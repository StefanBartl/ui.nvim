-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `kit.async` with real typed keys, in a child Neovim with a UI attached.
---
--- `kit.sync` waits in `vim.wait()`, and Neovim does not run typed keys while it waits, so a dialog
--- opened that way never sees them (it returns when its timeout runs out). A spec in this
--- process cannot show the difference: it has no UI and feeds keys with `feedkeys`. So this file
--- starts a child Neovim the way `ui_kit_input_ui_spec.lua` does, types into it over RPC and reads
--- what the coroutine got back -- and that the editor kept running meanwhile.

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

---@param keys string
local function input(keys)
  vim.rpcrequest(chan, "nvim_input", keys)
end

--- Poll the child until `cond(state)` holds; returns the state it held for.
---@param cond fun(s: table): boolean
---@param what string
---@return table
local function expect(cond, what)
  local last
  local ok = vim.wait(5000, function()
    last = lua([[
      local confirm = require("ui.kit.confirm")
      return {
        mode = vim.api.nvim_get_mode().mode,
        confirm_open = confirm.is_open(),
        result = _G.RESULT,
        ticks = _G.TICKS or 0,
      }
    ]])
    return cond(last)
  end, 20)
  assert.is_true(ok, what .. " -- last state: " .. vim.inspect(last))
  return last
end

describe("kit.async with typed keys", function()
  before_each(function()
    -- A Git-for-Windows `$SHELL` makes Neovim pick bash with cmd.exe's flags, and no
    -- command line runs at all: the child gets the 'shell' every Windows user has.
    local env = vim.fn.environ()
    if vim.fn.has("win32") == 1 then
      env.SHELL = nil
    end
    chan = vim.fn.jobstart({
      vim.v.progpath,
      "--embed",
      "-n",
      "-i",
      "NONE",
      "-u",
      "NONE",
    }, { rpc = true, env = env, clear_env = true })
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
  end)

  after_each(function()
    if chan then
      pcall(vim.fn.jobstop, chan)
      chan = nil
    end
  end)

  it(
    "an input and a confirm in one coroutine take typed keys, and the editor keeps running",
    function()
      lua([[
      _G.RESULT = nil
      _G.TICKS = 0
      -- proof that the main loop runs while the coroutine waits for the user
      local timer = vim.uv.new_timer()
      timer:start(0, 30, vim.schedule_wrap(function() _G.TICKS = _G.TICKS + 1 end))
      local kit = require("ui.kit")
      kit.async.run(function()
        local name, cancelled = kit.async.input({ prompt = "Name" })
        local yes = kit.async.confirm({ question = "Create " .. tostring(name) .. "?" })
        _G.RESULT = { name = name, cancelled = cancelled, yes = yes }
      end)
    ]])

      local s = expect(function(st)
        return st.mode == "i"
      end, "the input is open and takes keys")
      local ticks_before = s.ticks
      input("abc<CR>")

      expect(function(st)
        return st.confirm_open
      end, "the question that follows the answer opens")
      local mid = expect(function(st)
        return st.ticks > ticks_before
      end, "the editor kept running while the coroutine waited")
      assert.is_nil(mid.result, "the coroutine has not finished before the question is answered")

      input("<CR>") -- the focused button: Yes
      local done = expect(function(st)
        return st.result ~= nil
      end, "the coroutine finishes")
      assert.are.same({ name = "abc", cancelled = false, yes = true }, done.result)
    end
  )

  it("a cancelled input comes back as nil, true and the coroutine can stop there", function()
    lua([[
      _G.RESULT = nil
      local kit = require("ui.kit")
      kit.async.run(function()
        local name, cancelled = kit.async.input({ prompt = "Name" })
        _G.RESULT = { name = name == nil and "nil" or name, cancelled = cancelled }
      end)
    ]])
    expect(function(st)
      return st.mode == "i"
    end, "the input is open and takes keys")
    input("<Esc>")
    local done = expect(function(st)
      return st.result ~= nil
    end, "the coroutine finishes")
    assert.are.same({ name = "nil", cancelled = true }, done.result)
  end)
end)
