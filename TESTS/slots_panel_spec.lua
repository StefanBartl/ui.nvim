-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, missing-fields

--- `ui.slots.view.panel` and `ui.slots.view.editor` -- the working view and the
--- editor, driven from keys and from the sheet's callbacks.

local config = require("ui.slots.config")
local editor = require("ui.slots.view.editor")
local panel = require("ui.slots.view.panel")
local registry = require("ui.slots.kinds.registry")
local slots = require("ui.slots")
local store = require("ui.slots.store")

describe("ui.slots panel and editor", function()
  local dir
  local messages
  local original_notify
  local saved

  local function flush()
    vim.wait(20, function()
      return false
    end)
    vim.wait(500, function()
      return not require("ui.slots.view.chips")._pending()
    end, 2)
  end

  ---@param opts table|nil
  local function start(opts)
    vim.fn.delete(dir .. "/data", "rf")
    panel.reset()
    require("ui.slots.view.chips").reset()
    slots.reset()
    store.reset()
    registry.reset()
    slots.setup(
      vim.tbl_extend("force", { data_dir = dir .. "/data", save_delay_ms = 0 }, opts or {})
    )
    slots.enable()
  end

  ---@param n integer
  local function add_yanks(n)
    for i = 1, n do
      slots.add({ kind = "yank", text = "slot " .. i })
    end
  end

  --- Press keys in Normal mode in the current window.
  ---@param keys string
  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "x", false)
    flush()
  end

  ---@param needle string
  ---@return boolean
  local function said(needle)
    return table.concat(messages, "\n"):find(needle, 1, true) ~= nil
  end

  --- Capture what the kit would open: the sheet and the chooser.
  ---@return { sheet: table|nil, select: table|nil, restore: fun() }
  local function capture()
    local sheet = require("ui.kit.sheet")
    local select = require("ui.kit.select")
    local cap = {}
    local original_sheet, original_select = sheet.open, select.open
    sheet.open = function(opts)
      cap.sheet = opts
      return {
        is_valid = function()
          return true
        end,
      }
    end
    select.open = function(opts)
      cap.select = opts
      return nil
    end
    cap.restore = function()
      sheet.open, select.open = original_sheet, original_select
    end
    return cap
  end

  ---@return string
  local function text()
    return table.concat(panel.lines(), "\n")
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    messages = {}
    original_notify = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    saved = { lines = vim.o.lines, columns = vim.o.columns }
    vim.o.lines, vim.o.columns = 40, 120
    vim.cmd("silent! %bwipeout!")
    start()
  end)

  after_each(function()
    panel.reset()
    require("ui.slots.view.chips").reset()
    slots.reset()
    store.reset()
    registry.reset()
    config.reset()
    vim.o.lines, vim.o.columns = saved.lines, saved.columns
    vim.notify = original_notify
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  describe("the panel", function()
    it("lists every slot, one row each, with number, icon and label", function()
      add_yanks(3)
      panel.open()
      assert.is_true(panel.is_open())
      local lines = panel.lines()
      assert.equals(3, #lines)
      assert.is_truthy(lines[1]:find("1", 1, true))
      assert.is_truthy(lines[1]:find("slot 1", 1, true))
      assert.is_truthy(lines[3]:find("slot 3", 1, true))
    end)

    it("is a focused float, docked at the right, about a quarter wide", function()
      add_yanks(1)
      panel.open()
      local win = vim.api.nvim_get_current_win()
      local cfg = vim.api.nvim_win_get_config(win)
      assert.equals("editor", cfg.relative)
      assert.is_true(cfg.focusable)
      assert.is_true(cfg.col > vim.o.columns / 2)
      assert.is_true(cfg.width >= 28 and cfg.width <= vim.o.columns / 3)
    end)

    it("says what to do when there are no slots", function()
      panel.open()
      assert.is_truthy(text():find("no slots yet", 1, true))
      assert.is_nil(panel.current())
    end)

    it("has no upper bound: forty slots, all listed", function()
      add_yanks(40)
      panel.open()
      assert.equals(40, #panel.lines())
    end)

    it(
      "puts the cursor on the slot run last, else on the file's slot, else on the first",
      function()
        add_yanks(5)
        slots.apply(4)
        panel.open()
        assert.equals(4, panel.current())
        panel.close()
        local path = dir .. "/f.txt"
        vim.fn.writefile({ "x" }, path)
        slots.add({ kind = "file", path = path })
        vim.cmd.edit(path)
        panel.open()
        assert.equals(6, panel.current())
      end
    )

    it("marks the file you are in, a fixed slot and a missing file", function()
      local path = dir .. "/a.txt"
      vim.fn.writefile({ "x" }, path)
      start({
        slots = { [2] = { kind = "yank", text = "fixed one" } },
      })
      slots.add({ kind = "file", path = path })
      slots.add({ kind = "file", path = dir .. "/gone.txt" })
      vim.cmd.edit(path)
      panel.open()
      local t = text()
      assert.is_truthy(t:find("fixed", 1, true))
      assert.is_truthy(t:find("✗", 1, true))
      assert.is_truthy(t:find("•", 1, true))
    end)

    it("follows changes made while it is open", function()
      add_yanks(2)
      panel.open()
      slots.add({ kind = "yank", text = "arrived late" })
      flush()
      assert.is_truthy(text():find("arrived late", 1, true))
    end)

    it("closes when the focus leaves it", function()
      add_yanks(1)
      vim.cmd.vsplit()
      local other = vim.api.nvim_get_current_win()
      panel.open()
      vim.api.nvim_set_current_win(other)
      flush()
      assert.is_false(panel.is_open())
    end)

    it("toggles, and a second open replaces the first", function()
      add_yanks(1)
      assert.is_true(panel.toggle())
      local first = vim.api.nvim_get_current_win()
      panel.open()
      assert.is_true(panel.is_open())
      assert.is_false(
        vim.api.nvim_win_is_valid(first) and first == vim.api.nvim_get_current_win() and false
      )
      assert.is_false(panel.toggle())
      assert.is_false(panel.is_open())
    end)

    it("cleans up: no window, no store listener, no leftover buffer", function()
      add_yanks(1)
      local before = #vim.api.nvim_list_wins()
      panel.open()
      local buf = vim.api.nvim_get_current_buf()
      panel.close()
      assert.equals(before, #vim.api.nvim_list_wins())
      assert.is_false(vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf))
    end)
  end)

  describe("the keys", function()
    before_each(function()
      add_yanks(5)
      panel.open()
    end)

    it("<CR> runs the slot under the cursor and closes the panel", function()
      config.get().clipboard = { "a" }
      press("2j")
      press("<CR>")
      assert.is_false(panel.is_open())
      assert.equals("slot 3", vim.fn.getreg("a"))
    end)

    it("typing a number puts the cursor on that slot, <CR> runs it", function()
      config.get().clipboard = { "a" }
      press("4")
      assert.equals(4, panel.current())
      press("<CR>")
      assert.equals("slot 4", vim.fn.getreg("a"))
    end)

    it("typing digits one after the other reaches numbers above 9", function()
      panel.close()
      slots.clear_all()
      for i = 1, 12 do
        slots.add({ kind = "yank", text = "slot " .. i })
      end
      panel.open()
      press("1")
      assert.equals(1, panel.current())
      press("2")
      assert.equals(12, panel.current())
      press("1")
      press("0")
      assert.equals(10, panel.current())
    end)

    it("a digit that makes no slot starts a number afresh", function()
      press("1")
      press("7") -- there is no slot 17 (nor 7 here): said, and the cursor stays
      assert.is_true(said("is empty"))
      press("3")
      assert.equals(3, panel.current())
    end)

    it("moving the cursor some other way ends a typed number", function()
      panel.close()
      slots.clear_all()
      for i = 1, 12 do
        slots.add({ kind = "yank", text = "slot " .. i })
      end
      panel.open()
      press("1")
      press("j")
      press("2")
      assert.equals(2, panel.current())
    end)

    it("0 never starts a number, and 0 after a 1 reaches slot 10", function()
      press("0")
      assert.is_true(said("is empty"))
    end)

    it("a number that is not a slot says so and keeps the panel", function()
      press("9")
      assert.is_true(panel.is_open())
      assert.is_true(said("is empty"))
    end)

    it("dd clears the slot and the list shrinks", function()
      press("2j")
      press("dd")
      assert.is_nil(slots.get(3))
      assert.equals(4, #panel.lines())
      assert.is_nil(text():find("slot 3", 1, true))
    end)

    it("dd on a fixed slot is refused and says why", function()
      start({ slots = { [1] = { kind = "yank", text = "fixed one" } } })
      panel.open()
      press("dd")
      assert.is_not_nil(slots.get(1))
      assert.is_true(said("fixed"))
    end)

    it("y copies what the slot stands for", function()
      config.get().clipboard = { "a" }
      press("y")
      assert.equals("slot 1", vim.fn.getreg("a"))
    end)

    it("<C-j> and <C-k> move the slot and the cursor goes with it", function()
      press("<C-j>")
      assert.equals("slot 1", slots.get(2).text)
      assert.equals("slot 2", slots.get(1).text)
      assert.equals(2, panel.current())
      press("<C-k>")
      assert.equals("slot 1", slots.get(1).text)
      assert.equals(1, panel.current())
    end)

    it("<C-k> at the top and <C-j> at the bottom do nothing", function()
      press("<C-k>")
      assert.equals("slot 1", slots.get(1).text)
      press("G")
      press("<C-j>")
      assert.equals("slot 5", slots.get(5).text)
    end)

    it("moving swaps with the next slot even across a gap in the numbers", function()
      slots.clear(3)
      flush()
      press("2j") -- on slot 4 now
      assert.equals(4, panel.current())
      press("<C-k>")
      assert.equals("slot 4", slots.get(2).text)
      assert.equals("slot 2", slots.get(4).text)
    end)

    it("a fixed slot cannot be moved", function()
      start({ slots = { [1] = { kind = "yank", text = "fixed" } } })
      slots.add({ kind = "yank", text = "free" })
      panel.open()
      press("<C-j>")
      assert.equals("fixed", slots.get(1).text)
      assert.is_true(said("fixed"))
    end)

    it("q and <Esc> close it", function()
      press("q")
      assert.is_false(panel.is_open())
      panel.open()
      press("<Esc>")
      assert.is_false(panel.is_open())
    end)

    it("a runs the editor with the file you came from as the default", function()
      panel.close()
      local path = dir .. "/came-from.txt"
      vim.fn.writefile({ "x" }, path)
      vim.cmd.edit(path)
      panel.open()
      local cap = capture()
      press("a")
      cap.restore()
      assert.is_not_nil(cap.select)
      assert.is_true(vim.tbl_contains(cap.select.items, "file"))
      cap.select.on_select("file")
      -- the chooser was captured and not shown; the sheet opens for the kind
    end)

    it("e opens the editor for the slot, and the panel comes back afterwards", function()
      press("2j")
      local cap = capture()
      press("e")
      assert.is_false(panel.is_open())
      assert.is_not_nil(cap.sheet)
      assert.is_truthy(cap.sheet.title:find("Slot 3", 1, true))
      cap.sheet.on_cancel()
      cap.restore()
      flush()
      assert.is_true(panel.is_open())
      assert.equals(3, panel.current())
    end)

    it("e on a fixed slot or a cmd slot says why it cannot", function()
      start({ slots = { [1] = { kind = "yank", text = "fixed" } } })
      slots.add({ kind = "cmd", cmd = "echo" })
      panel.open()
      local cap = capture()
      press("e")
      assert.is_nil(cap.sheet)
      assert.is_true(said("fixed in setup()"))
      press("j")
      press("e")
      cap.restore()
      assert.is_nil(cap.sheet)
      assert.is_true(said("cannot be changed here"))
    end)

    it("a right click opens the menu of the slot under the pointer", function()
      local cap = capture()
      local original = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = vim.api.nvim_get_current_win(), line = 3 }
      end
      press("<RightMouse>")
      vim.fn.getmousepos = original
      cap.restore()
      assert.is_not_nil(cap.select)
      assert.equals("slot 3", cap.select.title)
      local names = vim.tbl_map(function(a)
        return a.label
      end, cap.select.items)
      assert.same({ "Apply", "Edit", "Copy", "Clear" }, names)
    end)

    it("a right click outside the panel leaves it, as a left click does", function()
      vim.cmd.vsplit()
      local other = vim.api.nvim_get_current_win()
      panel.open()
      local original = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = other, line = 1 }
      end
      press("<RightMouse>")
      vim.fn.getmousepos = original
      assert.is_false(panel.is_open())
    end)

    it("is silent on a right click that is not on a row", function()
      local cap = capture()
      local original = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = vim.api.nvim_get_current_win(), line = 99 }
      end
      press("<RightMouse>")
      vim.fn.getmousepos = original
      cap.restore()
      assert.is_nil(cap.select)
    end)
  end)

  describe("the menu", function()
    it("offers to open a file slot in a split, a vertical split or a tab", function()
      local path = dir .. "/m.txt"
      vim.fn.writefile({ "x" }, path)
      slots.add({ kind = "file", path = path })
      local labels = vim.tbl_map(function(a)
        return a.label
      end, panel.actions(1))
      assert.same({
        "Apply",
        "Edit",
        "Copy",
        "Open in a split",
        "Open in a vsplit",
        "Open in a new tab",
        "Clear",
      }, labels)
    end)

    it("'Open in a vsplit' opens the file beside the current window", function()
      local path = dir .. "/m.txt"
      vim.fn.writefile({ "x" }, path)
      slots.add({ kind = "file", path = path })
      local before = #vim.api.nvim_tabpage_list_wins(0)
      for _, a in ipairs(panel.actions(1)) do
        if a.label == "Open in a vsplit" then
          a.run()
        end
      end
      assert.equals(before + 1, #vim.api.nvim_tabpage_list_wins(0))
      assert.equals(
        require("lib.nvim.fs.normkey")(path),
        require("lib.nvim.fs.normkey")(vim.api.nvim_buf_get_name(0))
      )
      -- and the slot itself is unchanged
      assert.is_nil(slots.get(1).target)
    end)

    it("'Open in a new tab' opens a tab", function()
      local path = dir .. "/m.txt"
      vim.fn.writefile({ "x" }, path)
      slots.add({ kind = "file", path = path })
      for _, a in ipairs(panel.actions(1)) do
        if a.label == "Open in a new tab" then
          a.run()
        end
      end
      assert.equals(2, #vim.api.nvim_list_tabpages())
    end)

    it("the other kinds do not get the open-in entries", function()
      add_yanks(1)
      local labels = vim.tbl_map(function(a)
        return a.label
      end, panel.actions(1))
      assert.same({ "Apply", "Edit", "Copy", "Clear" }, labels)
    end)

    it("Apply and Open in ... do not bring the panel back over their result", function()
      local path = dir .. "/m.txt"
      vim.fn.writefile({ "x" }, path)
      slots.add({ kind = "file", path = path })
      local cap = capture()
      local back = 0
      panel.menu(1, function()
        back = back + 1
      end)
      cap.restore()
      local items = cap.select.items
      cap.select.on_select(items[1]) -- Apply
      cap.select.on_select(items[4]) -- Open in a split
      assert.equals(0, back)
      cap.select.on_select(items[3]) -- Copy
      assert.equals(1, back)
    end)

    it("Edit hands the way back to the editor, which calls it when it closes", function()
      add_yanks(1)
      local cap = capture()
      local back = 0
      panel.menu(1, function()
        back = back + 1
      end)
      cap.select.on_select(cap.select.items[2]) -- Edit
      assert.equals(0, back, "not before the editor is done")
      assert.is_not_nil(cap.sheet)
      cap.sheet.on_cancel()
      cap.restore()
      assert.equals(1, back)
    end)

    it("a cancelled menu comes back, too", function()
      add_yanks(1)
      local cap = capture()
      local back = 0
      panel.menu(1, function()
        back = back + 1
      end)
      cap.restore()
      cap.select.on_cancel()
      assert.equals(1, back)
    end)

    it("selecting an entry runs it, then calls back", function()
      add_yanks(1)
      local cap = capture()
      local done = false
      panel.menu(1, function()
        done = true
      end)
      cap.restore()
      cap.select.on_select(cap.select.items[4])
      assert.is_true(done)
      assert.is_nil(slots.get(1))
    end)
  end)

  describe("a long list", function()
    local COUNT = 600

    --- Slots whose files are not there, named in the order of their numbers.
    ---@param n integer
    local function add_missing_files(n)
      for i = 1, n do
        store.add({ kind = "file", path = dir .. "/gone/file" .. i .. ".txt" })
      end
    end

    it(
      "shows every slot, looks closely only at the rows in view, and the rest on arrival",
      function()
        start()
        add_missing_files(COUNT)
        local uv = vim.uv or vim.loop
        local original = uv.fs_stat
        local stats = 0
        uv.fs_stat = function(path)
          if tostring(path):find("/gone/", 1, true) then
            stats = stats + 1
          end
          return original(path)
        end
        panel.open()
        uv.fs_stat = original

        local lines = panel.lines()
        assert.equals(COUNT, #lines)
        -- in view: the full render says the file is not there
        assert.is_truthy(lines[1]:find("✗", 1, true))
        -- far away: only the name as written, no file system asked for it yet
        assert.is_nil(lines[COUNT]:find("✗", 1, true))
        assert.is_truthy(lines[COUNT]:find("file" .. COUNT .. ".txt", 1, true))
        assert.is_true(stats < 150, "stat'ed " .. stats .. " files while opening")

        -- the cursor comes there: the row gets its full render
        vim.cmd("normal! G")
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
        assert.is_truthy(panel.lines()[COUNT]:find("✗", 1, true))
        assert.equals(COUNT, #panel.lines())
      end
    )

    it("redraws once for a change the panel made itself", function()
      start()
      add_missing_files(60)
      panel.open()
      local calls = 0
      local original = store.list
      store.list = function(...)
        calls = calls + 1
        return original(...)
      end
      press("dd")
      store.list = original
      assert.equals(1, calls)
      assert.equals(59, #panel.lines())
    end)

    it("redraws once for several changes made behind its back", function()
      start()
      add_missing_files(30)
      panel.open()
      local cheap_rows = 0
      local original = registry.render
      registry.render = function(slot, opts)
        if opts and opts.cheap then
          cheap_rows = cheap_rows + 1
        end
        return original(slot, opts)
      end
      slots.add({ kind = "yank", text = "one" })
      slots.add({ kind = "yank", text = "two" })
      slots.add({ kind = "yank", text = "three" })
      flush()
      registry.render = original
      -- one build of the 33 rows, not one per add
      assert.equals(33, cheap_rows)
      assert.equals(33, #panel.lines())
    end)

    it(
      "finds the slot of the file you came from, also in a list too long to check exactly",
      function()
        start()
        add_missing_files(300)
        local path = dir .. "/mine.txt"
        vim.fn.writefile({ "x" }, path)
        store.add({ kind = "file", path = path })
        vim.cmd.edit(path)
        panel.open()
        assert.equals(301, panel.current())
      end
    )

    it("leaves no WinScrolled autocmd behind when the panel closes", function()
      start()
      add_missing_files(5)
      local before = #vim.api.nvim_get_autocmds({ event = "WinScrolled" })
      for _ = 1, 3 do
        panel.open()
        panel.close()
      end
      assert.equals(before, #vim.api.nvim_get_autocmds({ event = "WinScrolled" }))
    end)

    it("finds a relative path as written in a list too long to check by real path", function()
      start()
      local path = dir .. "/rel.txt"
      vim.fn.writefile({ "x" }, path)
      local cwd = vim.fn.getcwd()
      vim.cmd.cd(dir)
      add_missing_files(400)
      store.add({ kind = "file", path = "rel.txt" })
      vim.cmd.edit(path)
      panel.open()
      local current = panel.current()
      panel.close()
      vim.cmd.cd(cwd)
      assert.equals(401, current)
    end)

    it("draws the empty list with its hint", function()
      start()
      panel.open()
      assert.same({ " no slots yet -- press a to add one" }, panel.lines())
    end)
  end)

  describe("the panel and a window that is gone", function()
    it("opens from the current window when the one it came from was closed", function()
      add_yanks(1)
      vim.cmd.vsplit()
      local gone = vim.api.nvim_get_current_win()
      vim.cmd.close()
      panel.open({ from = gone })
      assert.is_true(panel.is_open())
    end)
  end)

  describe("the editor", function()
    it("makes only the kinds a data file may hold", function()
      assert.same({ "file", "url", "yank", "mark" }, editor.kinds())
      registry.register("keeps", { apply = function() end, persist = true })
      assert.same({ "file", "url", "yank", "mark" }, editor.kinds())
    end)

    it("refuses an empty, a fixed and a code-running slot, with a reason each", function()
      start({ slots = { [1] = { kind = "yank", text = "fixed" } } })
      slots.add({ kind = "cmd", cmd = "echo" })
      slots.add({ kind = "lua", fn = function() end })
      assert.is_truthy(editor.refusal(9):find("empty", 1, true))
      assert.is_truthy(editor.refusal(1):find("fixed", 1, true))
      assert.is_truthy(editor.refusal(2):find("cmd", 1, true))
      assert.is_truthy(editor.refusal(3):find("lua", 1, true))
      slots.add({ kind = "yank", text = "ok" })
      assert.is_nil(editor.refusal(4))
    end)

    it("asks for the kind first when adding, then opens the sheet for it", function()
      local cap = capture()
      editor.open({})
      assert.is_not_nil(cap.select)
      assert.equals("Kind of slot", cap.select.title)
      assert.same({ "file", "url", "yank", "mark" }, cap.select.items)
      cap.select.on_select("url")
      cap.restore()
      assert.is_not_nil(cap.sheet)
      assert.is_truthy(cap.sheet.title:find("url", 1, true))
      local names = vim.tbl_map(function(f)
        return f.name
      end, cap.sheet.fields)
      assert.same({ "url", "label", "icon", "style", "number" }, names)
    end)

    it("goes straight to the sheet when the kind is given", function()
      local cap = capture()
      editor.open({ kind = "file" })
      cap.restore()
      assert.is_nil(cap.select)
      local names = vim.tbl_map(function(f)
        return f.name
      end, cap.sheet.fields)
      assert.same({ "path", "target", "label", "icon", "style", "number" }, names)
    end)

    it("does not make a kind it has no fields for, and says so", function()
      local called
      local cap = capture()
      editor.open({
        kind = "cmd",
        on_close = function(n)
          called = n == nil
        end,
      })
      cap.restore()
      assert.is_nil(cap.sheet)
      assert.is_true(called)
      assert.is_true(said("makes no 'cmd' slots"))
    end)

    it("fills the sheet with the slot's own values when editing", function()
      slots.add({
        kind = "file",
        path = "~/n.md",
        label = "Notes",
        style = "double",
        target = "tab",
      })
      local cap = capture()
      editor.open({ n = 1 })
      cap.restore()
      local by = {}
      for _, f in ipairs(cap.sheet.fields) do
        by[f.name] = f
      end
      assert.equals("~/n.md", by.path.default)
      assert.equals("tab", by.target.default)
      assert.equals("Notes", by.label.default)
      assert.equals("double", by.style.default)
      assert.equals("1", by.number.default)
    end)

    it("offers the next free number when adding, and the default target of the config", function()
      add_yanks(2)
      config.get().target = "vsplit"
      local cap = capture()
      editor.open({ kind = "file" })
      cap.restore()
      local by = {}
      for _, f in ipairs(cap.sheet.fields) do
        by[f.name] = f
      end
      assert.equals("3", by.number.default)
      assert.equals("vsplit", by.target.default)
    end)

    it("takes a default for a field (the file you came from)", function()
      local cap = capture()
      editor.open({ kind = "file", defaults = { path = "/some/where.lua" } })
      cap.restore()
      assert.equals("/some/where.lua", cap.sheet.fields[1].default)
    end)

    it("checks each field through the kind's own validation", function()
      local cap = capture()
      editor.open({ kind = "url" })
      cap.restore()
      local url = cap.sheet.fields[1]
      local ok, err = url.validate("javascript:alert(1)")
      assert.is_false(ok)
      assert.is_truthy(err:find("scheme", 1, true))
      assert.is_true((url.validate("https://example.org")))
      local cap2 = capture()
      editor.open({ kind = "mark" })
      cap2.restore()
      assert.is_false((cap2.sheet.fields[1].validate("0")))
      assert.is_false((cap2.sheet.fields[1].validate("1.5")))
      assert.is_true((cap2.sheet.fields[1].validate("3")))
    end)

    it("checks the number: whole, in range, and free unless it is the slot's own", function()
      add_yanks(2)
      local cap = capture()
      editor.open({ n = 1 })
      cap.restore()
      local number
      for _, f in ipairs(cap.sheet.fields) do
        if f.name == "number" then
          number = f
        end
      end
      assert.is_true((number.validate("1")))
      assert.is_false((number.validate("2")))
      assert.is_true((number.validate("7")))
      assert.is_false((number.validate("0")))
      assert.is_false((number.validate("1.5")))
      assert.is_false((number.validate("abc")))
      assert.is_false((number.validate(tostring(config.MAX_N + 1))))
    end)

    it("saves an added slot from the sheet's answers", function()
      local cap = capture()
      editor.open({ kind = "yank" })
      cap.restore()
      cap.sheet.on_submit({
        text = "hello {word}",
        register = "",
        label = "greet",
        icon = "",
        style = "(default)",
        number = "5",
      })
      local slot = slots.get(5)
      assert.equals("yank", slot.kind)
      assert.equals("hello {word}", slot.text)
      assert.equals("greet", slot.label)
      assert.is_nil(slot.register)
      assert.is_nil(slot.icon)
      assert.is_nil(slot.style)
    end)

    it("keeps a style that was chosen, and a mark's number as a number", function()
      local cap = capture()
      editor.open({ kind = "mark" })
      cap.restore()
      cap.sheet.on_submit({ index = "2", label = "", icon = "", style = "ascii", number = "1" })
      assert.equals("ascii", slots.get(1).style)
      assert.equals(2, slots.get(1).index)
    end)

    it("saves a change to the same slot", function()
      slots.add({ kind = "yank", text = "before", label = "old" })
      local cap = capture()
      editor.open({ n = 1 })
      cap.restore()
      cap.sheet.on_submit({
        text = "after",
        register = "",
        label = "",
        icon = "",
        style = "(default)",
        number = "1",
      })
      assert.equals("after", slots.get(1).text)
      assert.is_nil(slots.get(1).label)
      assert.equals(1, #slots.list())
    end)

    it("a changed number moves the slot", function()
      slots.add({ kind = "yank", text = "mover" })
      local cap = capture()
      editor.open({ n = 1 })
      cap.restore()
      cap.sheet.on_submit({
        text = "mover",
        register = "",
        label = "",
        icon = "",
        style = "(default)",
        number = "8",
      })
      assert.is_nil(slots.get(1))
      assert.equals("mover", slots.get(8).text)
    end)

    it("keeps the remembered cursor position of a file slot that stays the same file", function()
      local path = dir .. "/p.txt"
      vim.fn.writefile({ "a", "b", "c" }, path)
      local n = slots.add({ kind = "file", path = path })
      store.update(n, { line = 3, col = 2 })
      local cap = capture()
      editor.open({ n = n })
      cap.restore()
      cap.sheet.on_submit({
        path = path,
        target = "current",
        label = "renamed",
        icon = "",
        style = "(default)",
        number = tostring(n),
      })
      assert.equals("renamed", slots.get(n).label)
      assert.equals(3, slots.get(n).line)
      assert.equals(2, slots.get(n).col)
    end)

    it("forgets the position when the path changes", function()
      local path = dir .. "/p.txt"
      vim.fn.writefile({ "a" }, path)
      local n = slots.add({ kind = "file", path = path })
      store.update(n, { line = 3, col = 2 })
      local cap = capture()
      editor.open({ n = n })
      cap.restore()
      cap.sheet.on_submit({
        path = dir .. "/other.txt",
        target = "current",
        label = "",
        icon = "",
        style = "(default)",
        number = tostring(n),
      })
      assert.is_nil(slots.get(n).line)
    end)

    it("keeps the sheet's answers when a save is refused: the sheet comes back filled", function()
      local cap = capture()
      editor.open({ kind = "url" })
      local first = cap.sheet
      first.on_submit({
        url = "javascript:alert(1)",
        label = "mine",
        icon = "",
        style = "(default)",
        number = "1",
      })
      flush()
      assert.is_not_nil(cap.sheet)
      assert.is_not.equals(first, cap.sheet, "a new sheet")
      local by = {}
      for _, f in ipairs(cap.sheet.fields) do
        by[f.name] = f
      end
      assert.equals("javascript:alert(1)", by.url.default)
      assert.equals("mine", by.label.default)
      -- fixing it and submitting again saves
      cap.sheet.on_submit({
        url = "https://example.org",
        label = "mine",
        icon = "",
        style = "(default)",
        number = "1",
      })
      cap.restore()
      assert.equals("https://example.org", slots.get(1).url)
    end)

    it("a refused save that is cancelled afterwards calls on_close once, with nil", function()
      local seen = {}
      local cap = capture()
      editor.open({
        kind = "url",
        on_close = function(n)
          seen[#seen + 1] = n or "none"
        end,
      })
      cap.sheet.on_submit({
        url = "javascript:x",
        label = "",
        icon = "",
        style = "(default)",
        number = "1",
      })
      flush()
      cap.sheet.on_cancel()
      cap.restore()
      assert.same({ "none" }, seen)
    end)

    it("checks the length of a text, label and icon in the sheet itself", function()
      config.get().max_string_len = 20
      local cap = capture()
      editor.open({ kind = "yank" })
      cap.restore()
      local by = {}
      for _, f in ipairs(cap.sheet.fields) do
        by[f.name] = f
      end
      local long = string.rep("x", 21)
      assert.is_false((by.text.validate(long)))
      assert.is_false((by.label.validate(long)))
      assert.is_false((by.icon.validate(long)))
      assert.is_true((by.label.validate(string.rep("x", 20))))
    end)

    it("leaves a text alone that was not touched, newlines and all", function()
      local n = slots.add({ kind = "yank", text = "line one\nline two", label = "  padded  " })
      local cap = capture()
      editor.open({ n = n })
      cap.restore()
      -- what the one-line sheet shows, handed back unchanged
      cap.sheet.on_submit({
        text = "line one line two",
        register = "",
        label = "padded",
        icon = "",
        style = "(default)",
        number = tostring(n),
      })
      assert.equals("line one\nline two", slots.get(n).text)
      assert.equals("  padded  ", slots.get(n).label)
    end)

    it("changes a text that was edited", function()
      local n = slots.add({ kind = "yank", text = "line one\nline two" })
      local cap = capture()
      editor.open({ n = n })
      cap.restore()
      cap.sheet.on_submit({
        text = "something else",
        register = "",
        label = "",
        icon = "",
        style = "(default)",
        number = tostring(n),
      })
      assert.equals("something else", slots.get(n).text)
    end)

    it("reports a slot the kind refuses on submit instead of saving it", function()
      local cap = capture()
      editor.open({ kind = "url" })
      cap.restore()
      cap.sheet.on_submit({
        url = "javascript:alert(1)",
        label = "",
        icon = "",
        style = "(default)",
        number = "1",
      })
      assert.is_nil(slots.get(1))
      assert.is_true(said("scheme"))
    end)

    it("calls on_close with the number it saved, or nil", function()
      local seen = {}
      local cap = capture()
      editor.open({
        kind = "yank",
        on_close = function(n)
          seen[#seen + 1] = n or "none"
        end,
      })
      cap.sheet.on_submit({
        text = "x",
        register = "",
        label = "",
        icon = "",
        style = "(default)",
        number = "4",
      })
      editor.open({
        kind = "yank",
        on_close = function(n)
          seen[#seen + 1] = n or "none"
        end,
      })
      cap.sheet.on_cancel()
      cap.restore()
      assert.same({ 4, "none" }, seen)
    end)

    it("calls on_close only once", function()
      local count = 0
      local cap = capture()
      editor.open({
        kind = "yank",
        on_close = function()
          count = count + 1
        end,
      })
      cap.restore()
      cap.sheet.on_cancel()
      cap.sheet.on_cancel()
      assert.equals(1, count)
    end)
  end)

  describe("the commands", function()
    before_each(function()
      require("ui.bindings.usrcmds").setup()
    end)

    it(":UI slots panel opens and closes the panel", function()
      add_yanks(2)
      vim.cmd("UI slots panel")
      assert.is_true(panel.is_open())
      vim.cmd("UI slots panel")
      assert.is_false(panel.is_open())
    end)

    it(
      ":UI slots edit opens the editor to add a slot, :UI slots edit 2 to change slot 2",
      function()
        add_yanks(2)
        local cap = capture()
        vim.cmd("UI slots edit")
        assert.is_not_nil(cap.select)
        cap.select = nil
        vim.cmd("UI slots edit 2")
        cap.restore()
        assert.is_nil(cap.select)
        assert.is_truthy(cap.sheet.title:find("Slot 2", 1, true))
      end
    )

    it(":UI slots edit with a bad number says so", function()
      local cap = capture()
      vim.cmd("UI slots edit abc")
      cap.restore()
      assert.is_nil(cap.sheet)
      assert.is_true(said("not a slot number"))
    end)

    it("edit gives the file you are in as the path default when adding", function()
      local path = dir .. "/cur.txt"
      vim.fn.writefile({ "x" }, path)
      vim.cmd.edit(path)
      local cap = capture()
      slots.edit(nil, { kind = "file" })
      cap.restore()
      local key = require("lib.nvim.fs.normkey")
      assert.equals(key(path), key(cap.sheet.fields[1].default))
    end)

    it("with layout = panel, toggle/open/close act on the panel", function()
      start({ layout = "panel" })
      add_yanks(1)
      vim.cmd("UI slots toggle")
      assert.is_true(panel.is_open())
      assert.is_false(require("ui.slots.view.chips").wanted())
      vim.cmd("UI slots close")
      assert.is_false(panel.is_open())
      vim.cmd("UI slots open")
      assert.is_true(panel.is_open())
      vim.cmd("UI slots open")
      assert.is_true(panel.is_open())
    end)

    it("completes panel and edit, edit with the slot numbers", function()
      add_yanks(2)
      local first = vim.fn.getcompletion("UI slots ", "cmdline")
      assert.is_true(vim.tbl_contains(first, "panel"))
      assert.is_true(vim.tbl_contains(first, "edit"))
      assert.same({ "1", "2" }, vim.fn.getcompletion("UI slots edit ", "cmdline"))
    end)

    it("the panel key opens the panel", function()
      start({ keys = { panel = "<leader>sp" } })
      add_yanks(1)
      vim.api.nvim_feedkeys(vim.keycode("<leader>sp"), "x", false)
      flush()
      assert.is_true(panel.is_open())
    end)

    it("is in the help text", function()
      messages = {}
      vim.cmd("UI help")
      assert.is_true(said(":UI slots panel"))
      assert.is_true(said(":UI slots edit"))
    end)
  end)
end)
