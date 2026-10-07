-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.slots.kinds` -- the registry and the kinds `file`, `yank`, `url`.

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local store = require("ui.slots.store")

describe("ui.slots.kinds", function()
  local dir
  local messages
  local original_notify

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    messages = {}
    original_notify = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    registry.reset()
    store.reset()
    config.setup({ data_dir = dir .. "/data", save_delay_ms = 0 })
    require("ui.slots.kinds.file").forget_positions()
    vim.cmd("silent! %bwipeout!")
  end)

  after_each(function()
    vim.notify = original_notify
    registry.reset()
    store.reset()
    config.reset()
    vim.cmd("silent! only")
    vim.cmd("silent! tabonly")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  ---@param name string
  ---@param lines string[]|nil
  ---@return string path
  local function make_file(name, lines)
    local path = dir .. "/" .. name
    vim.fn.writefile(lines or { "one", "two", "three" }, path)
    -- The canonical spelling: Neovim names a buffer by it (on macOS /var is a
    -- link to /private/var), so a test must compare in that one spelling.
    return require("lib.nvim.fs.normkey")(path)
  end

  ---@param path string
  local function slots_add_file(path)
    store.add({ kind = "file", path = path })
  end

  ---@return string
  local function current_name()
    return require("lib.nvim.fs.normkey")(vim.api.nvim_buf_get_name(0))
  end

  describe("registry", function()
    it("loads the built-in kinds on first use and registers nothing before", function()
      assert.same({ "cmd", "file", "lua", "mark", "url", "yank" }, registry.names())
    end)

    it("registers a kind, refuses a second one of the same name unless forced", function()
      local first = { apply = function() end }
      assert.is_true(registry.register("mine", first))
      local ok, err = registry.register("mine", { apply = function() end })
      assert.is_false(ok)
      assert.is_truthy(err:find("already", 1, true))
      assert.equals(first, registry.get("mine"))
      assert.is_true(registry.register("mine", { apply = function() end }, { force = true }))
      assert.is_not.equals(first, registry.get("mine"))
    end)

    it("refuses a built-in name too, so a host replaces it on purpose with force", function()
      local ok = registry.register("file", { apply = function() end })
      assert.is_false(ok)
      assert.is_true(registry.register("file", { apply = function() end }, { force = true }))
    end)

    it("validates a kind when it is registered", function()
      assert.is_false((registry.register("x", "no")))
      assert.is_false((registry.register("x", {})))
      assert.is_false((registry.register("x", { apply = function() end, render = 1 })))
      assert.is_false((registry.register("x", { apply = function() end, persist = "yes" })))
      assert.is_false((registry.register("bad name", { apply = function() end })))
      assert.is_false((registry.register(5, { apply = function() end })))
    end)

    it("load() registers a map and reports the kinds it refused", function()
      local errors = registry.load({ good = { apply = function() end }, bad = { nope = 1 } })
      assert.equals(1, #errors)
      assert.is_truthy(errors[1]:find("bad", 1, true))
      assert.is_not_nil(registry.get("good"))
    end)

    it("unregister() and reset() forget kinds", function()
      registry.register("mine", { apply = function() end })
      assert.is_true(registry.unregister("mine"))
      assert.is_false(registry.unregister("mine"))
      registry.reset()
      assert.same({ "cmd", "file", "lua", "mark", "url", "yank" }, registry.names())
    end)

    it("apply() reports an unknown kind and a slot the kind refuses", function()
      local ok, err = registry.apply({ kind = "nope" })
      assert.is_false(ok)
      assert.is_truthy(err:find("unknown kind", 1, true))
      ok, err = registry.apply({ kind = "file" })
      assert.is_false(ok)
      assert.is_truthy(err:find("path", 1, true))
    end)

    it("apply() hands the kind the slot and a context, and passes its failure on", function()
      local seen
      registry.register("probe", {
        apply = function(slot, ctx)
          seen = { slot = slot, ctx = ctx }
          return false, "nope"
        end,
      })
      local ok, err = registry.apply({ kind = "probe", n = 4 }, { count = 7 })
      assert.is_false(ok)
      assert.equals("nope", err)
      assert.equals(4, seen.slot.n)
      assert.equals(7, seen.ctx.resolve.count())
    end)

    it("apply() turns an error raised inside a kind into false, err", function()
      registry.register("boom", {
        apply = function()
          error("kaboom")
        end,
      })
      local ok, err = registry.apply({ kind = "boom" })
      assert.is_false(ok)
      assert.is_truthy(err:find("kaboom", 1, true))
    end)

    it("apply() treats nil, err as a failure too", function()
      registry.register("legacy", {
        apply = function()
          return nil, "went wrong"
        end,
      })
      local ok, err = registry.apply({ kind = "legacy" })
      assert.is_false(ok)
      assert.equals("went wrong", err)
    end)

    it("apply() treats a kind that returns nothing as success", function()
      registry.register("quiet", { apply = function() end })
      assert.is_true((registry.apply({ kind = "quiet" })))
    end)

    it("apply() survives a validate that raises", function()
      registry.register("shaky", {
        apply = function() end,
        validate = function()
          error("bad validate")
        end,
      })
      local ok, err = registry.apply({ kind = "shaky" })
      assert.is_false(ok)
      assert.is_truthy(err:find("bad validate", 1, true))
    end)

    it("render() lets the slot's own label and icon win over the kind's", function()
      registry.register("pretty", {
        apply = function() end,
        render = function()
          return { label = "kind label", icon = "K", hl = "KitAccent" }
        end,
      })
      local r = registry.render({ kind = "pretty" })
      assert.equals("kind label", r.label)
      assert.equals("K", r.icon)
      assert.equals("KitAccent", r.hl)
      r = registry.render({ kind = "pretty", label = "mine", icon = "M" })
      assert.equals("mine", r.label)
      assert.equals("M", r.icon)
    end)

    it("render() has a fallback for an unregistered kind and a raising render", function()
      local r = registry.render({ kind = "ghost" })
      assert.equals("ghost", r.label)
      assert.is_true(r.missing)
      assert.equals("KitError", r.hl)
      registry.register("shaky", {
        apply = function() end,
        render = function()
          error("x")
        end,
      })
      assert.equals("shaky", registry.render({ kind = "shaky" }).label)
    end)

    it("preview() is nil without one and survives a raising one", function()
      registry.register("plain", { apply = function() end })
      assert.is_nil(registry.preview({ kind = "plain" }))
      registry.register("shaky", {
        apply = function() end,
        preview = function()
          error("x")
        end,
      })
      assert.is_nil(registry.preview({ kind = "shaky" }))
    end)

    it("lets a kind with persist = true be written to the data file, others not", function()
      registry.register("keeps", { apply = function() end, persist = true })
      registry.register("runs", { apply = function() end })
      config.setup({ data_dir = dir .. "/data", save_delay_ms = 0 })
      store.reload()
      store.add({ kind = "keeps", a = 1 })
      store.add({ kind = "runs", a = 2 })
      assert.is_true(store.flush())
      local data = vim.json.decode(table.concat(vim.fn.readfile(store.path()), "\n"))
      assert.equals(1, #data.slots)
      assert.equals("keeps", data.slots[1].kind)
    end)
  end)

  describe("file", function()
    local file = require("ui.slots.kinds.file")

    it("opens the file in the current window", function()
      local path = make_file("a.txt")
      local win = vim.api.nvim_get_current_win()
      assert.is_true((registry.apply({ kind = "file", path = path })))
      assert.equals(path, current_name())
      assert.equals(win, vim.api.nvim_get_current_win())
    end)

    it("honours the config's target and a slot's own target over it", function()
      local path = make_file("a.txt")
      config.setup({ target = "vsplit" })
      registry.apply({ kind = "file", path = path })
      assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
      vim.cmd("only")
      registry.apply({ kind = "file", path = path, target = "tab" })
      assert.equals(2, #vim.api.nvim_list_tabpages())
      vim.cmd("tabonly")
      config.setup({ target = "current" })
      registry.apply({ kind = "file", path = path, target = "split" })
      assert.equals(2, #vim.api.nvim_tabpage_list_wins(0))
    end)

    it("reports a file that is not there and does not create it", function()
      local path = dir .. "/missing.txt"
      local ok, err = registry.apply({ kind = "file", path = path })
      assert.is_false(ok)
      assert.is_truthy(err:find("does not exist", 1, true))
      assert.equals(0, vim.fn.filereadable(path))
    end)

    it("opens a path with spaces and characters that are special to :edit", function()
      local path = make_file("my file #1 %x.txt")
      assert.is_true((registry.apply({ kind = "file", path = path })))
      assert.equals(path, current_name())
    end)

    it("puts placeholders into the path", function()
      local path = make_file("p.txt")
      local ok = registry.apply(
        { kind = "file", path = "{dir}/p.txt" },
        { resolve = { dir = vim.fs.dirname(path) } }
      )
      assert.is_true(ok)
      assert.equals(path, current_name())
    end)

    it("says which placeholder it did not know", function()
      make_file("p.txt")
      registry.apply({ kind = "file", path = dir .. "/{nope}.txt" })
      assert.is_truthy(table.concat(messages, "\n"):find("{nope}", 1, true))
    end)

    it("fails cleanly when the current buffer cannot be left", function()
      local path = make_file("a.txt")
      local hidden = vim.o.hidden
      vim.o.hidden = false
      vim.cmd("enew")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
      local ok, err = registry.apply({ kind = "file", path = path })
      vim.o.hidden = hidden
      assert.is_false(ok)
      assert.is_truthy(err:find("E37", 1, true))
    end)

    it("jumps to the slot's line and column, clamped to the buffer", function()
      local path = make_file("a.txt", { "alpha", "beta", "gamma" })
      registry.apply({ kind = "file", path = path, line = 2, col = 3 })
      assert.same({ 2, 2 }, vim.api.nvim_win_get_cursor(0))
      vim.cmd("enew")
      registry.apply({ kind = "file", path = path, line = 99, col = 99 })
      assert.same({ 3, 4 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("goes back to where the cursor was when the file was last left", function()
      local path = make_file("a.txt", { "alpha", "beta", "gamma" })
      registry.apply({ kind = "file", path = path })
      vim.api.nvim_win_set_cursor(0, { 3, 2 })
      file.remember_current()
      vim.cmd("enew")
      registry.apply({ kind = "file", path = path })
      assert.same({ 3, 2 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("writes the position into a slot of the data file, but not into a fixed one", function()
      local path = make_file("a.txt", { "alpha", "beta", "gamma" })
      config.setup({
        data_dir = dir .. "/data",
        save_delay_ms = 0,
        slots = { [1] = { kind = "file", path = path } },
      })
      store.reload()
      local n = store.add({ kind = "file", path = path })
      registry.apply({ kind = "file", path = path })
      vim.api.nvim_win_set_cursor(0, { 2, 3 })
      file.remember_current()
      assert.equals(2, store.get(n).line)
      assert.equals(4, store.get(n).col)
      assert.is_nil(store.get(1).line)
    end)

    it("does not remember a buffer that is not a file", function()
      local path = make_file("a.txt")
      slots_add_file(path)
      vim.cmd("enew")
      vim.api.nvim_buf_set_name(0, "")
      file.remember_current()
      assert.is_nil(file.position(""))
      vim.cmd("terminal")
      file.remember_current()
      assert.is_nil(file.position(vim.api.nvim_buf_get_name(0)))
      vim.cmd("bwipeout!")
    end)

    it(
      "opens a file whose relative name starts with '+' instead of reading it as a +cmd",
      function()
        local old = vim.fn.getcwd()
        vim.cmd.cd(dir)
        vim.fn.writefile({ "x" }, "+q")
        local ok = registry.apply({ kind = "file", path = "+q" })
        vim.cmd.cd(old)
        assert.is_true(ok)
        assert.equals("+q", vim.fs.basename(current_name()))
      end
    )

    it(
      "treats a path whose placeholders are all empty as nothing, not as the working directory",
      function()
        vim.cmd("enew")
        vim.api.nvim_buf_set_name(0, "")
        local slot = { kind = "file", path = "{file}" }
        local ok, err = registry.apply(slot)
        assert.is_false(ok)
        assert.is_truthy(err:find("does not exist", 1, true))
        assert.is_true(registry.render(slot).missing)
        assert.equals("", registry.text(slot))
      end
    )

    it("reads {{ and }} in a path as literal braces", function()
      local path = make_file("report {line}.md")
      local escaped = path:gsub("{", "{{"):gsub("}", "}}")
      assert.is_true((registry.apply({ kind = "file", path = escaped })))
      assert.equals(path, current_name())
    end)

    it("validates target, line and col", function()
      assert.is_truthy(registry.validate({ kind = "file", path = "x", target = "float" }))
      assert.is_truthy(registry.validate({ kind = "file", path = "x", line = 0 }))
      assert.is_truthy(registry.validate({ kind = "file", path = "x", col = 1.5 }))
      assert.is_truthy(registry.validate({ kind = "file", path = "" }))
      assert.is_nil(registry.validate({ kind = "file", path = "x", target = "tab", line = 3 }))
    end)

    it("renders icon and highlight too, and dims a file that is gone", function()
      local path = make_file("notes.md")
      local r = registry.render({ kind = "file", path = path })
      assert.is_truthy(r.icon ~= "")
      assert.equals("KitAccent", r.hl)
      vim.fn.delete(path)
      assert.equals("KitMuted", registry.render({ kind = "file", path = path }).hl)
    end)

    it("renders the file name, and marks a file that is gone", function()
      local path = make_file("notes.md")
      local r = registry.render({ kind = "file", path = path })
      assert.equals("notes.md", r.label)
      assert.is_false(r.missing)
      vim.fn.delete(path)
      assert.is_true(registry.render({ kind = "file", path = path }).missing)
    end)
  end)

  describe("yank", function()
    ---@param reg_name string
    ---@return string
    local function reg(reg_name)
      return vim.fn.getreg(reg_name)
    end

    it("writes the text into every register of the config", function()
      config.setup({ clipboard = { "a", "b" } })
      assert.is_true((registry.apply({ kind = "yank", text = "hello" })))
      assert.equals("hello", reg("a"))
      assert.equals("hello", reg("b"))
    end)

    it("uses the slot's own register when it names one", function()
      config.setup({ clipboard = { "a" } })
      vim.fn.setreg("a", "before")
      registry.apply({ kind = "yank", text = "only here", register = "c" })
      assert.equals("only here", reg("c"))
      assert.equals("before", reg("a"))
    end)

    it("puts placeholders into the text", function()
      config.setup({ clipboard = { "a" } })
      registry.apply(
        { kind = "yank", text = "git rebase -i HEAD~{count} {word}" },
        { resolve = { count = 3, word = "x" } }
      )
      assert.equals("git rebase -i HEAD~3 x", reg("a"))
    end)

    it("says what it copied, and which placeholder it did not know", function()
      config.setup({ clipboard = { "a" } })
      registry.apply({ kind = "yank", text = "ab {nope}" })
      local all = table.concat(messages, "\n")
      assert.is_truthy(all:find("copied", 1, true))
      assert.is_truthy(all:find("{nope}", 1, true))
    end)

    it("keeps multi-line text as it is", function()
      config.setup({ clipboard = { "a" } })
      registry.apply({ kind = "yank", text = "l1\nl2" })
      assert.equals("l1\nl2", reg("a"))
    end)

    it("fails when no register takes the text", function()
      local kind = require("ui.slots.kinds.yank")
      local ok, err = kind.apply({ text = "x", register = "?" }, { resolve = {} })
      assert.is_false(ok)
      assert.is_truthy(err:find("no register", 1, true))
    end)

    it("skips a register that refuses as long as another takes it", function()
      config.setup({ clipboard = { "a" } })
      config.get().clipboard = { "?", "a" }
      assert.is_true((registry.apply({ kind = "yank", text = "ok" })))
      assert.equals("ok", reg("a"))
    end)

    it("validates text and register", function()
      assert.is_truthy(registry.validate({ kind = "yank" }))
      assert.is_truthy(registry.validate({ kind = "yank", text = 5 }))
      assert.is_truthy(registry.validate({ kind = "yank", text = "x", register = "ab" }))
      assert.is_nil(registry.validate({ kind = "yank", text = "" }))
    end)

    it("renders an icon and the muted highlight", function()
      local r = registry.render({ kind = "yank", text = "x" })
      assert.is_truthy(r.icon ~= "")
      assert.equals("KitMuted", r.hl)
    end)

    it("does not count a clipboard register as written when there is no provider", function()
      local kind = require("ui.slots.kinds.yank")
      local original = kind.clipboard_available
      kind.clipboard_available = function()
        return false
      end
      config.setup({ clipboard = { "+", "*", "a" } })
      vim.fn.setreg("a", "")
      assert.is_true((registry.apply({ kind = "yank", text = "kept" })))
      assert.equals("kept", reg("a"))
      assert.is_truthy(table.concat(messages, "\n"):find("to a", 1, true))
      assert.is_nil(table.concat(messages, "\n"):find("to + * a", 1, true))
      local ok, err = registry.apply({ kind = "yank", text = "lost", register = "+" })
      kind.clipboard_available = original
      assert.is_false(ok)
      assert.is_truthy(err:find("no register", 1, true))
    end)

    it("renders a one-line label and previews the resolved text", function()
      local r = registry.render({ kind = "yank", text = "first\n   second   line" })
      assert.is_nil(r.label:find("\n", 1, true))
      assert.equals("first second line", r.label)
      local pv = registry.preview(
        { kind = "yank", text = "a {count}\nb" },
        { resolve = { count = 2 } }
      )
      assert.same({ "a 2", "b" }, pv.lines)
    end)
  end)

  describe("url", function()
    local original_open
    local opened

    before_each(function()
      original_open = vim.ui.open
      opened = {}
      vim.ui.open = function(url)
        opened[#opened + 1] = url
        return {}, nil
      end
    end)

    after_each(function()
      vim.ui.open = original_open
    end)

    it("opens http, https, file and mailto addresses", function()
      for _, url in ipairs({
        "http://example.org",
        "https://example.org/a?b=c#d",
        "file:///tmp/x.html",
        "mailto:me@example.org",
        "HTTPS://example.org",
      }) do
        -- fixed: a slot from setup(), the only kind that may name a file: address
        assert.is_true((registry.apply({ kind = "url", url = url, fixed = true })), url)
      end
      assert.equals(5, #opened)
    end)

    it("refuses a file: address from anywhere but setup()", function()
      local ok, err = registry.apply({ kind = "url", url = "file:///tmp/payload.bat" })
      assert.is_false(ok)
      assert.is_truthy(err:find("setup()", 1, true))
      assert.equals(0, #opened)
      -- also when the address only becomes a file: address through a placeholder
      ok = registry.apply(
        { kind = "url", url = "{clip}" },
        { resolve = { clip = "file:///x.bat" } }
      )
      assert.is_false(ok)
      assert.equals(0, #opened)
      assert.is_truthy(registry.outside_setup({ kind = "url", url = " FILE:///x" }))
      assert.is_nil(registry.outside_setup({ kind = "url", url = "https://example.org" }))
    end)

    it("refuses every other scheme, and an address without one", function()
      for _, url in ipairs({
        "javascript:alert(1)",
        "ssh://host",
        "data:text/html,x",
        "vbscript:x",
        "example.org",
        "//example.org",
        "ftp://example.org",
      }) do
        local ok = registry.apply({ kind = "url", url = url })
        assert.is_false(ok, url)
      end
      assert.equals(0, #opened)
    end)

    it("refuses a control character anywhere in the address", function()
      assert.is_false((registry.apply({ kind = "url", url = "https://example.org/\n--x" })))
      assert.is_false((registry.apply({ kind = "url", url = "https://example.org/\0" })))
      assert.equals(0, #opened)
    end)

    it("percent-encodes everything but unreserved characters in a value", function()
      registry.apply(
        { kind = "url", url = "https://example.org/?q={word}" },
        { resolve = { word = "a b&c=d#e/f" } }
      )
      assert.equals("https://example.org/?q=a%20b%26c%3Dd%23e%2Ff", opened[1])
    end)

    it("keeps the slashes of a path value readable", function()
      registry.apply(
        { kind = "url", url = "file:///{file}", fixed = true },
        { resolve = { file = "C:/dir/my file.txt" } }
      )
      assert.equals("file:///C:/dir/my%20file.txt", opened[1])
    end)

    it("takes a placeholder that starts the address as the address itself", function()
      local slot = { kind = "url", url = "{clip}" }
      assert.is_nil(registry.validate(slot))
      assert.is_true((registry.apply(slot, { resolve = { clip = "https://example.org/a?b=c" } })))
      assert.equals("https://example.org/a?b=c", opened[1])
    end)

    it("checks the scheme after the placeholders were put in", function()
      local slot = { kind = "url", url = "{clip}" }
      for _, clip in ipairs({ "javascript:alert(1)", "ssh://host", "no scheme at all", "" }) do
        local ok = registry.apply(slot, { resolve = { clip = clip } })
        assert.is_false(ok, clip)
      end
      assert.equals(0, #opened)
    end)

    it("does not let a value in the middle change the scheme or the host", function()
      local slot = { kind = "url", url = "https://example.org/{word}" }
      registry.apply(slot, { resolve = { word = "../@evil.test" } })
      assert.equals("https://example.org/..%2F%40evil.test", opened[1])
    end)

    it("hands the address to a launcher that is no shell on Windows", function()
      local kind = require("ui.slots.kinds.url")
      assert.same({ cmd = { "rundll32", "url.dll,FileProtocolHandler" } }, kind.opener(true))
      assert.is_nil(kind.opener(false))
      local given
      vim.ui.open = function(url, opts)
        given = { url = url, opts = opts }
        return {}, nil
      end
      registry.apply({ kind = "url", url = "https://example.org/?a=1&b=2" })
      assert.equals("https://example.org/?a=1&b=2", given.url)
      assert.same(kind.opener(), given.opts)
    end)

    it("sends non-ASCII characters as %XX through the Windows launcher only", function()
      local kind = require("ui.slots.kinds.url")
      local original = kind.opener
      kind.opener = function()
        return { cmd = { "rundll32", "url.dll,FileProtocolHandler" } }
      end
      registry.apply({ kind = "url", url = "https://example.org/caf\195\169" })
      kind.opener = function()
        return nil
      end
      registry.apply({ kind = "url", url = "https://example.org/caf\195\169" })
      kind.opener = original
      assert.equals("https://example.org/caf%C3%A9", opened[1])
      assert.equals("https://example.org/caf\195\169", opened[2])
    end)

    it("passes on an error of the opener", function()
      vim.ui.open = function()
        return nil, "no opener"
      end
      local ok, err = registry.apply({ kind = "url", url = "https://example.org" })
      assert.is_false(ok)
      assert.equals("no opener", err)
    end)

    it("validates the address when it is known", function()
      assert.is_truthy(registry.validate({ kind = "url" }))
      assert.is_truthy(registry.validate({ kind = "url", url = "" }))
      assert.is_truthy(registry.validate({ kind = "url", url = "javascript:x" }))
      assert.is_nil(registry.validate({ kind = "url", url = "https://example.org" }))
    end)

    it("renders the host and previews the address", function()
      local r = registry.render({ kind = "url", url = "https://neovim.io/doc/user" })
      assert.equals("neovim.io", r.label)
      local pv = registry.preview({ kind = "url", url = "https://neovim.io/doc/user" })
      assert.equals("https://neovim.io/doc/user", pv.lines[1])
      assert.equals("host: neovim.io", pv.lines[3])
    end)
  end)
end)
