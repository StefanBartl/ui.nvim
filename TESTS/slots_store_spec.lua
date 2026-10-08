-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.slots.store` -- numbering, fixed slots, and the data file.

local config = require("ui.slots.config")
local store = require("ui.slots.store")

describe("ui.slots.store", function()
  local dir
  local messages
  local original_notify

  --- Start from an empty store on a throw-away data directory.
  ---@param opts table|nil
  local function fresh(opts)
    store.reset()
    config.setup(vim.tbl_extend("force", { data_dir = dir, save_delay_ms = 0 }, opts or {}))
    store.reload()
  end

  --- Let the scheduled notifications run.
  local function drain()
    vim.wait(30, function()
      return false
    end)
  end

  ---@param path string
  ---@return string
  local function slurp(path)
    return table.concat(vim.fn.readfile(path, "b"), "\n")
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    messages = {}
    original_notify = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    fresh()
  end)

  after_each(function()
    drain()
    store.reset()
    config.reset()
    vim.notify = original_notify
    vim.fn.delete(dir, "rf")
  end)

  describe("numbering", function()
    it(
      "add() takes the lowest free number, a cleared slot leaves a gap that is refilled",
      function()
        assert.equals(1, store.add({ kind = "file", path = "a" }))
        assert.equals(2, store.add({ kind = "file", path = "b" }))
        assert.equals(3, store.add({ kind = "file", path = "c" }))
        assert.is_true(store.clear(2))
        assert.same(
          { 1, 3 },
          vim.tbl_map(function(s)
            return s.n
          end, store.list())
        )
        assert.equals(2, store.add({ kind = "file", path = "d" }))
      end
    )

    it("has no upper bound", function()
      for i = 1, 60 do
        assert.equals(i, store.add({ kind = "yank", text = tostring(i) }))
      end
      assert.equals(60, store.count())
      assert.equals("60", store.get(60).text)
    end)

    it("lists only occupied slots, ascending", function()
      assert.is_true(store.set(7, { kind = "file", path = "seven" }))
      assert.is_true(store.set(2, { kind = "file", path = "two" }))
      local numbers = vim.tbl_map(function(s)
        return s.n
      end, store.list())
      assert.same({ 2, 7 }, numbers)
    end)

    it("hands out copies, never the live table", function()
      store.add({ kind = "file", path = "a" })
      local got = store.get(1)
      got.path = "changed"
      assert.equals("a", store.get(1).path)
    end)

    it("rejects numbers that are not positive whole numbers", function()
      for _, n in ipairs({ 0, -1, 1.5, 1e9 }) do
        local ok = store.set(n, { kind = "file", path = "x" })
        assert.is_false(ok)
      end
      assert.equals(0, store.count())
    end)

    it("rejects a slot without a kind", function()
      assert.is_false((store.set(1, { path = "x" })))
      assert.is_nil((store.add("not a table")))
    end)
  end)

  describe("changing", function()
    it("move() renumbers, and swaps when the target is taken", function()
      store.set(1, { kind = "file", path = "a" })
      store.set(2, { kind = "file", path = "b" })
      assert.is_true(store.move(1, 5))
      assert.is_nil(store.get(1))
      assert.equals("a", store.get(5).path)
      assert.is_true(store.move(5, 2))
      assert.equals("a", store.get(2).path)
      assert.equals("b", store.get(5).path)
    end)

    it("update() merges fields and refuses to remove the kind", function()
      store.set(1, { kind = "file", path = "a", label = "A" })
      assert.is_true(store.update(1, { label = "B" }))
      assert.equals("B", store.get(1).label)
      assert.equals("a", store.get(1).path)
      assert.is_false((store.update(1, { kind = vim.NIL })))
      assert.is_false((store.update(9, { label = "x" })))
    end)

    it("update() removes a field when the patch holds vim.NIL for it", function()
      store.set(1, { kind = "file", path = "a", label = "A" })
      assert.is_true(store.update(1, { label = vim.NIL }))
      assert.is_nil(store.get(1).label)
      assert.equals("a", store.get(1).path)
    end)

    it("clear() fails on an empty slot, clear_all() reports how many it removed", function()
      assert.is_false((store.clear(3)))
      store.add({ kind = "file", path = "a" })
      store.add({ kind = "file", path = "b" })
      assert.equals(2, store.clear_all())
      assert.equals(0, store.count())
    end)

    it("tells subscribers what happened until they unsubscribe", function()
      local seen = {}
      local id = store.on_change(function(event, n)
        seen[#seen + 1] = event .. ":" .. tostring(n)
      end)
      store.add({ kind = "file", path = "a" })
      store.move(1, 4)
      store.clear(4)
      store.off(id)
      store.add({ kind = "file", path = "b" })
      assert.same({ "set:1", "move:4", "clear:4" }, seen)
    end)

    it("survives a subscriber that raises", function()
      store.on_change(function()
        error("boom")
      end)
      assert.equals(1, store.add({ kind = "file", path = "a" }))
    end)
  end)

  describe("fixed slots", function()
    before_each(function()
      fresh({
        slots = {
          [3] = { kind = "file", path = "~/notes.md" },
          [5] = { kind = "cmd", cmd = "Lazy" },
        },
      })
    end)

    it("keep their number and are flagged", function()
      assert.is_true(store.get(3).fixed)
      assert.equals("~/notes.md", store.get(3).path)
      assert.equals("cmd", store.get(5).kind)
    end)

    it("are skipped when add() looks for a free number", function()
      assert.equals(1, store.add({ kind = "file", path = "a" }))
      assert.equals(2, store.add({ kind = "file", path = "b" }))
      assert.equals(4, store.add({ kind = "file", path = "c" }))
      assert.equals(6, store.add({ kind = "file", path = "d" }))
    end)

    it("cannot be replaced, changed, cleared or moved", function()
      assert.is_false((store.set(3, { kind = "file", path = "other" })))
      assert.is_false((store.update(3, { label = "x" })))
      assert.is_false((store.clear(3)))
      store.set(1, { kind = "file", path = "a" })
      assert.is_false((store.move(1, 3)))
      assert.is_false((store.move(3, 1)))
      assert.equals("~/notes.md", store.get(3).path)
    end)

    it("survive clear_all()", function()
      store.add({ kind = "file", path = "a" })
      store.clear_all()
      assert.equals(2, store.count())
    end)

    it("are never written", function()
      store.add({ kind = "file", path = "a" })
      assert.is_true(store.flush())
      local data = vim.json.decode(slurp(store.path()))
      assert.equals(1, #data.slots)
      assert.equals("a", data.slots[1].path)
    end)

    it("ignore invalid entries and say so", function()
      fresh({ slots = { [0] = { kind = "file" }, [2] = { path = "no kind" } } })
      drain()
      assert.equals(0, store.count())
      assert.is_true(#messages >= 1)
    end)
  end)

  describe("persistence", function()
    it("brings the dynamic slots back after a restart", function()
      store.add({ kind = "file", path = "a", label = "Alpha" })
      store.set(4, { kind = "url", url = "https://example.org" })
      store.add({ kind = "yank", text = "hello {file}" })
      assert.is_true(store.flush())

      store.reset()
      config.setup({ data_dir = dir, save_delay_ms = 0 })
      store.reload()

      assert.equals(3, store.count())
      assert.equals("Alpha", store.get(1).label)
      assert.equals("https://example.org", store.get(4).url)
      assert.equals("hello {file}", store.get(2).text)
    end)

    it("writes after save_delay_ms, batching a burst into one write", function()
      fresh({ save_delay_ms = 40 })
      store.add({ kind = "file", path = "a" })
      store.add({ kind = "file", path = "b" })
      assert.equals(0, vim.fn.filereadable(store.path()))
      vim.wait(400, function()
        return vim.fn.filereadable(store.path()) == 1
      end)
      local data = vim.json.decode(slurp(store.path()))
      assert.equals(2, #data.slots)
    end)

    it("writes pending changes when the scope is reloaded", function()
      fresh({ save_delay_ms = 10000 })
      store.add({ kind = "file", path = "a" })
      local path = store.path()
      store.reload()
      assert.equals(1, vim.fn.filereadable(path))
    end)

    it("keeps one file per scope: global and project do not share slots", function()
      fresh({ scope = "global" })
      store.add({ kind = "file", path = "g" })
      store.flush()
      assert.is_truthy(store.path():match("global%.json$"))

      fresh({ scope = "project" })
      assert.equals(0, store.count())
      assert.is_truthy(store.path():match("project%-%x+%.json$"))
    end)

    it("expands ~ in data_dir instead of creating a directory named '~'", function()
      fresh({ data_dir = "~/ui_slots_spec_never_created" })
      assert.is_nil(store.path():find("~", 1, true))
      assert.is_truthy(vim.startswith(store.path(), vim.fs.normalize("~")))
    end)

    it("writes nothing when persist is off", function()
      fresh({ persist = false })
      store.add({ kind = "file", path = "a" })
      assert.is_nil(store.path())
      assert.same({}, vim.fn.glob(dir .. "/*", false, true))
    end)

    it("leaves slots of a kind a file may not hold out of the file", function()
      store.add({ kind = "file", path = "a" })
      store.add({ kind = "lua", fn = function() end })
      store.add({ kind = "cmd", cmd = "Foo" })
      assert.equals(3, store.count())
      assert.is_true(store.flush())
      local data = vim.json.decode(slurp(store.path()))
      assert.equals(1, #data.slots)
      assert.equals("file", data.slots[1].kind)
    end)

    it("drops values JSON cannot hold instead of failing the write", function()
      store.add({ kind = "file", path = "a", weight = math.huge, other = 0 / 0, keep = 1 })
      assert.is_true(store.flush())
      local data = vim.json.decode(slurp(store.path()))
      assert.is_nil(data.slots[1].weight)
      assert.is_nil(data.slots[1].other)
      assert.equals(1, data.slots[1].keep)
    end)

    it("keeps the slots dirty and says so when the write fails", function()
      -- A file where the directory should be: mkdir -p cannot succeed.
      local blocker = dir .. "/blocker"
      vim.fn.writefile({ "x" }, blocker)
      fresh({ data_dir = blocker .. "/sub" })
      store.add({ kind = "file", path = "a" })
      local ok = store.flush()
      assert.is_false(ok)
      drain()
      assert.is_true(#messages >= 1)
    end)
  end)

  describe("what is saved can be read back", function()
    it("refuses a string over max_string_len for a kind that is saved", function()
      fresh({ max_string_len = 100 })
      local ok, err = store.set(1, { kind = "yank", text = string.rep("x", 101) })
      assert.is_false(ok)
      assert.is_truthy(err:find("100", 1, true))
      assert.is_nil((store.add({ kind = "yank", text = string.rep("x", 101) })))
      assert.is_true(store.set(1, { kind = "yank", text = string.rep("x", 100) }))
      store.set(2, { kind = "file", path = "a", label = "l" })
      local ok_update = store.update(2, { label = string.rep("y", 101) })
      assert.is_false(ok_update)
      assert.equals("l", store.get(2).label)
    end)

    it("also checks strings inside nested tables", function()
      fresh({ max_string_len = 10 })
      local ok = store.set(1, { kind = "file", path = "a", extra = { deep = string.rep("x", 11) } })
      assert.is_false(ok)
    end)

    it("lets a kind that is never saved keep a long string", function()
      fresh({ max_string_len = 10 })
      assert.is_true(store.set(1, { kind = "cmd", cmd = string.rep("x", 500) }))
    end)

    it("round-trips a long (but allowed) string without losing the neighbours", function()
      local text = string.rep("x", 3000)
      store.add({ kind = "yank", text = text })
      store.add({ kind = "file", path = "a.lua" })
      assert.is_true(store.flush())
      store.reset()
      config.setup({ data_dir = dir, save_delay_ms = 0 })
      store.reload()
      assert.equals(text, store.get(1).text)
      assert.equals("a.lua", store.get(2).path)
    end)

    it("does not write a file the next start would refuse to read", function()
      fresh({ max_file_kb = 1, save_delay_ms = 10000 })
      for i = 1, 40 do
        store.add({ kind = "yank", text = string.rep("z", 100) .. i })
      end
      local ok, err = store.flush()
      assert.is_false(ok)
      assert.is_truthy(err:find("1 KB", 1, true))
      assert.equals(0, vim.fn.filereadable(store.path()))
      drain()
      assert.is_true(#messages >= 1)
    end)
  end)

  describe("a write that fails", function()
    --- A data directory that cannot be created: a file sits where it should be.
    local function broken_dir()
      local blocker = dir .. "/blocker"
      vim.fn.writefile({ "x" }, blocker)
      return blocker .. "/sub"
    end

    it("is told every time, not only the first", function()
      fresh({ data_dir = broken_dir() })
      store.add({ kind = "file", path = "a" })
      drain()
      store.add({ kind = "file", path = "b" })
      drain()
      local failures = vim.tbl_filter(function(m)
        return m:find("could not create", 1, true) ~= nil
      end, messages)
      assert.is_true(#failures >= 2)
    end)

    it("keeps the unsaved slots through a reload instead of re-reading the disk", function()
      fresh({ data_dir = broken_dir() })
      store.add({ kind = "file", path = "a" })
      store.add({ kind = "file", path = "b" })
      store.reload()
      assert.equals(2, store.count())
      assert.equals("b", store.get(2).path)
      -- and it is still dirty: once the directory works, the next flush saves them
      vim.fn.delete(dir .. "/blocker")
      assert.is_true(store.flush())
      assert.equals(1, vim.fn.filereadable(store.path()))
    end)
  end)

  describe("scope_changed()", function()
    it("is false inside one project and when nothing is persisted", function()
      assert.is_false(store.scope_changed())
      fresh({ persist = false })
      assert.is_false(store.scope_changed())
    end)

    it("is true once the working directory points at another project", function()
      local old = vim.fn.getcwd()
      local other = dir .. "/other_project"
      vim.fn.mkdir(other, "p")
      fresh()
      vim.cmd.cd(other)
      local changed = store.scope_changed()
      vim.cmd.cd(old)
      assert.is_true(changed)
    end)
  end)

  describe("the data directory", function()
    it("is made absolute, so a :cd cannot move a pending write", function()
      local old = vim.fn.getcwd()
      vim.cmd.cd(vim.fs.dirname(dir))
      fresh({ data_dir = vim.fs.basename(dir) .. "/slots", save_delay_ms = 10000 })
      store.add({ kind = "file", path = "a" })
      local elsewhere = vim.fn.tempname()
      vim.fn.mkdir(elsewhere, "p")
      vim.cmd.cd(elsewhere)
      local ok = store.flush()
      vim.cmd.cd(old)
      assert.is_true(ok)
      assert.equals(1, vim.fn.filereadable(dir .. "/slots/" .. vim.fs.basename(store.path())))
      assert.same({}, vim.fn.glob(elsewhere .. "/*", false, true))
      vim.fn.delete(elsewhere, "rf")
    end)
  end)

  describe("the data file is untrusted", function()
    it("treats a JSON null as no value, not as an empty table", function()
      local path = (function()
        fresh()
        return store.path()
      end)()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({
        '{"format":"ui.slots","version":1,"slots":[{"n":1,"kind":"file","path":null,"label":{"a":null}}]}',
      }, path)
      store.reload()
      assert.is_nil(store.get(1).path)
      assert.same({}, store.get(1).label)
    end)

    ---@param entries table
    ---@return string path
    local function seed(entries)
      fresh()
      local path = store.path()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile(
        { vim.json.encode({ format = "ui.slots", version = 1, slots = entries }) },
        path
      )
      return path
    end

    it("never brings cmd or lua slots in, and reports them once", function()
      seed({
        { n = 1, kind = "file", path = "ok" },
        { n = 2, kind = "cmd", cmd = "Evil" },
        { n = 3, kind = "lua", fn = "os.execute('x')" },
      })
      store.reload()
      store.reload()
      drain()
      assert.equals(1, store.count())
      assert.equals("file", store.get(1).kind)
      local dropped = vim.tbl_filter(function(m)
        return m:find("may not hold", 1, true) ~= nil
      end, messages)
      assert.equals(1, #dropped)
      assert.is_truthy(dropped[1]:find("dropped 2 entries", 1, true))
    end)

    it("drops a file: address and a network path, which only setup() may name", function()
      seed({
        { n = 1, kind = "file", path = "ok" },
        { n = 2, kind = "url", url = "file:///C:/Users/x/payload.bat", label = "Docs" },
        { n = 3, kind = "file", path = "//192.0.2.1/share/notes.md" },
        { n = 4, kind = "file", path = [[\\192.0.2.1\share\notes.md]] },
        { n = 5, kind = "url", url = "https://example.org" },
      })
      store.reload()
      drain()
      local numbers = vim.tbl_map(function(slot)
        return slot.n
      end, store.list())
      assert.same({ 1, 5 }, numbers)
      local dropped = vim.tbl_filter(function(m)
        return m:find("dropped", 1, true) ~= nil
      end, messages)
      assert.equals(1, #dropped)
      assert.is_truthy(dropped[1]:find("dropped 3 entries", 1, true))
    end)

    it("keeps a copy of the file before it is saved without the entries it dropped", function()
      seed({
        { n = 1, kind = "file", path = "ok" },
        { n = 2, kind = "url", url = "file:///C:/Users/x/docs/readme.html", label = "Docs" },
      })
      store.reload()
      drain()
      store.add({ kind = "yank", text = "later" })
      store.flush()
      local dirpath = vim.fs.dirname(store.path())
      local copies = vim.fn.glob(dirpath .. "/*.dropped-*", false, true)
      assert.equals(1, #copies)
      assert.is_truthy(copies[1]:find("-" .. vim.fn.getpid() .. "-", 1, true))
      local kept = table.concat(vim.fn.readfile(copies[1]), "\n")
      assert.is_truthy(kept:find("readme.html", 1, true))
      local main = table.concat(vim.fn.readfile(store.path()), "\n")
      assert.is_nil(main:find("readme.html", 1, true))
      -- and only once: the next save does not copy again
      store.add({ kind = "yank", text = "again" })
      store.flush()
      assert.equals(1, #vim.fn.glob(dirpath .. "/*.dropped-*", false, true))
    end)

    it("keeps a copy too when a fixed slot takes the number of a saved one", function()
      fresh({ slots = { [1] = { kind = "file", path = "fixed" } } })
      local path = store.path()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({
        vim.json.encode({
          format = "ui.slots",
          slots = {
            { n = 1, kind = "file", path = "saved-keep-me" },
            { n = 2, kind = "yank", text = "two" },
          },
        }),
      }, path)
      store.reload()
      drain()
      store.update(2, { label = "x" })
      store.flush()
      local copies = vim.fn.glob(vim.fs.dirname(path) .. "/*.dropped-*", false, true)
      assert.equals(1, #copies)
      assert.is_truthy(
        table.concat(vim.fn.readfile(copies[1]), "\n"):find("saved-keep-me", 1, true)
      )
    end)

    it("does not save over a file it could not copy first", function()
      local path = seed({
        { n = 1, kind = "file", path = "ok" },
        { n = 2, kind = "url", url = "file:///C:/keep.html" },
      })
      store.reload()
      drain()
      local uv = vim.uv or vim.loop
      local original = uv.fs_copyfile
      uv.fs_copyfile = function()
        return nil, "EACCES"
      end
      store.add({ kind = "yank", text = "later" })
      local flushed, ok = pcall(store.flush)
      uv.fs_copyfile = original
      assert.is_true(flushed, ok)
      assert.is_false(ok)
      assert.is_truthy(table.concat(vim.fn.readfile(path), "\n"):find("keep.html", 1, true))
      -- the copy works again: the next save goes through, with the copy first
      assert.is_true(store.flush())
      assert.equals(1, #vim.fn.glob(vim.fs.dirname(path) .. "/*.dropped-*", false, true))
    end)

    it("does not print a hostile reason in full", function()
      seed({
        { n = 1, kind = "file", path = "ok" },
        { n = 2, kind = string.rep("A", 20000) },
      })
      store.reload()
      drain()
      local dropped = vim.tbl_filter(function(m)
        return m:find("dropped", 1, true) ~= nil
      end, messages)
      assert.equals(1, #dropped)
      assert.is_true(#dropped[1] < 600)
    end)

    it("says one message for a file of many bad entries", function()
      local entries = { { n = 1, kind = "file", path = "ok" } }
      for i = 2, 200 do
        entries[#entries + 1] = { n = i, kind = "cmd", cmd = "Evil" }
      end
      seed(entries)
      store.reload()
      drain()
      local dropped = vim.tbl_filter(function(m)
        return m:find("dropped", 1, true) ~= nil
      end, messages)
      assert.equals(1, #dropped)
    end)

    it("drops entries with bad numbers, missing kinds, or oversized strings", function()
      seed({
        { n = -4, kind = "file", path = "x" },
        { n = 1.5, kind = "file", path = "x" },
        { n = 5000000, kind = "file", path = "x" },
        { n = 6, path = "no kind" },
        { n = 7, kind = "file", path = string.rep("a", 5000) },
        "just a string",
        { n = 8, kind = "file", path = "fine" },
      })
      store.reload()
      assert.equals(1, store.count())
      assert.equals("fine", store.get(8).path)
    end)

    it("lets a fixed slot win over a saved one with the same number", function()
      fresh({ slots = { [1] = { kind = "file", path = "fixed" } } })
      local path = store.path()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({
        vim.json.encode({
          format = "ui.slots",
          slots = { { n = 1, kind = "file", path = "saved" } },
        }),
      }, path)
      store.reload()
      assert.equals("fixed", store.get(1).path)
    end)

    it("does not read a file above max_file_kb", function()
      local path = seed({ { n = 1, kind = "file", path = "ok" } })
      fresh({ max_file_kb = 1 })
      vim.fn.writefile(
        { vim.json.encode({ format = "ui.slots", pad = string.rep("x", 3000), slots = {} }) },
        path
      )
      store.reload()
      assert.is_not_nil(store.blocked_reason())
      assert.equals(0, store.count())
    end)

    it("never overwrites a file that is not its own", function()
      fresh()
      local path = store.path()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      local foreign = vim.json.encode({ somebody = "else", slots = "mine" })
      vim.fn.writefile({ foreign }, path)

      store.reload()
      assert.is_not_nil(store.blocked_reason())
      store.add({ kind = "file", path = "a" })
      local ok = store.flush()
      assert.is_false(ok)
      assert.equals(foreign, vim.trim(slurp(path)))
    end)

    it("treats a corrupt file the same way: untouched, persistence off for the scope", function()
      fresh()
      local path = store.path()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({ "{ this is not json" }, path)
      store.reload()
      assert.is_not_nil(store.blocked_reason())
      store.add({ kind = "file", path = "a" })
      assert.is_false((store.flush()))
      assert.equals("{ this is not json", vim.trim(slurp(path)))
    end)

    it("still works in memory when persistence is blocked", function()
      fresh()
      local path = store.path()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile({ "[]" }, path)
      store.reload()
      assert.equals(1, store.add({ kind = "file", path = "a" }))
      assert.equals("a", store.get(1).path)
    end)
  end)
end)
