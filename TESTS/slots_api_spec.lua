-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, missing-fields

--- `ui.slots` -- the Lua API, `:UI slots`, the keymaps and the autocommands.

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local slots = require("ui.slots")
local store = require("ui.slots.store")

describe("ui.slots", function()
  local dir
  local messages
  local original_notify
  local original_cwd

  ---@param opts table|nil
  local function start(opts)
    slots.reset()
    store.reset()
    registry.reset()
    slots.setup(
      vim.tbl_extend("force", { data_dir = dir .. "/data", save_delay_ms = 0 }, opts or {})
    )
    slots.enable()
  end

  ---@param name string
  ---@param lines string[]|nil
  ---@return string
  local function make_file(name, lines)
    local path = dir .. "/" .. name
    vim.fn.writefile(lines or { "one", "two", "three" }, path)
    -- The canonical spelling: Neovim names a buffer by it (on macOS /var is a
    -- link to /private/var), so a test must compare in that one spelling.
    return require("lib.nvim.fs.normkey")(path)
  end

  ---@return string
  local function current_name()
    return require("lib.nvim.fs.normkey")(vim.api.nvim_buf_get_name(0))
  end

  ---@param needle string
  ---@return boolean
  local function said(needle)
    return table.concat(messages, "\n"):find(needle, 1, true) ~= nil
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    original_cwd = vim.fn.getcwd()
    messages = {}
    original_notify = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    vim.cmd("silent! %bwipeout!")
    start()
  end)

  after_each(function()
    slots.reset()
    store.reset()
    registry.reset()
    config.reset()
    vim.cmd.cd(original_cwd)
    vim.notify = original_notify
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  describe("switching on and off", function()
    it("registers nothing when it is only required", function()
      slots.reset()
      assert.is_false(slots.is_enabled())
      assert.equals(0, #vim.api.nvim_get_autocmds({ group = "ui_slots" }) or {})
    end)

    it("is off after setup() without enabled = true and on with it", function()
      slots.reset()
      slots.setup({ data_dir = dir .. "/data" })
      assert.is_false(slots.is_enabled())
      slots.setup({ data_dir = dir .. "/data", enabled = true })
      assert.is_true(slots.is_enabled())
    end)

    it("switches itself on for the session when the API is used", function()
      slots.reset()
      slots.setup({ data_dir = dir .. "/data" })
      assert.is_false(slots.is_enabled())
      slots.list()
      assert.is_true(slots.is_enabled())
    end)

    it("creates the autocommands on enable and removes them on disable", function()
      assert.is_true(#vim.api.nvim_get_autocmds({ group = "ui_slots" }) >= 3)
      slots.disable()
      local ok, found = pcall(vim.api.nvim_get_autocmds, { group = "ui_slots" })
      assert.is_true(not ok or #found == 0)
    end)

    it("enable() twice does not double anything", function()
      local before = #vim.api.nvim_get_autocmds({ group = "ui_slots" })
      slots.enable()
      assert.equals(before, #vim.api.nvim_get_autocmds({ group = "ui_slots" }))
    end)

    it("reports a wrong option once at setup() and carries on with the default", function()
      slots.reset()
      slots.setup({ data_dir = dir .. "/data", layout = "tower", persits = true })
      assert.is_true(said("layout"))
      assert.is_true(said("persits"))
      assert.equals("chips", config.get().layout)
    end)

    it("loads the kinds of the config and reports one it refuses", function()
      local ran = false
      slots.reset()
      registry.reset()
      slots.setup({
        data_dir = dir .. "/data",
        enabled = true,
        kinds = {
          hello = {
            apply = function()
              ran = true
            end,
          },
          broken = { nope = 1 },
        },
      })
      assert.is_true((slots.apply(slots.add({ kind = "hello" }))))
      assert.is_true(ran)
      assert.is_true(said("broken"))
    end)

    it("setup() while on picks up the new config", function()
      slots.setup({ data_dir = dir .. "/data", save_delay_ms = 0, keys = { count = "<leader>q" } })
      assert.is_true(slots.is_enabled())
      assert.is_true(
        vim.tbl_contains(require("ui.slots.bindings").mapped(), (vim.g.mapleader or "\\") .. "q")
      )
    end)
  end)

  describe("applying", function()
    it("runs the slot's kind", function()
      local path = make_file("a.txt")
      slots.add({ kind = "file", path = path })
      vim.cmd("enew")
      assert.is_true((slots.apply(1)))
      assert.equals(path, current_name())
      assert.equals(1, slots.last_applied())
    end)

    it("refuses numbers outside 1 to MAX_N the same way as a string and as a number", function()
      for _, bad in ipairs({ 0, "0", config.MAX_N + 1, "99999999999999999999", "00" }) do
        local ok, err = slots.apply(bad)
        assert.is_false(ok)
        assert.equals("not a slot number", err, tostring(bad))
      end
    end)

    it("accepts the number as a string and refuses anything else", function()
      local path = make_file("a.txt")
      slots.add({ kind = "file", path = path })
      assert.is_true((slots.apply("1")))
      for _, bad in ipairs({ "0x1", "1e0", "abc", -1, 0, 1.5, {} }) do
        local ok = slots.apply(bad)
        assert.is_false(ok)
      end
    end)

    it("says when the slot is empty and does not move last_applied", function()
      local ok, err = slots.apply(7)
      assert.is_false(ok)
      assert.equals("empty", err)
      assert.is_true(said("slot 7 is empty"))
      assert.is_nil(slots.last_applied())
    end)

    it("reports what went wrong inside the kind", function()
      slots.add({ kind = "file", path = dir .. "/gone.txt" })
      local ok = slots.apply(1)
      assert.is_false(ok)
      assert.is_true(said("slot 1:"))
      assert.is_true(said("does not exist"))
    end)

    it("hands a count to the kind", function()
      local seen
      slots.register_kind("probe", {
        apply = function(_, ctx)
          seen = ctx.resolve.count()
        end,
      })
      slots.add({ kind = "probe" })
      slots.apply(1, { count = 5 })
      assert.equals(5, seen)
    end)
  end)

  describe("add", function()
    it("puts the current file into the next free slot and says which", function()
      local path = make_file("a.txt")
      vim.cmd.edit(path)
      assert.equals(1, slots.add())
      assert.equals(path, vim.fs.normalize(slots.get(1).path))
      assert.is_true(said("slot 1"))
    end)

    it("does not add the same file twice, but names the slot it is in", function()
      local path = make_file("a.txt")
      vim.cmd.edit(path)
      slots.add()
      messages = {}
      assert.equals(1, slots.add())
      assert.equals(1, slots.list()[1].n)
      assert.equals(1, #slots.list())
      assert.is_true(said("already in slot 1"))
    end)

    it(
      "stores a file name with braces escaped, so it opens again and is not added twice",
      function()
        local path = make_file("report {line}.md")
        vim.cmd.edit(path)
        assert.equals(1, slots.add())
        assert.equals(path, vim.fs.normalize(registry.text(slots.get(1))))
        vim.cmd("enew")
        assert.is_true((slots.apply(1)))
        assert.equals(path, current_name())
        assert.equals(1, slots.add())
        assert.equals(1, #slots.list())
      end
    )

    it("does not match a slot whose path has a placeholder, and does not warn about it", function()
      slots.add({ kind = "file", path = "{file}" })
      slots.add({ kind = "file", path = "~/{foo}.md" })
      local path = make_file("b.md")
      vim.cmd.edit(path)
      messages = {}
      assert.equals(3, slots.add())
      assert.is_false(said("unknown placeholder"))
      assert.is_false(said("already in slot"))
    end)

    it("refuses a buffer without a file", function()
      vim.cmd("enew")
      local n, err = slots.add()
      assert.is_nil(n)
      assert.equals("no file", err)
    end)

    it("takes a given number when it is free and refuses it when it is taken", function()
      assert.equals(5, slots.add({ kind = "yank", text = "x" }, 5))
      local n, err = slots.add({ kind = "yank", text = "y" }, 5)
      assert.is_nil(n)
      assert.equals("taken", err)
      assert.equals("x", slots.get(5).text)
      assert.is_nil((slots.add({ kind = "yank", text = "z" }, "abc")))
    end)

    it("refuses a slot its kind finds wrong, before it reaches the store", function()
      local n, err = slots.add({ kind = "url", url = "javascript:alert(1)" })
      assert.is_nil(n)
      assert.is_truthy(err:find("scheme", 1, true))
      assert.is_nil((slots.add({ kind = "nope" })))
      assert.equals(0, #slots.list())
    end)

    it("fills a gap before it grows", function()
      slots.add({ kind = "yank", text = "1" })
      slots.add({ kind = "yank", text = "2" })
      slots.add({ kind = "yank", text = "3" })
      slots.clear(2)
      assert.equals(2, slots.add({ kind = "yank", text = "again" }))
    end)
  end)

  describe("completion", function()
    it("knows the slot numbers before anything switched the feature on", function()
      slots.add({ kind = "yank", text = "x" })
      store.flush()
      slots.reset()
      store.reset()
      config.setup({ data_dir = dir .. "/data", save_delay_ms = 0 })
      assert.is_false(slots.is_enabled())
      local out = slots.complete("", nil, 1)
      assert.is_true(vim.tbl_contains(out, "1"))
      assert.is_false(slots.is_enabled())
    end)
  end)

  describe("yank", function()
    before_each(function()
      config.get().clipboard = { "a" }
    end)

    it("copies the path of a file slot", function()
      local path = make_file("a.txt")
      slots.add({ kind = "file", path = path })
      assert.is_true((slots.yank(1)))
      assert.equals(path, vim.fs.normalize(vim.fn.getreg("a")))
    end)

    it("copies the address of a url slot and the text of a yank slot", function()
      slots.add({ kind = "url", url = "https://neovim.io/" })
      slots.add({ kind = "yank", text = "hello" })
      slots.yank(1)
      assert.equals("https://neovim.io/", vim.fn.getreg("a"))
      slots.yank(2)
      assert.equals("hello", vim.fn.getreg("a"))
    end)

    it("copies a resolved value as it is, without resolving it a second time", function()
      slots.add({ kind = "yank", text = "{word}" })
      local text = registry.text(slots.get(1), { resolve = { word = "{count}", count = 9 } })
      assert.equals("{count}", text)
      slots.yank(1)
      assert.is_true(said("copied"))
    end)

    it("copies a path whose name has braces that are no placeholder", function()
      local path = make_file("{plain}.txt")
      slots.add({ kind = "file", path = path })
      slots.yank(1)
      assert.equals(path, vim.fs.normalize(vim.fn.getreg("a")))
    end)

    it("says when the slot is empty or its kind has nothing to copy", function()
      assert.is_false((slots.yank(3)))
      registry.register("silent", { apply = function() end })
      slots.add({ kind = "silent" })
      local ok, err = slots.yank(1)
      assert.is_false(ok)
      assert.is_truthy(err:find("nothing to copy", 1, true))
    end)
  end)

  describe("clearing and moving", function()
    it("clear() empties a slot and clear_all() all that are not fixed", function()
      slots.add({ kind = "yank", text = "1" })
      slots.add({ kind = "yank", text = "2" })
      assert.is_true((slots.clear(1)))
      assert.is_false((slots.clear(1)))
      assert.is_false((slots.clear("x")))
      assert.equals(1, slots.clear_all())
      assert.equals(0, #slots.list())
    end)

    it("clear() refuses a fixed slot", function()
      start({ slots = { [2] = { kind = "yank", text = "fixed" } } })
      local ok, err = slots.clear(2)
      assert.is_false(ok)
      assert.is_truthy(err:find("fixed", 1, true))
      assert.equals(1, #slots.list())
    end)

    it("move() renumbers and swaps", function()
      slots.add({ kind = "yank", text = "a" })
      slots.add({ kind = "yank", text = "b" })
      assert.is_true((slots.move(1, 2)))
      assert.equals("b", slots.get(1).text)
      assert.equals("a", slots.get(2).text)
      assert.is_true((slots.move(2, 9)))
      assert.equals("a", slots.get(9).text)
      assert.is_false((slots.move(1)))
      assert.is_false((slots.move("x", 2)))
    end)
  end)

  describe("fixed slots from setup()", function()
    it("are there after enabling, with their kind's rendering", function()
      local path = make_file("notes.md")
      start({ slots = { [3] = { kind = "file", path = path } } })
      assert.equals(1, #slots.list())
      assert.is_true(slots.get(3).fixed)
      assert.equals("notes.md", registry.render(slots.get(3)).label)
    end)
  end)

  describe("keymaps", function()
    it("maps nothing by default", function()
      assert.same({}, require("ui.slots.bindings").mapped())
    end)

    it("maps slots 1 to 9 from a pattern, and each key applies its slot", function()
      local seen = {}
      start({ keys = { apply = "<leader>%d" } })
      registry.register("probe", {
        apply = function(slot)
          seen[#seen + 1] = slot.tag
        end,
      })
      for n = 1, 9 do
        slots.add({ kind = "probe", tag = n })
      end
      assert.equals(9, #require("ui.slots.bindings").mapped())
      vim.api.nvim_feedkeys(vim.keycode("<leader>3"), "x", false)
      vim.api.nvim_feedkeys(vim.keycode("<leader>9"), "x", false)
      assert.same({ 3, 9 }, seen)
    end)

    it("takes the slot number as a count on the count key", function()
      local seen
      start({ keys = { count = "<leader>s" } })
      registry.register("probe", {
        apply = function(slot)
          seen = slot.tag
        end,
      })
      for n = 1, 12 do
        slots.add({ kind = "probe", tag = n })
      end
      vim.api.nvim_feedkeys("12" .. vim.keycode("<leader>s"), "x", false)
      assert.equals(12, seen)
      messages = {}
      vim.api.nvim_feedkeys(vim.keycode("<leader>s"), "x", false)
      assert.is_true(said("count"))
    end)

    it("maps an add key", function()
      local path = make_file("a.txt")
      start({ keys = { add = "<leader>a" } })
      vim.cmd.edit(path)
      vim.api.nvim_feedkeys(vim.keycode("<leader>a"), "x", false)
      assert.equals(1, #slots.list())
    end)

    it(
      "reports a pattern without exactly one %d and an unknown key, and maps nothing for them",
      function()
        start({ keys = { apply = "<leader>x", bogus = "<leader>b", count = false } })
        assert.is_true(said("exactly one %d"))
        assert.is_true(said("bogus"))
        assert.same({}, require("ui.slots.bindings").mapped())
      end
    )

    it("reads an empty mapleader as a backslash, like Neovim does", function()
      local old = vim.g.mapleader
      vim.g.mapleader = ""
      start({ keys = { apply = "<leader>%d" } })
      local mapped = require("ui.slots.bindings").mapped()
      vim.g.mapleader = old
      assert.is_true(vim.tbl_contains(mapped, "\\1"))
      assert.is_false(vim.tbl_contains(mapped, "1"))
    end)

    it("removes the keymaps it made even when the leader changed in between", function()
      local old = vim.g.mapleader
      vim.g.mapleader = ","
      start({ keys = { apply = "<leader>%d" } })
      assert.is_not.equals("", vim.fn.maparg(",1", "n"))
      vim.g.mapleader = ";"
      slots.disable()
      vim.g.mapleader = old
      assert.equals("", vim.fn.maparg(",1", "n"))
    end)

    it("removes its keymaps on disable and again on a second enable", function()
      start({ keys = { apply = "<leader>%d" } })
      assert.equals(9, #require("ui.slots.bindings").mapped())
      slots.disable()
      assert.same({}, require("ui.slots.bindings").mapped())
      assert.equals("", vim.fn.maparg("<leader>1", "n"))
      slots.enable()
      assert.equals(9, #require("ui.slots.bindings").mapped())
    end)
  end)

  describe("autocommands", function()
    it("DirChanged loads the slots of the new project and brings them back on return", function()
      local a = dir .. "/proj_a"
      local b = dir .. "/proj_b"
      vim.fn.mkdir(a, "p")
      vim.fn.mkdir(b, "p")
      vim.cmd.cd(a)
      start()
      slots.add({ kind = "yank", text = "in a" })
      vim.cmd.cd(b)
      assert.equals(0, #slots.list())
      slots.add({ kind = "yank", text = "in b" })
      vim.cmd.cd(a)
      assert.equals("in a", slots.get(1).text)
      assert.equals(1, #slots.list())
      vim.cmd.cd(b)
      assert.equals("in b", slots.get(1).text)
    end)

    it("DirChanged keeps the slots of this session when nothing is persisted", function()
      start({ persist = false })
      slots.add({ kind = "yank", text = "session only" })
      vim.cmd.cd(dir)
      assert.equals("session only", slots.get(1).text)
    end)

    it("DirChanged inside the same project does not reload", function()
      local proj = dir .. "/proj"
      vim.fn.mkdir(proj .. "/.git", "p")
      vim.fn.mkdir(proj .. "/sub", "p")
      vim.cmd.cd(proj)
      start({ save_delay_ms = 60000 })
      slots.add({ kind = "yank", text = "unsaved" })
      local reloads = 0
      store.on_change(function(event)
        if event == "reload" then
          reloads = reloads + 1
        end
      end)
      vim.cmd.cd(proj .. "/sub")
      assert.equals(0, reloads)
      assert.equals("unsaved", slots.get(1).text)
    end)

    it("VimLeavePre remembers the cursor of the file you quit from", function()
      local path = make_file("a.txt", { "alpha", "beta", "gamma" })
      slots.add({ kind = "file", path = path })
      slots.apply(1)
      vim.api.nvim_win_set_cursor(0, { 2, 2 })
      vim.api.nvim_exec_autocmds("VimLeavePre", { group = "ui_slots" })
      assert.equals(2, slots.get(1).line)
      assert.equals(3, slots.get(1).col)
      assert.equals(1, vim.fn.filereadable(store.path()))
    end)

    it("DirChanged leaves a global scope alone", function()
      start({ scope = "global" })
      slots.add({ kind = "yank", text = "g" })
      vim.cmd.cd(dir)
      assert.equals("g", slots.get(1).text)
    end)

    it("VimLeavePre writes what the batching timer has not written yet", function()
      start({ save_delay_ms = 60000 })
      slots.add({ kind = "yank", text = "late" })
      assert.equals(0, vim.fn.filereadable(store.path()))
      vim.api.nvim_exec_autocmds("VimLeavePre", { group = "ui_slots" })
      assert.equals(1, vim.fn.filereadable(store.path()))
    end)

    it("BufLeave remembers the cursor of a slot's file", function()
      local path = make_file("a.txt", { "alpha", "beta", "gamma" })
      slots.add({ kind = "file", path = path })
      slots.apply(1)
      vim.api.nvim_win_set_cursor(0, { 3, 1 })
      vim.cmd("enew")
      assert.equals(3, slots.get(1).line)
      assert.equals(2, slots.get(1).col)
    end)

    it("disable() writes pending changes", function()
      start({ save_delay_ms = 60000 })
      slots.add({ kind = "yank", text = "pending" })
      local path = store.path()
      slots.disable()
      assert.equals(1, vim.fn.filereadable(path))
    end)
  end)

  describe(":UI slots", function()
    before_each(function()
      require("ui.bindings.usrcmds").setup()
    end)

    it("lists the slots, and says so when there are none", function()
      vim.cmd("UI slots")
      assert.is_true(said("no slots yet"))
      slots.add({ kind = "yank", text = "hello world" })
      messages = {}
      vim.cmd("UI slots list")
      assert.is_true(said("hello world"))
      assert.is_true(said("(yank)"))
    end)

    it("marks fixed slots and slots whose target is gone", function()
      start({ slots = { [2] = { kind = "file", path = dir .. "/gone.md" } } })
      messages = {}
      vim.cmd("UI slots")
      assert.is_true(said("fixed"))
      assert.is_true(said("missing"))
    end)

    it("runs a slot by number", function()
      local path = make_file("a.txt")
      slots.add({ kind = "file", path = path })
      vim.cmd("enew")
      vim.cmd("UI slots 1")
      assert.equals(path, current_name())
    end)

    it("adds, copies, moves and clears", function()
      config.get().clipboard = { "a" }
      local path = make_file("a.txt")
      vim.cmd.edit(path)
      vim.cmd("UI slots add")
      assert.equals(1, #slots.list())
      vim.cmd("UI slots yank 1")
      assert.equals(path, vim.fs.normalize(vim.fn.getreg("a")))
      vim.cmd("UI slots move 1 4")
      assert.is_not_nil(slots.get(4))
      vim.cmd("UI slots clear 4")
      assert.equals(0, #slots.list())
      slots.add({ kind = "yank", text = "x" })
      vim.cmd("UI slots clear all")
      assert.equals(0, #slots.list())
    end)

    it("add takes a number", function()
      local path = make_file("a.txt")
      vim.cmd.edit(path)
      vim.cmd("UI slots add 6")
      assert.is_not_nil(slots.get(6))
    end)

    it("lists the kinds", function()
      vim.cmd("UI slots kinds")
      assert.is_true(said("cmd, file, lua, mark, url, yank"))
    end)

    it("says that the slot editor is not built, instead of failing", function()
      vim.cmd("UI slots edit")
      assert.is_true(said("editor is not built yet"))
    end)

    it("reports an unknown subcommand", function()
      vim.cmd("UI slots frobnicate")
      assert.is_true(said("unknown subcommand 'frobnicate'"))
    end)

    it("completes the subcommands and the numbers of the slots", function()
      slots.add({ kind = "yank", text = "x" })
      local first = vim.fn.getcompletion("UI slots ", "cmdline")
      assert.is_true(vim.tbl_contains(first, "add"))
      assert.is_true(vim.tbl_contains(first, "clear"))
      assert.is_true(vim.tbl_contains(first, "1"))
      assert.same({ "clear" }, vim.fn.getcompletion("UI slots cle", "cmdline"))
      local clear = vim.fn.getcompletion("UI slots clear ", "cmdline")
      assert.is_true(vim.tbl_contains(clear, "all"))
      assert.is_true(vim.tbl_contains(clear, "1"))
      assert.same({ "1" }, vim.fn.getcompletion("UI slots move ", "cmdline"))
      assert.same({}, vim.fn.getcompletion("UI slots clear all ", "cmdline"))
    end)

    it("is in the help text", function()
      messages = {}
      vim.cmd("UI help")
      assert.is_true(said(":UI slots"))
    end)
  end)

  describe("ui.setup", function()
    it("does not touch slots without the option, not even under all", function()
      slots.reset()
      require("ui").setup({ all = true })
      assert.is_false(slots.is_enabled())
    end)

    it("slots = true switches them on", function()
      slots.reset()
      config.setup({ data_dir = dir .. "/data" })
      require("ui").setup({ slots = true })
      assert.is_true(slots.is_enabled())
      -- the options given before are still there
      assert.equals(dir .. "/data", config.get().data_dir)
    end)

    it("a table configures them and switches them on only with enabled = true", function()
      slots.reset()
      require("ui").setup({ slots = { data_dir = dir .. "/data" } })
      assert.is_false(slots.is_enabled())
      require("ui").setup({ slots = { data_dir = dir .. "/data", enabled = true } })
      assert.is_true(slots.is_enabled())
    end)
  end)
end)
