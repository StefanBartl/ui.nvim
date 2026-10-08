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

  describe("which mode the window a callback opens is in", function()
    --- A prompt whose `on_submit` runs `opener` (Lua, in the child), answered with
    --- `x<CR>`; the state once the dust of the mode change has settled.
    ---@param opener string
    ---@return table
    local function after_submit(opener)
      lua(([[
        _G.RESULT = nil
        require("ui.kit").input({
          on_submit = function(v)
            _G.RESULT = v
            %s
          end,
        })
      ]]):format(opener))
      expect(function(s)
        return s.mode == "i"
      end, "the first prompt opens in Insert mode")
      input("x<CR>")
      expect(function(s)
        return s.result == "x"
      end, "the first prompt is answered")
      vim.wait(200) -- `stopinsert` (or its absence) lands once the mapping has returned
      return state()
    end

    -- A window to be typed into is opened in Insert mode: the prompt that closes
    -- must not stop the Insert mode that the new window's own `startinsert` could not
    -- re-enter (it is ignored while the old one's is still on).
    for name, opener in pairs({
      ["another prompt"] = [[ require("ui.kit").input({}) ]],
      ["a sheet whose first field is text"] = [[
        require("ui.kit").sheet({ fields = { { name = "a" } }, on_submit = function() end })
      ]],
      ["a picker"] = [[
        require("ui.kit").picker({ on_change = function() end, on_submit = function() end })
      ]],
      ["a live_input"] = [[ require("ui.kit").live_input({ on_change = function() end }) ]],
      ["a compare"] = [[
        require("ui.kit").compare({
          items = { "a", "b" },
          render = function(item, surface) surface:set_lines({ item }) end,
        })
      ]],
    }) do
      it("is Insert mode for " .. name, function()
        local s = after_submit(opener)
        assert.equals("i", s.mode, "the new window is typed into, not commanded")
      end)
    end

    -- Nothing that waits for typing: the prompt's Insert mode must end.
    for name, opener in pairs({
      ["nothing"] = [[ ]],
      ["a chooser"] = [[
        require("ui.kit.select").open({ items = { "a", "b" }, on_select = function() end })
      ]],
      ["a sheet that starts on a select"] = [[
        require("ui.kit").sheet({
          fields = { { name = "a", kind = "select", choices = { "x", "y" } } },
          on_submit = function() end,
        })
      ]],
    }) do
      it("is Normal mode for " .. name, function()
        local s = after_submit(opener)
        assert.equals("n", s.mode, "no Insert mode is left behind")
      end)
    end

    it("is Insert mode for the sheet that follows the last field of a form", function()
      lua([[
        _G.RESULT = nil
        require("ui.kit").form({
          fields = { { name = "a" } },
          on_submit = function(v)
            _G.RESULT = v.a
            require("ui.kit").sheet({ fields = { { name = "b" } }, on_submit = function() end })
          end,
        })
      ]])
      expect(function(s)
        return s.mode == "i"
      end, "the form opens in Insert mode")
      input("x<CR>")
      expect(function(s)
        return s.result == "x"
      end, "the form is answered")
      vim.wait(200)
      assert.equals("i", state().mode)
    end)

    it("leaves a window that was there before as it was, when a sheet closes over it", function()
      -- A modifiable float in Normal mode opens a sheet and the sheet is cancelled: the
      -- focus goes back to the float, which was never in Insert mode. It is a
      -- modifiable float all the same, and used to be taken for the next prompt of a
      -- chain, so the Insert mode of the sheet was left running in it.
      lua([[
        _G.RESULT = nil
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_open_win(buf, true, { relative = "editor", row = 2, col = 2, width = 20, height = 3 })
        _G.ORIGIN = vim.api.nvim_get_current_win()
        require("ui.kit").sheet({
          fields = { { name = "a" } },
          on_submit = function() end,
          on_cancel = function() _G.RESULT = "cancelled" end,
        })
      ]])
      expect(function(s)
        return s.mode == "i"
      end, "the sheet opens in Insert mode")
      input("<Esc>")
      expect(function(s)
        return s.result == "cancelled"
      end, "the sheet is cancelled")
      vim.wait(200)
      assert.is_true(
        lua([[return vim.api.nvim_get_current_win() == _G.ORIGIN]]),
        "back in the float"
      )
      assert.equals("n", state().mode, "which is still in Normal mode")
    end)

    it("leaves a window that was there before as it was, when a prompt closes over it", function()
      lua([[
        _G.RESULT = nil
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_open_win(buf, true, { relative = "editor", row = 2, col = 2, width = 20, height = 3 })
        _G.ORIGIN = vim.api.nvim_get_current_win()
        require("ui.kit").input({ on_submit = function(v) _G.RESULT = v end })
      ]])
      expect(function(s)
        return s.mode == "i"
      end, "the prompt opens in Insert mode")
      input("x<CR>")
      expect(function(s)
        return s.result == "x"
      end, "the prompt is answered")
      vim.wait(200)
      assert.is_true(
        lua([[return vim.api.nvim_get_current_win() == _G.ORIGIN]]),
        "back in the float"
      )
      assert.equals("n", state().mode)
    end)
  end)

  describe("a secret typed into a prompt", function()
    --- The `.` register in the child.
    ---@return string
    local function dot()
      return lua([[return vim.fn.getreg(".")]])
    end

    --- What `.` does to a buffer with `hello` in it, in the child.
    ---@return string
    local function dot_repeat()
      lua([[
        vim.cmd("enew")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
        vim.cmd("normal! gg0")
      ]])
      input(".")
      vim.wait(200)
      return lua([[return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] ]])
    end

    ---@param extra string  # more options for the prompt, as Lua
    local function open_secret(extra)
      lua(([[
        _G.RESULT = nil
        require("ui.kit").input(vim.tbl_extend("force", {
          secret = true,
          on_submit = function(v) _G.RESULT = v end,
          on_cancel = function() _G.RESULT = "cancelled" end,
        }, %s))
      ]]):format(extra or "{}"))
      expect(function(s)
        return s.mode == "i"
      end, "the secret prompt opens in Insert mode")
    end

    it("is gone from the . register and from what . replays once the prompt submits", function()
      open_secret()
      input("hunter2<CR>")
      expect(function(s)
        return s.result == "hunter2"
      end, "the prompt hands the secret on")
      vim.wait(300) -- the scrub runs once the Insert run has ended
      assert.equals("", dot(), "nothing is left in the register")
      assert.equals("hello", dot_repeat(), ". types nothing into another buffer")
    end)

    it("is gone once the prompt is cancelled", function()
      open_secret()
      input("hunt<Esc>")
      expect(function(s)
        return s.result == "cancelled"
      end, "the prompt is cancelled")
      vim.wait(300)
      assert.equals("", dot())
      assert.equals("hello", dot_repeat())
    end)

    it("is gone once a chain of prompts that began with it has ended", function()
      -- The Insert run goes on into the next prompt: the scrub waits for its end.
      lua([[
        _G.RESULT = nil
        _G.SECOND = nil
        require("ui.kit").input({
          secret = true,
          on_submit = function(v)
            _G.RESULT = v
            require("ui.kit").input({ on_submit = function(w) _G.SECOND = w end })
          end,
        })
      ]])
      expect(function(s)
        return s.mode == "i"
      end, "the secret prompt opens in Insert mode")
      input("hunter2<CR>")
      expect(function(s)
        return s.result == "hunter2"
      end, "the secret prompt is answered")
      vim.wait(200)
      assert.equals("i", state().mode, "and the next prompt is typed into")
      input("abc<CR>")
      vim.wait(400)
      assert.equals("abc", lua([[return _G.SECOND]]), "its answer is untouched by the scrub")
      assert.equals("", dot())
      assert.equals("hello", dot_repeat())
    end)

    it("is gone after a chain whose next prompt was left for a <C-o> command", function()
      -- <C-o> fires InsertLeave and carries the Insert run on all the same: the scrub
      -- must wait for the end of the run, not for that first InsertLeave.
      lua([[
        _G.RESULT = nil
        _G.SECOND = nil
        require("ui.kit").input({
          secret = true,
          on_submit = function(v)
            _G.RESULT = v
            require("ui.kit").input({ on_cancel = function() _G.SECOND = "cancelled" end })
          end,
        })
      ]])
      expect(function(s)
        return s.mode == "i"
      end, "the secret prompt opens in Insert mode")
      input("hunter2<CR>")
      expect(function(s)
        return s.result == "hunter2"
      end, "the secret prompt is answered")
      vim.wait(200)
      input("abc<C-o>")
      expect(function(s)
        return s.mode:sub(1, 2) == "ni"
      end, "the next prompt waits for a command")
      vim.wait(300) -- the scrub, were it armed on the first InsertLeave, runs now
      input("<Esc>") -- the prompt's own <Esc>: cancels it, and the run ends
      expect(function()
        return lua([[return _G.SECOND == "cancelled"]])
      end, "the next prompt is cancelled")
      vim.wait(400)
      assert.equals("", dot(), "nothing of the run is left once it has ended")
      assert.equals("hello", dot_repeat())
    end)

    it("is no business of a prompt without a secret", function()
      lua([[
        _G.RESULT = nil
        require("ui.kit").input({ on_submit = function(v) _G.RESULT = v end })
      ]])
      expect(function(s)
        return s.mode == "i"
      end, "the prompt opens in Insert mode")
      input("plain<CR>")
      expect(function(s)
        return s.result == "plain"
      end, "the prompt is answered")
      vim.wait(300)
      assert.equals("plain", dot(), "the last Insert run is the user's own")
    end)
  end)

  -- Insert-mode completion works on the words of the buffer, and in a secret prompt the buffer is
  -- the secret: `<C-n>`/`<C-p>` listed them in clear text and put the pick in unmasked, and with
  -- 'autocomplete' (Neovim 0.12) the popup came up by itself as one types. They do nothing there
  -- now (`ui_kit_secret_buffer_spec.lua` has the keys without a popup to look at).
  describe("a secret prompt and the completion popup", function()
    local TYPED = "hunter2 hunter3 hun"

    --- `autocomplete` is a Neovim 0.12 option: the child is the same binary as this one.
    local has_autocomplete = vim.fn.exists("&autocomplete") == 1

    --- How many characters the line holds and how many of them are under a mask.
    ---@return table
    local function masked()
      return lua([[
        local b = vim.api.nvim_get_current_buf()
        local ns = vim.api.nvim_create_namespace("lib_kit_input_secret_" .. b)
        return {
          marks = #vim.api.nvim_buf_get_extmarks(b, ns, 0, -1, {}),
          chars = vim.fn.strchars(vim.api.nvim_buf_get_lines(b, 0, 1, false)[1]),
        }
      ]])
    end

    --- Press `keys`, then `!`: the line must be what was typed and the `!`, and no popup may be
    --- open. One sequence at a time, and the `!` taken out again: several completion keys in a row
    --- (`<C-n><C-p>`) cancel each other out and would hide a candidate that was put in.
    ---@param keys string
    local function nothing_completes(keys)
      input(keys .. "!")
      local s = expect(function(x)
        return x.lines[1] == TYPED .. "!"
      end, keys .. " inserted nothing")
      assert.is_false(s.pum, keys .. " opened no popup")
      input("<BS>")
      expect(function(x)
        return x.lines[1] == TYPED
      end, "the character is taken out again")
    end

    ---@param autocomplete boolean
    ---@param secret boolean
    local function open_typing(autocomplete, secret)
      if has_autocomplete then
        lua(("vim.o.autocomplete = %s"):format(tostring(autocomplete)))
      end
      lua(
        ([[ require("ui.kit").input({ secret = %s, relative = "editor" }) ]]):format(
          tostring(secret)
        )
      )
      expect(function(s)
        return s.mode == "i"
      end, "the prompt opens in Insert mode")
      input(TYPED)
      expect(function(s)
        return s.lines[1] == TYPED
      end, "the words are typed")
    end

    for _, autocomplete in ipairs(has_autocomplete and { false, true } or { false }) do
      local label = ("'autocomplete' %s"):format(autocomplete and "on" or "off")

      it("offers no word of the buffer, " .. label, function()
        open_typing(autocomplete, true)
        vim.wait(300) -- the popup of 'autocomplete' comes after the key that asked for it
        assert.is_false(state().pum, "no popup while typing")
        for _, keys in ipairs({ "<C-n>", "<C-p>", "<C-x><C-n>", "<C-x><C-p>" }) do
          nothing_completes(keys)
        end
      end)

      it("(control) a plain prompt does, " .. label, function()
        open_typing(autocomplete, false)
        if not autocomplete then
          input("<C-n>")
        end
        expect(function(s)
          return s.pum
        end, "the popup lists the words: without this the test above sees nothing either way")
      end)
    end

    it(
      "keeps the popup of its own completion, moves in it with <C-n>/<C-p>, and masks the pick",
      function()
        for _, name in ipairs({ "alpha1.txt", "alpha2.txt" }) do
          local f = assert(io.open(tmp .. "/" .. name, "w"))
          f:write("")
          f:close()
        end
        lua(([[
        vim.cmd("cd " .. vim.fn.fnameescape(%q))
        require("ui.kit").input({ secret = true, completion = "file", default = "al", relative = "editor" })
      ]]):format(tmp:gsub("\\", "/")))
        expect(function(s)
          return s.mode == "i"
        end, "the prompt opens in Insert mode")
        input("<Tab>")
        local s = expect(function(x)
          return x.pum and x.lines[1]:match("^alpha[12]%.txt$") ~= nil
        end, "<Tab> opens the popup, with the first candidate in")
        local first = s.lines[1]
        input("<C-n>")
        s = expect(function(x)
          return x.lines[1]:match("^alpha[12]%.txt$") ~= nil and x.lines[1] ~= first
        end, "<C-n> goes on to the next candidate")
        assert.is_true(s.pum, "the popup stays open")
        -- The pick is a change made with the popup open (`TextChangedP`): masked all the same.
        local m = masked()
        assert.equals(m.chars, m.marks, "every character of the pick is under a mask")
        assert.is_true(m.chars > 2, "and it is more than what was typed")
        input("<C-p>")
        expect(function(x)
          return x.lines[1] == first
        end, "<C-p> goes back")
        m = masked()
        assert.equals(m.chars, m.marks, "the one it went back to is masked too")
      end
    )

    it("offers nothing from the buffer in a sheet with a secret field either", function()
      lua([[
        require("ui.kit").sheet({
          fields = { { name = "token", secret = true }, { name = "note" } },
          relative = "editor",
          on_submit = function() end,
        })
      ]])
      expect(function(s)
        return s.mode == "i"
      end, "the sheet opens in Insert mode")
      input(TYPED)
      expect(function(s)
        return s.lines[1] == TYPED
      end, "the words are typed")
      for _, keys in ipairs({ "<C-n>", "<C-x><C-n>" }) do
        nothing_completes(keys)
      end
    end)
  end)
end)
