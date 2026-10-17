-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- A read-only float opened from an Insert-mode key, and the way back into the
--- picker prompt it was opened from, in a real, UI-attached Neovim.
---
--- Entering a window keeps the mode. A `kit.viewer` opened by a picker's caller key
--- (bound in Insert and Normal mode, the prompt starts in Insert mode) stood in
--- Insert mode: `q` was typed (E21) instead of closing it. And once it was closed,
--- the prompt stood in Normal mode, so the next letter was a command (`x` deleted)
--- instead of going into the query. This runner never enters Insert mode, so the
--- keys go to a child Neovim over RPC, as in `ui_kit_input_ui_spec.lua`.

---@type integer|nil
local chan

--- Root of the first runtimepath entry that carries `rel`.
---@param rel string
---@return string
local function root_of(rel)
  local found =
    assert(vim.api.nvim_get_runtime_file(rel, false)[1], "not on the runtimepath: " .. rel)
  local dir = vim.fs.dirname(found)
  for _ = 1, select(2, rel:gsub("/", "/")) do
    dir = vim.fs.dirname(dir)
  end
  return dir
end

---@param code string
---@return any
local function lua(code)
  return vim.rpcrequest(chan, "nvim_exec_lua", code, {})
end

---@return table
local function state()
  return lua("return _G.detour_state()")
end

--- Poll until `cond(state)` holds; returns the state it held for.
---@param cond fun(s: table): boolean
---@param what string
---@return table
local function expect(cond, what)
  local last
  local ok = vim.wait(3000, function()
    last = state()
    return cond(last)
  end, 20)
  assert.is_true(ok, what .. " -- last state: " .. vim.inspect(last))
  return last
end

---@param keys string
local function input(keys)
  vim.rpcrequest(chan, "nvim_input", keys)
end

--- A picker whose caller keys open a viewer (`<C-v>`), a viewer after the caller
--- ended Insert mode itself (`<C-s>`), a float that is typed into (`<C-e>`), a
--- kit.input (`<C-t>`) and a nested picker (`<C-g>`).
local CHILD = [[
  vim.o.showmode = false
  local kit = require("ui.kit")
  local viewer = require("ui.kit.viewer")
  local api = vim.api

  function _G.detour_open()
    _G.V = nil
    _G.SUBMITTED = nil
    _G.P = kit.picker({
      items = { "alpha", "beta", "gamma" },
      on_submit = function() end,
      keys = {
        ["<C-v>"] = function()
          _G.V = viewer.open({ lines = { "details" } })
        end,
        ["<C-s>"] = function()
          vim.cmd("stopinsert")
          _G.V = viewer.open({ lines = { "details" } })
        end,
        ["<C-e>"] = function()
          _G.V = require("ui.kit.surface").open({
            lines = { "" },
            modifiable = true,
            width = 20,
            height = 1,
          })
        end,
        ["<C-t>"] = function()
          kit.input({
            prompt = "name",
            on_submit = function(line)
              _G.SUBMITTED = line
            end,
          })
        end,
        ["<C-g>"] = function()
          kit.picker({ items = { "inner" }, on_submit = function() end })
        end,
      },
    })
  end

  function _G.detour_state()
    local win = api.nvim_get_current_win()
    return {
      mode = api.nvim_get_mode().mode,
      in_prompt = win == _G.P.slots.prompt.winid,
      in_viewer = _G.V ~= nil and win == _G.V.winid,
      viewer_open = _G.V ~= nil and api.nvim_win_is_valid(_G.V.winid),
      query = _G.P.query(),
      col = api.nvim_win_get_cursor(0)[2],
    }
  end
]]

