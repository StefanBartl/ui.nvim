-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, missing-fields

--- `ui.slots` action kinds `cmd`, `lua` and `mark`, and the rule that a data
--- file can never bring the first two in.

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local slots = require("ui.slots")
local store = require("ui.slots.store")

describe("ui.slots action kinds", function()
  local dir
  local messages
  local original_notify
  local seen

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

  ---@param needle string
  ---@return boolean
  local function said(needle)
    return table.concat(messages, "\n"):find(needle, 1, true) ~= nil
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    messages = {}
    seen = nil
    original_notify = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    vim.api.nvim_create_user_command("UiSlotsProbe", function(o)
      seen = { args = o.args, fargs = o.fargs, bang = o.bang }
    end, { nargs = "*", bang = true })
    start()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_user_command, "UiSlotsProbe")
    slots.reset()
    store.reset()
    registry.reset()
    config.reset()
    package.preload["sessions.marks"] = nil
    package.loaded["sessions.marks"] = nil
    vim.notify = original_notify
    vim.fn.delete(dir, "rf")
  end)

  describe("registry", function()
    it("knows all six built-in kinds", function()
      assert.same({ "cmd", "file", "lua", "mark", "url", "yank" }, registry.names())
    end)

    it("keeps cmd and lua out of what a data file may hold, and mark in", function()
      assert.is_false(vim.tbl_contains(config.get().persistable_kinds, "cmd"))
      assert.is_false(vim.tbl_contains(config.get().persistable_kinds, "lua"))
      assert.is_true(vim.tbl_contains(config.get().persistable_kinds, "mark"))
    end)
  end)

  describe("cmd", function()
    it("runs the command with its arguments", function()
      slots.add({ kind = "cmd", cmd = "UiSlotsProbe", args = "one two" })
      assert.is_true((slots.apply(1)))
      assert.same({ "one", "two" }, seen.fargs)
    end)

    it("puts placeholders in, and a value with spaces stays ONE argument", function()
      registry.apply(
        { kind = "cmd", cmd = "UiSlotsProbe", args = "q={word} {cwd}" },
        { resolve = { word = "a b c", cwd = "/my dir" } }
      )
      assert.same({ "q=a b c", "/my dir" }, seen.fargs)
    end)

    it("refuses a value with a bar instead of passing it on, and runs nothing", function()
      vim.g.ui_slots_pwned = nil
      local ok, err = registry.apply(
        { kind = "cmd", cmd = "UiSlotsProbe", args = "{word}" },
        { resolve = { word = "x | let g:ui_slots_pwned = 1" } }
      )
      assert.is_false(ok)
      assert.is_truthy(err:find("refused", 1, true))
      assert.is_truthy(err:find("{word}", 1, true))
      assert.is_nil(seen)
      assert.is_nil(vim.g.ui_slots_pwned)
    end)

    it("refuses a bar even for a command that pastes its raw <args>", function()
      vim.g.ui_slots_pwned = nil
      vim.cmd("command! -nargs=* UiSlotsRaw echo <args>")
      local ok = registry.apply(
        { kind = "cmd", cmd = "UiSlotsRaw", args = "{sel}" },
        { resolve = { sel = "'a' | let g:ui_slots_pwned = 2" } }
      )
      vim.cmd("delcommand UiSlotsRaw")
      assert.is_false(ok)
      assert.is_nil(vim.g.ui_slots_pwned)
    end)

    it("refuses a backtick, which :argadd and friends would hand to a shell", function()
      for _, value in ipairs({ "`mkdir x`", "dir/`whoami`", "a`b" }) do
        local ok = registry.apply(
          { kind = "cmd", cmd = "argadd", args = "{dir}" },
          { resolve = { dir = value } }
        )
        assert.is_false(ok, value)
      end
      assert.equals(0, vim.fn.argc())
    end)

    it("refuses a value that starts the argument with + or !", function()
      vim.g.ui_slots_pwned = nil
      for _, value in ipairs({
        "+let\\ g:ui_slots_pwned=1 notes.txt",
        "  +q",
        "!echo hi",
        "++ff=dos x",
      }) do
        local ok = registry.apply(
          { kind = "cmd", cmd = "edit", args = "{clip}" },
          { resolve = { clip = value } }
        )
        assert.is_false(ok, value)
      end
      assert.is_nil(vim.g.ui_slots_pwned)
    end)

    it("lets + and ! stand elsewhere: inside a value, or written by the slot's author", function()
      assert.is_true(
        (
          registry.apply(
            { kind = "cmd", cmd = "UiSlotsProbe", args = "a+b {word}" },
            { resolve = { word = "c!d" } }
          )
        )
      )
      assert.same({ "a+b", "c!d" }, seen.fargs)
      assert.is_true(
        (registry.apply({ kind = "cmd", cmd = "UiSlotsProbe", args = "+literal !also" }))
      )
      assert.same({ "+literal", "!also" }, seen.fargs)
      assert.is_true(
        (
          registry.apply(
            { kind = "cmd", cmd = "UiSlotsProbe", args = "pre{word}" },
            { resolve = { word = "+x" } }
          )
        )
      )
    end)

    it("takes the values as they are with raw_values = true", function()
      local ok = registry.apply(
        { kind = "cmd", cmd = "UiSlotsProbe", args = "{word}", raw_values = true },
        { resolve = { word = "x | y `z` +w" } }
      )
      assert.is_true(ok)
      assert.equals("x | y `z` +w", seen.args)
      assert.is_truthy(registry.validate({ kind = "cmd", cmd = "X", raw_values = "yes" }))
    end)

    it("turns a newline in a value into a space instead of ending the command", function()
      vim.g.ui_slots_pwned = nil
      registry.apply(
        { kind = "cmd", cmd = "UiSlotsProbe", args = "{sel}" },
        { resolve = { sel = "a\nlet g:ui_slots_pwned = 1" } }
      )
      assert.is_nil(vim.g.ui_slots_pwned)
      assert.equals("a let g:ui_slots_pwned = 1", seen.args)
    end)

    it("does not expand % or # in an argument", function()
      registry.apply({ kind = "cmd", cmd = "UiSlotsProbe", args = { "%", "#", "*.lua" } })
      assert.same({ "%", "#", "*.lua" }, seen.fargs)
    end)

    it("takes a list of arguments as it is, spaces included", function()
      registry.apply({ kind = "cmd", cmd = "UiSlotsProbe", args = { "a b", "c" } })
      assert.same({ "a b", "c" }, seen.fargs)
    end)

    it("drops an argument that resolved to nothing", function()
      registry.apply(
        { kind = "cmd", cmd = "UiSlotsProbe", args = "{word} x" },
        { resolve = { word = "" } }
      )
      assert.same({ "x" }, seen.fargs)
    end)

    it("passes the bang", function()
      registry.apply({ kind = "cmd", cmd = "UiSlotsProbe", bang = true })
      assert.is_true(seen.bang)
    end)

    it("says when the command does not exist, and runs nothing", function()
      local ok, err = registry.apply({ kind = "cmd", cmd = "UiSlotsNoSuchThing" })
      assert.is_false(ok)
      assert.is_truthy(err:find("no such command", 1, true))
    end)

    it("reports an error raised by the command", function()
      vim.api.nvim_create_user_command("UiSlotsBoom", function()
        error("kaboom")
      end, {})
      local ok, err = registry.apply({ kind = "cmd", cmd = "UiSlotsBoom" })
      vim.api.nvim_del_user_command("UiSlotsBoom")
      assert.is_false(ok)
      assert.is_truthy(err:find("kaboom", 1, true))
    end)

    it("refuses a command name that is not a plain name", function()
      for _, name in ipairs({ "Foo bar", "Foo|Bar", "!ls", "Foo;Bar", "", "1Foo", 5 }) do
        assert.is_truthy(registry.validate({ kind = "cmd", cmd = name }), tostring(name))
      end
    end)

    it("refuses an unknown placeholder in args, naming it", function()
      local err = registry.validate({ kind = "cmd", cmd = "UiSlotsProbe", args = "{nope}" })
      assert.is_truthy(err:find("{nope}", 1, true))
      err = registry.validate({ kind = "cmd", cmd = "UiSlotsProbe", args = { "ok", "{bad}" } })
      assert.is_truthy(err:find("{bad}", 1, true))
      assert.is_nil(registry.validate({ kind = "cmd", cmd = "UiSlotsProbe", args = "{{nope}}" }))
    end)

    it("refuses args of the wrong type and a bang that is no boolean", function()
      assert.is_truthy(registry.validate({ kind = "cmd", cmd = "X", args = 5 }))
      assert.is_truthy(registry.validate({ kind = "cmd", cmd = "X", args = { 1 } }))
      assert.is_truthy(registry.validate({ kind = "cmd", cmd = "X", bang = "yes" }))
    end)

    it("renders the command, dimmed when it does not exist, and copies the command line", function()
      local slot = { kind = "cmd", cmd = "UiSlotsProbe", args = "a b", bang = true }
      local r = registry.render(slot)
      assert.equals(":UiSlotsProbe", r.label)
      assert.is_false(r.missing)
      assert.is_true(registry.render({ kind = "cmd", cmd = "UiSlotsNope" }).missing)
      assert.equals(":UiSlotsProbe! a b", registry.text(slot))
      assert.same({ ":UiSlotsProbe! a b" }, registry.preview(slot).lines)
    end)

    it("can be added by a host in Lua and runs, but never reaches the data file", function()
      assert.equals(1, slots.add({ kind = "cmd", cmd = "UiSlotsProbe", args = "x" }))
      assert.is_true((slots.apply(1)))
      assert.is_true(store.flush())
      local data = vim.json.decode(table.concat(vim.fn.readfile(store.path() or ""), "\n"))
      assert.same({}, data.slots)
    end)
  end)

  describe("slots of this session", function()
    it("survive a change of scope, because they were never part of a project", function()
      slots.add({
        kind = "lua",
        fn = function() end,
      })
      slots.add({ kind = "yank", text = "saved here" })
      config.get().scope = "global"
      store.reload()
      assert.equals("lua", slots.get(1).kind)
      assert.is_nil(slots.get(2))
    end)

    it("give way to a saved slot with the same number, and say so", function()
      config.get().scope = "global"
      store.reload()
      slots.add({ kind = "yank", text = "global one" })
      store.flush()
      config.get().scope = "project"
      store.reload()
      slots.add({
        kind = "lua",
        fn = function() end,
      })
      config.get().scope = "global"
      store.reload()
      vim.wait(30, function()
        return false
      end)
      assert.equals("yank", slots.get(1).kind)
      assert.is_true(said("replaced by the one saved"))
    end)
  end)

  describe("a data file can not bring cmd or lua in", function()
    it("loads neither, runs nothing, and says so once", function()
      start()
      local path = store.path()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({
        vim.json.encode({
          format = "ui.slots",
          version = 1,
          slots = {
            { n = 1, kind = "cmd", cmd = "UiSlotsProbe", args = "evil" },
            { n = 2, kind = "lua", fn = "vim.g.ui_slots_pwned = 1" },
            { n = 3, kind = "mark", index = 4 },
            { n = 4, kind = "yank", text = "fine" },
          },
        }),
      }, path)
      store.reload()
      store.reload()
      vim.wait(30, function()
        return false
      end)
      local numbers = vim.tbl_map(function(s)
        return s.n
      end, slots.list())
      assert.same({ 3, 4 }, numbers)
      assert.is_false((slots.apply(1)))
      assert.is_false((slots.apply(2)))
      assert.is_nil(seen)
      assert.is_nil(vim.g.ui_slots_pwned)
      local reports = vim.tbl_filter(function(m)
        return m:find("may not hold", 1, true) ~= nil
      end, messages)
      -- one message for all the dropped entries, not one per entry
      assert.equals(1, #reports)
      assert.is_truthy(reports[1]:find("dropped 2 entries", 1, true))
    end)
  end)

  describe("lua", function()
    it("calls the function with the slot, its number and the count", function()
      local got
      slots.add({
        kind = "lua",
        fn = function(ctx)
          got = { n = ctx.n, kind = ctx.slot.kind, count = ctx.count }
        end,
      })
      slots.apply(1, { count = 4 })
      assert.same({ n = 1, kind = "lua", count = 4 }, got)
    end)

    it("reads a placeholder only when the function asks for it", function()
      local reads = 0
      local ok = registry.apply({
        kind = "lua",
        fn = function(ctx)
          return ctx.slot ~= nil
        end,
      }, {
        resolve = {
          clip = function()
            reads = reads + 1
            return "secret"
          end,
        },
      })
      assert.is_true(ok)
      assert.equals(0, reads)
      local value
      registry.apply({
        kind = "lua",
        fn = function(ctx)
          value = ctx.clip
        end,
      }, {
        resolve = {
          clip = function()
            reads = reads + 1
            return "secret"
          end,
        },
      })
      assert.equals(1, reads)
      assert.equals("secret", value)
    end)

    it("reports an error raised by the function and stays usable", function()
      slots.add({
        kind = "lua",
        fn = function()
          error("boom")
        end,
      })
      local ok = slots.apply(1)
      assert.is_false(ok)
      assert.is_true(said("boom"))
      assert.equals(2, slots.add({ kind = "yank", text = "still works" }))
    end)

    it("counts false, and nil with a message, as a failure", function()
      local ok, err = registry.apply({
        kind = "lua",
        fn = function()
          return false
        end,
      })
      assert.is_false(ok)
      assert.is_truthy(err)
      ok, err = registry.apply({
        kind = "lua",
        fn = function()
          return nil, "not now"
        end,
      })
      assert.is_false(ok)
      assert.equals("not now", err)
      assert.is_true((registry.apply({
        kind = "lua",
        fn = function() end,
      })))
    end)

    it("never runs a string", function()
      vim.g.ui_slots_pwned = nil
      local err = registry.validate({ kind = "lua", fn = "vim.g.ui_slots_pwned = 1" })
      assert.is_truthy(err:find("string is not run", 1, true))
      assert.is_false((registry.apply({ kind = "lua", fn = "vim.g.ui_slots_pwned = 1" })))
      assert.is_nil(vim.g.ui_slots_pwned)
    end)

    it("is not written to the data file, with its function", function()
      slots.add({ kind = "lua", fn = function() end })
      slots.add({ kind = "yank", text = "kept" })
      assert.is_true(store.flush())
      local data = vim.json.decode(table.concat(vim.fn.readfile(store.path()), "\n"))
      assert.equals(1, #data.slots)
      assert.equals("yank", data.slots[1].kind)
    end)

    it("has no text to copy", function()
      local text, err = registry.text({ kind = "lua", fn = function() end })
      assert.is_nil(text)
      assert.is_truthy(err:find("nothing to copy", 1, true))
    end)
  end)

  describe("mark", function()
    local selected

    ---@param list table[]
    local function fake_marks(list)
      selected = nil
      package.loaded["sessions.marks"] = {
        list = function()
          return list
        end,
        select = function(n)
          selected = n
          if not list[n] then
            return false, ("no mark at %d (%d listed)"):format(n, #list)
          end
          return true
        end,
        label = function(path)
          return "label:" .. vim.fs.basename(path)
        end,
      }
    end

    local function without_sessions()
      package.loaded["sessions.marks"] = nil
      package.preload["sessions.marks"] = function()
        error("module 'sessions.marks' not found")
      end
    end

    it("hands the index to sessions.marks", function()
      fake_marks({ { path = dir .. "/a.txt" }, { path = dir .. "/b.txt" } })
      assert.is_true((registry.apply({ kind = "mark", index = 2 })))
      assert.equals(2, selected)
    end)

    it("reports an index past the end of the list", function()
      fake_marks({ { path = dir .. "/a.txt" } })
      local ok, err = registry.apply({ kind = "mark", index = 5 })
      assert.is_false(ok)
      assert.is_truthy(err:find("no mark at 5", 1, true))
    end)

    it("tells a broken sessions.nvim from a missing one", function()
      package.loaded["sessions.marks"] = nil
      package.preload["sessions.marks"] = function()
        error("syntax error near x")
      end
      local ok, err = registry.apply({ kind = "mark", index = 1 })
      assert.is_false(ok)
      assert.is_truthy(err:find("failed to load", 1, true))
      assert.is_truthy(err:find("syntax error", 1, true))
    end)

    it("says that sessions.nvim is missing instead of failing", function()
      without_sessions()
      local ok, err = registry.apply({ kind = "mark", index = 1 })
      assert.is_false(ok)
      assert.equals("sessions.nvim is not installed", err)
    end)

    it("renders the mark's label, and dimmed with the index when it cannot", function()
      vim.fn.writefile({ "x" }, dir .. "/a.txt")
      fake_marks({ { path = dir .. "/a.txt" } })
      local r = registry.render({ kind = "mark", index = 1 })
      assert.equals("label:a.txt", r.label)
      assert.is_false(r.missing)
      r = registry.render({ kind = "mark", index = 3 })
      assert.equals("mark 3", r.label)
      assert.is_true(r.missing)
      without_sessions()
      r = registry.render({ kind = "mark", index = 1 })
      assert.is_true(r.missing)
      assert.equals("KitMuted", r.hl)
    end)

    it("marks a mark whose file is gone as missing", function()
      fake_marks({ { path = dir .. "/gone.txt" } })
      assert.is_true(registry.render({ kind = "mark", index = 1 }).missing)
    end)

    it("copies the path of the mark, and says why when it cannot", function()
      fake_marks({ { path = dir .. "/a.txt" } })
      assert.equals(dir .. "/a.txt", registry.text({ kind = "mark", index = 1 }))
      local text, err = registry.text({ kind = "mark", index = 9 })
      assert.is_nil(text)
      assert.is_truthy(err:find("no mark at 9", 1, true))
    end)

    it("previews the path, or the reason", function()
      fake_marks({ { path = dir .. "/a.txt" } })
      assert.same({ dir .. "/a.txt" }, registry.preview({ kind = "mark", index = 1 }).lines)
      assert.is_truthy(
        registry.preview({ kind = "mark", index = 7 }).lines[1]:find("no mark", 1, true)
      )
    end)

    it("needs a positive whole index", function()
      for _, bad in ipairs({ 0, -1, 1.5, "1" }) do
        assert.is_truthy(registry.validate({ kind = "mark", index = bad }))
      end
      assert.is_truthy(registry.validate({ kind = "mark" }))
      assert.is_nil(registry.validate({ kind = "mark", index = 2 }))
    end)

    it("is written to the data file with its index only", function()
      slots.add({ kind = "mark", index = 3 })
      assert.is_true(store.flush())
      local data = vim.json.decode(table.concat(vim.fn.readfile(store.path()), "\n"))
      assert.equals("mark", data.slots[1].kind)
      assert.equals(3, data.slots[1].index)
      store.reload()
      assert.equals(3, slots.get(1).index)
    end)
  end)
end)
