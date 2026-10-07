-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `kit.input` in a real, UI-attached Neovim.
---
--- `ui_kit_spec.lua` drives the prompt from Normal mode with `vim.fn.complete`
--- and `vim.fn.getcompletion` stubbed, because this runner has no UI and never
--- enters Insert mode. That hides what only a real Insert-mode session shows:
--- whether `<Tab>` really opens the completion popup (the mapping used to be an
--- `<expr>` one, under whose textlock `complete()` raises E565 -- the pcall around it
--- swallowed that and the key did nothing), and what a pasted backtick does to
--- the unstubbed `getcompletion()`. So this file starts a child Neovim with
--- `--embed`, attaches a UI to it so that its main loop runs for real, and
--- talks to it over RPC -- the way `ui_kit_form_back_ui_spec.lua` does for
--- `kit.form` and `ui_kit_sheet_ui_spec.lua` for `kit.sheet`.

---@type integer|nil
local chan
---@type string|nil
local tmp

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

--- What a person would see of the focused float.
---@return table
local function state()
  return lua([[
    return {
      mode = vim.api.nvim_get_mode().mode,
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
      pum = vim.fn.pumvisible() == 1,
      result = _G.RESULT,
    }
  ]])
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

describe("kit.input in a real Neovim", function()
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
      "--cmd",
      "set mouse=a",
    }, { rpc = true, env = env, clear_env = true })
    assert.is_true(chan > 0, "the child Neovim did not start")
    vim.rpcrequest(chan, "nvim_ui_attach", 100, 30, { rgb = true })
    -- Over RPC, not as `--cmd "set rtp^=<dir>"`: `:set` splits at a space and at a
    -- comma, and a checkout under `C:\Users\First Last\...` has the one.
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
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
  end)

  after_each(function()
    if chan then
      pcall(vim.fn.jobstop, chan)
      chan = nil
    end
    if tmp then
      vim.fn.delete(tmp, "rf")
      tmp = nil
    end
  end)

  --- A prompt with `completion = "file"` in the child, whose working directory
  --- holds two files that share a prefix.
  ---@param default string
  local function open_completing(default)
    for _, name in ipairs({ "alpha1.txt", "alpha2.txt" }) do
      local f = assert(io.open(tmp .. "/" .. name, "w"))
      f:write("")
      f:close()
    end
    lua(([[
      vim.cmd("cd " .. vim.fn.fnameescape(%q))
      _G.RESULT = nil
      require("ui.kit").input({
        completion = "file",
        default = %q,
        on_submit = function(v) _G.RESULT = v end,
      })
    ]]):format(tmp:gsub("\\", "/"), default))
    expect(function(s)
      return s.mode == "i"
    end, "the prompt opens in Insert mode")
  end

  it("opens the completion popup on <Tab> and completes from it", function()
    open_completing("al")
    input("<Tab>")
    expect(function(s)
      return s.pum
    end, "<Tab> opens the popup (it did nothing when the mapping was an <expr> one)")
    input("<Tab>")
    expect(function(x)
      return x.lines[1]:match("^alpha[12]%.txt$") ~= nil
    end, "a second <Tab> takes a candidate")
    input("<CR>") -- accepts the highlighted candidate, does not submit
    expect(function(x)
      return not x.pum
    end, "<CR> closes the popup")
    assert.is_nil(state().result, "and does not submit yet")
    input("<CR>")
    local s = expect(function(x)
      return x.result ~= nil
    end, "a second <CR> submits")
    assert.truthy(s.result:match("^alpha[12]%.txt$"), "the completed name: " .. s.result)
  end)

  it("opens the popup from an empty field too", function()
    open_completing("")
    input("<Tab>")
    expect(function(s)
      return s.pum
    end, "<Tab> on an empty field lists what the directory holds")
  end)

  it("never lets a pasted backtick span reach the shell", function()
    open_completing("")
    -- A token without whitespace (it has to survive as one fragment). Whichever
    -- shell runs the span, `getcompletion()` used to execute it: `touch` under a
    -- POSIX shell, `md` under cmd.exe. Each is tried on its own: the one that
    -- cannot work here does no harm, and the other is what the guard must stop.
    local posix = tmp:gsub("\\", "/") .. "/pwned_sh"
    local cmd = tmp:gsub("/", "\\") .. "\\pwned_cmd"
    for _, payload in ipairs({
      ("`touch${IFS}%s`"):format(posix),
      ("`md,%s`"):format(cmd),
    }) do
      lua(([[
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { %q })
        vim.api.nvim_win_set_cursor(0, { 1, #%q })
      ]]):format(payload, payload))
      input("<Tab>")
      -- Barrier: a key whose effect is visible, queued behind the <Tab>.
      input("x")
      expect(function(s)
        return s.lines[1] == payload .. "x"
      end, "the <Tab> was handled and nothing was inserted by it")
      vim.wait(300)
    end
    assert.is_nil(vim.uv.fs_stat(tmp .. "/pwned_sh"), "no command ran (POSIX shell)")
    assert.is_nil(vim.uv.fs_stat(tmp .. "/pwned_cmd"), "no command ran (cmd.exe)")
  end)
end)