describe("a float opened from a picker's Insert-mode key", function()
  before_each(function()
    -- A Git-for-Windows `$SHELL` makes Neovim pick bash with cmd.exe's flags: the
    -- child gets the 'shell' every Windows user has (see ui_kit_input_ui_spec.lua).
    local env = vim.fn.environ()
    if vim.fn.has("win32") == 1 then
      env.SHELL = nil
    end
    chan = vim.fn.jobstart(
      { vim.v.progpath, "--embed", "-n", "-i", "NONE", "-u", "NONE" },
      { rpc = true, env = env, clear_env = true }
    )
    assert.is_true(chan > 0, "the child Neovim did not start")
    vim.rpcrequest(chan, "nvim_ui_attach", 100, 30, { rgb = true })
    vim.rpcrequest(
      chan,
      "nvim_exec_lua",
      [[
        local lib, ui = ...
        vim.opt.rtp:prepend(lib)
        vim.opt.rtp:prepend(ui)
      ]],
      { root_of("lua/lib/nvim/init.lua"), root_of("lua/ui/kit/init.lua") }
    )
    lua(CHILD)
    lua("_G.detour_open()")
    expect(function(s)
      return s.in_prompt and s.mode == "i"
    end, "the picker opens in its prompt, in Insert mode")
  end)

  after_each(function()
    if chan then
      pcall(vim.fn.jobstop, chan)
      chan = nil
    end
  end)

  it("opens a read-only viewer in Normal mode, q closes it, typing filters again", function()
    input("<C-v>")
    expect(function(s)
      return s.in_viewer and s.mode == "n"
    end, "a read-only viewer opened from Insert mode is in Normal mode")
    input("q")
    expect(function(s)
      return not s.viewer_open and s.in_prompt and s.mode == "i"
    end, "q closes the viewer on the first press, back in the prompt in Insert mode")
    input("x")
    expect(function(s)
      return s.query == "x"
    end, "the next letter goes into the query")
  end)

  it("closes the viewer on the first <Esc> too", function()
    input("<C-v>")
    expect(function(s)
      return s.in_viewer and s.mode == "n"
    end, "the viewer is focused in Normal mode")
    input("<Esc>")
    expect(function(s)
      return not s.viewer_open and s.in_prompt and s.mode == "i"
    end, "<Esc> closes the viewer, the prompt is in Insert mode")
    input("y")
    expect(function(s)
      return s.query == "y"
    end, "after <Esc> the next letter goes into the query")
  end)

  it("resumes Insert mode at the column it had", function()
    input("ab<Left>")
    expect(function(s)
      return s.query == "ab" and s.col == 1
    end, "the cursor stands between a and b")
    input("<C-v>")
    expect(function(s)
      return s.in_viewer
    end, "the viewer is focused")
    input("q")
    expect(function(s)
      return s.in_prompt and s.mode == "i"
    end, "back in the prompt")
    input("x")
    expect(function(s)
      return s.query == "axb"
    end, "typing resumes at the column Insert mode had")
  end)

  it("appends at the end of the query", function()
    input("ab")
    input("<C-v>")
    expect(function(s)
      return s.in_viewer
    end, "the viewer is focused")
    input("q")
    expect(function(s)
      return s.in_prompt and s.mode == "i"
    end, "back in the prompt")
    input("c")
    expect(function(s)
      return s.query == "abc"
    end, "at the end of the query typing appends")
  end)

  it("takes the same way back after the caller's own :stopinsert", function()
    input("<C-s>")
    expect(function(s)
      return s.in_viewer and s.mode == "n"
    end, "the viewer is in Normal mode")
    input("q")
    expect(function(s)
      return s.in_prompt and s.mode == "i"
    end, "the prompt is back in Insert mode")
    input("z")
    expect(function(s)
      return s.query == "z"
    end, "the next letter goes into the query")
  end)

  it("gives a prompt left from Normal mode back in Normal mode", function()
    input("<C-\\><C-n>")
    expect(function(s)
      return s.in_prompt and s.mode == "n"
    end, "the prompt is in Normal mode")
    input("<C-v>")
    expect(function(s)
      return s.in_viewer
    end, "the viewer is focused")
    input("q")
    local s = expect(function(st)
      return st.in_prompt and not st.viewer_open
    end, "the viewer closed back into the prompt")
    assert.equals("n", s.mode, "a prompt left from Normal mode is not put into Insert mode")
    -- and it stays so once the keys are through
    vim.wait(100)
    assert.equals("n", state().mode, "still in Normal mode")
  end)

  -- A window that is typed into closes back into the prompt while its own Insert mode is
  -- still on, and its closer ends that Insert mode right after: the prompt still gets it back.
  it("resumes Insert mode at its column after a kit.input", function()
    input("ab<Left>")
    expect(function(s)
      return s.query == "ab" and s.col == 1
    end, "the cursor stands between a and b")
    input("<C-t>")
    expect(function(s)
      return not s.in_prompt and s.mode == "i"
    end, "the kit.input is focused in Insert mode")
    -- one batch: the resume must run before the letter, not after it
    input("foo<CR>x")
    local s = expect(function(st)
      return st.in_prompt and st.query ~= "ab"
    end, "back in the prompt, the letter typed")
    assert.equals("foo", lua("return _G.SUBMITTED"), "the kit.input submitted what was typed")
    assert.equals("i", s.mode, "back from a kit.input, the prompt is in Insert mode")
    assert.equals("axb", s.query, "typing resumes at the column Insert mode had")
  end)

  it("resumes Insert mode after a cancelled kit.input", function()
    input("ab")
    input("<C-t>")
    expect(function(s)
      return not s.in_prompt and s.mode == "i"
    end, "the kit.input is focused in Insert mode")
    input("foo<Esc>x")
    local s = expect(function(st)
      return st.in_prompt and st.query ~= "ab"
    end, "back in the prompt, the letter typed")
    assert.equals("i", s.mode, "back from a cancelled kit.input, the prompt is in Insert mode")
    assert.equals("abx", s.query, "after a cancelled kit.input, typing appends")
  end)

  it("resumes Insert mode after a nested picker", function()
    input("ab")
    input("<C-g>")
    expect(function(s)
      return not s.in_prompt
    end, "the nested picker is focused")
    input("<Esc>x")
    local s = expect(function(st)
      return st.in_prompt and st.query ~= "ab"
    end, "back in the prompt, the letter typed")
    assert.equals("i", s.mode, "back from a nested picker, the prompt is in Insert mode")
    assert.equals("abx", s.query, "after a nested picker, the next letter goes into the query")
  end)

  it("keeps Insert mode in a float that is typed into", function()
    input("<C-e>")
    expect(function(st)
      return st.in_viewer
    end, "the modifiable float is focused")
    vim.wait(100)
    assert.equals(
      "i",
      state().mode,
      "a modifiable float opened from Insert mode stays in Insert mode"
    )
  end)
end)
