-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, missing-fields

--- `ui.slots.view.chips` -- the slot bar: what it draws, where, how it scrolls,
--- and what a click, the wheel and a right click do.

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local slots = require("ui.slots")
local store = require("ui.slots.store")
local chips = require("ui.slots.view.chips")

describe("ui.slots bar", function()
  local dir
  local messages
  local original_notify
  local saved

  --- Run the scheduled redraws.
  local function flush()
    vim.wait(40, function()
      return false
    end)
  end

  ---@param opts table|nil
  local function start(opts)
    -- A fresh data directory every time: slots are saved, and the next start
    -- would load them again.
    vim.fn.delete(dir .. "/data", "rf")
    chips.reset()
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

  ---@return string[]
  local function lines()
    return chips.state().lines
  end

  ---@return string
  local function text()
    return table.concat(lines(), "\n")
  end

  --- Point the pointer at line `line` of the bar and deliver `key`.
  ---@param key string  # "<LeftMouse>", ...
  ---@param line integer
  local function click(key, line)
    local st = chips.state()
    local original = vim.fn.getmousepos
    vim.fn.getmousepos = function()
      return { winid = st.win, line = line, screenrow = 1, screencol = 1 }
    end
    chips._on_key("", vim.api.nvim_replace_termcodes(key, true, true, true))
    vim.fn.getmousepos = original
    flush()
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
    vim.o.lines, vim.o.columns = 30, 100
    vim.cmd("silent! %bwipeout!")
    start()
  end)

  after_each(function()
    chips.reset()
    slots.reset()
    store.reset()
    registry.reset()
    config.reset()
    vim.o.lines, vim.o.columns = saved.lines, saved.columns
    vim.notify = original_notify
    vim.cmd("silent! tabonly")
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  describe("what it draws", function()
    it("is a float with a rounded chip per slot, number and label inside", function()
      add_yanks(2)
      chips.open()
      local st = chips.state()
      assert.is_not_nil(st.win)
      assert.equals(6, #st.lines)
      assert.is_truthy(st.lines[1]:find("╭", 1, true))
      assert.is_truthy(st.lines[1]:find("╮", 1, true))
      assert.is_truthy(st.lines[2]:find("1", 1, true))
      assert.is_truthy(st.lines[2]:find("slot 1", 1, true))
      assert.is_truthy(st.lines[3]:find("╰", 1, true))
      assert.is_truthy(st.lines[5]:find("slot 2", 1, true))
    end)

    it("sits at the right edge, below nothing, as wide as its widest chip", function()
      add_yanks(1)
      chips.open()
      local cfg = vim.api.nvim_win_get_config(chips.state().win)
      assert.equals("editor", cfg.relative)
      assert.equals(0, cfg.row)
      assert.equals(vim.o.columns - cfg.width, cfg.col)
      assert.is_true(cfg.width >= 10)
      assert.is_true(cfg.zindex < 50)
      for _, l in ipairs(lines()) do
        assert.equals(cfg.width, vim.fn.strdisplaywidth(l))
      end
    end)

    it("makes room for a tabline", function()
      vim.o.showtabline = 2
      add_yanks(1)
      chips.open()
      assert.equals(1, vim.api.nvim_win_get_config(chips.state().win).row)
      vim.o.showtabline = 1
    end)

    it("can sit on the left", function()
      start({ side = "left" })
      add_yanks(1)
      chips.open()
      assert.equals(0, vim.api.nvim_win_get_config(chips.state().win).col)
    end)

    it(
      "shows nothing, and no window, while there are no slots, then appears with the first",
      function()
        chips.open()
        assert.is_nil(chips.state().win)
        assert.is_true(chips.wanted())
        add_yanks(1)
        flush()
        assert.is_not_nil(chips.state().win)
        slots.clear(1)
        flush()
        assert.is_nil(chips.state().win)
      end
    )

    it("follows changes to the slots", function()
      add_yanks(1)
      chips.open()
      slots.add({ kind = "yank", text = "late arrival" })
      flush()
      assert.is_truthy(text():find("late arrival", 1, true))
      slots.clear(1)
      flush()
      assert.is_nil(text():find("slot 1", 1, true))
    end)

    it("cuts a label that does not fit and says so with an ellipsis", function()
      start({ width = 14 })
      slots.add({ kind = "yank", text = "an extremely long label that cannot fit" })
      chips.open()
      assert.is_truthy(text():find("…", 1, true))
      assert.equals(14, vim.api.nvim_win_get_config(chips.state().win).width)
    end)

    it(
      "marks the slot of the current file, a file with unsaved changes and a missing file",
      function()
        local path = require("lib.nvim.fs.normkey")((function()
          local p = dir .. "/a.txt"
          vim.fn.writefile({ "x" }, p)
          return p
        end)())
        slots.add({ kind = "file", path = path })
        slots.add({ kind = "file", path = dir .. "/gone.txt" })
        vim.cmd.edit(path)
        chips.open()
        assert.is_truthy(lines()[2]:find("•", 1, true))
        assert.is_nil(lines()[2]:find("+", 1, true))
        assert.is_truthy(lines()[5]:find("✗", 1, true))
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed" })
        chips.refresh()
        assert.is_truthy(lines()[2]:find(" +", 1, true))
      end
    )
  end)

  describe("styles", function()
    it("draws the double and the ascii borders", function()
      start({ style = "double" })
      add_yanks(1)
      chips.open()
      assert.is_truthy(lines()[1]:find("╔", 1, true))
      start({ style = "ascii" })
      add_yanks(1)
      chips.open()
      assert.is_truthy(lines()[1]:find("+-", 1, true))
    end)

    it("draws solid and minimal as one row each", function()
      start({ style = "solid" })
      add_yanks(2)
      chips.open()
      assert.equals(2, #lines())
      start({ style = "minimal" })
      add_yanks(2)
      chips.open()
      assert.equals(2, #lines())
    end)

    it("understands the chip vocabulary of ui.kit", function()
      start({ style = "rounded_chip" })
      add_yanks(1)
      chips.open()
      assert.equals(3, #lines())
      start({ style = "chip" })
      add_yanks(1)
      chips.open()
      assert.equals(1, #lines())
      start({ style = "classic" })
      add_yanks(1)
      chips.open()
      assert.equals(1, #lines())
    end)

    it("lets a slot choose its own style, and the rows stay right", function()
      add_yanks(1)
      slots.add({ kind = "yank", text = "flat one", style = "minimal" })
      chips.open()
      assert.equals(4, #lines())
      assert.equals(1, chips.state().rows[1].n)
      assert.equals(2, chips.state().rows[4].n)
    end)

    it("falls back to rounded for an unknown style and says so once", function()
      start({ style = "wavy" })
      add_yanks(1)
      chips.open()
      chips.refresh()
      assert.is_truthy(lines()[1]:find("╭", 1, true))
      local told = vim.tbl_filter(function(m)
        return m:find("wavy", 1, true) ~= nil
      end, messages)
      assert.equals(1, #told)
    end)
  end)

  describe("accordion", function()
    before_each(function()
      -- 14 rows: room for three chips (9 rows) and a counter below them.
      vim.o.lines = 14
      vim.o.cmdheight = 1
      vim.o.laststatus = 1
      add_yanks(10)
      chips.open()
    end)

    it("shows as many slots as there are rows, and counts the rest", function()
      assert.equals(10, #lines())
      assert.is_truthy(lines()[10]:find("▼ +7", 1, true))
      assert.is_truthy(lines()[2]:find("slot 1", 1, true))
      assert.is_truthy(lines()[8]:find("slot 3", 1, true))
      assert.is_nil(text():find("▲", 1, true))
    end)

    it("scrolls by one: the top slot drops out, the next comes in below", function()
      chips.scroll(1)
      assert.is_truthy(lines()[1]:find("▲ +1", 1, true))
      assert.is_truthy(lines()[3]:find("slot 2", 1, true))
      assert.is_truthy(text():find("slot 4", 1, true))
      assert.is_nil(text():find("slot 1\n", 1, true))
      assert.is_truthy(text():find("▼ +6", 1, true))
    end)

    it("does not scroll past either end", function()
      chips.scroll(-1)
      assert.is_nil(text():find("▲", 1, true))
      chips.scroll(100)
      assert.is_truthy(text():find("slot 10", 1, true))
      assert.is_nil(text():find("▼", 1, true))
      assert.is_truthy(text():find("▲ +7", 1, true))
    end)

    it("moves as little as it must to bring the focus slot into view", function()
      chips.set_focus(4)
      flush()
      assert.is_truthy(text():find("slot 4", 1, true))
      assert.is_truthy(lines()[1]:find("▲ +1", 1, true))
      assert.equals(2, chips.state().top_n)
    end)

    it("jumps up to a focus slot above the window", function()
      chips.scroll(100)
      chips.set_focus(2)
      flush()
      assert.is_truthy(text():find("slot 2", 1, true))
      assert.equals(2, chips.state().top_n)
    end)

    it("leaves a window alone that already shows the focus slot", function()
      chips.set_focus(2)
      flush()
      assert.equals(1, chips.state().top_n)
    end)

    it("shows the slot that was just applied", function()
      slots.apply(9)
      flush()
      assert.is_truthy(text():find("slot 9", 1, true))
    end)

    it("shows a slot that was just added, wherever it lands", function()
      slots.add({ kind = "yank", text = "brand new" })
      flush()
      assert.is_truthy(text():find("brand new", 1, true))
    end)

    it("closes the gap when slots are cleared and everything fits again", function()
      chips.scroll(100)
      for n = 4, 10 do
        slots.clear(n)
      end
      flush()
      assert.is_nil(text():find("▲", 1, true))
      assert.is_nil(text():find("▼", 1, true))
      assert.is_truthy(text():find("slot 1", 1, true))
      assert.equals(9, #lines())
    end)

    it("fills the window from the end of the list, never leaving it half empty", function()
      chips.scroll(100)
      for n = 8, 10 do
        slots.clear(n)
      end
      flush()
      -- 7 slots left: the window still shows three and the counters
      assert.equals(10, #lines())
      assert.is_truthy(text():find("slot 7", 1, true))
    end)

    it("shrinks and grows with the editor", function()
      vim.o.lines = 40
      vim.api.nvim_exec_autocmds("VimResized", {})
      flush()
      assert.equals(30, #lines())
      assert.is_nil(text():find("▼", 1, true))
      vim.o.lines = 14
      vim.api.nvim_exec_autocmds("VimResized", {})
      flush()
      assert.equals(10, #lines())
    end)

    it("still shows one slot when there is hardly any room", function()
      vim.o.lines = 6
      vim.api.nvim_exec_autocmds("VimResized", {})
      flush()
      assert.is_truthy(text():find("slot 1", 1, true))
    end)

    it("numbers with gaps are shown in order, the gaps are not", function()
      slots.clear_all()
      slots.add({ kind = "yank", text = "a" }, 3)
      slots.add({ kind = "yank", text = "b" }, 12)
      flush()
      assert.is_truthy(lines()[2]:find("3", 1, true))
      assert.is_truthy(lines()[5]:find("12", 1, true))
    end)
  end)

  describe("the mouse", function()
    local path, main

    before_each(function()
      path = require("lib.nvim.fs.normkey")((function()
        local p = dir .. "/a.txt"
        vim.fn.writefile({ "one", "two" }, p)
        return p
      end)())
      slots.add({ kind = "file", path = path })
      slots.add({ kind = "yank", text = "copy me" })
      chips.open()
      main = vim.api.nvim_get_current_win()
    end)

    it("applies the slot under a left click and returns the focus it moved", function()
      vim.cmd("enew")
      main = vim.api.nvim_get_current_win()
      local bar = chips.state().win
      -- what Neovim does with a click on a focusable float: it enters it
      local st = chips.state()
      local original = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = st.win, line = 2 }
      end
      chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
      vim.fn.getmousepos = original
      vim.api.nvim_set_current_win(bar)
      flush()
      assert.equals(main, vim.api.nvim_get_current_win())
      assert.equals(path, require("lib.nvim.fs.normkey")(vim.api.nvim_buf_get_name(0)))
    end)

    it("hits every row of a chip, border rows included", function()
      config.get().clipboard = { "a" }
      for _, line in ipairs({ 4, 5, 6 }) do
        vim.fn.setreg("a", "")
        click("<LeftMouse>", line)
        assert.equals("copy me", vim.fn.getreg("a"), "line " .. line)
      end
    end)

    it("ignores a click that is not on the bar", function()
      vim.cmd("enew")
      local original = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = vim.api.nvim_get_current_win(), line = 2 }
      end
      chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
      vim.fn.getmousepos = original
      flush()
      assert.equals("", vim.api.nvim_buf_get_name(0))
    end)

    it("ignores keys that are no mouse keys, and a click on the bar's empty row", function()
      local st = chips.state()
      local original = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = st.win, line = 99 }
      end
      chips._on_key("j", "j")
      chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
      vim.fn.getmousepos = original
      flush()
      assert.is_true(vim.api.nvim_win_is_valid(st.win))
    end)

    it("does not change the key it looks at", function()
      assert.is_nil(
        chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
      )
    end)

    it("opens a menu of the slot on a right click", function()
      local select = require("ui.kit.select")
      local original = select.open
      local seen
      select.open = function(opts)
        seen = opts
      end
      click("<RightMouse>", 5)
      select.open = original
      assert.is_not_nil(seen)
      assert.is_truthy(seen.title:find("2", 1, true))
      local names = vim.tbl_map(function(a)
        return a.label
      end, seen.items)
      assert.same({ "Apply", "Copy", "Clear" }, names)
      seen.on_select(seen.items[3])
      assert.is_nil(slots.get(2))
    end)

    it("scrolls with the wheel over the bar", function()
      vim.o.lines = 14
      slots.clear_all()
      add_yanks(10)
      chips.set_focus(1)
      flush()
      click("<ScrollWheelDown>", 2)
      assert.equals(2, chips.state().top_n)
      click("<ScrollWheelUp>", 2)
      assert.equals(1, chips.state().top_n)
    end)

    it("scrolls by one on a click on a counter", function()
      vim.o.lines = 14
      slots.clear_all()
      add_yanks(10)
      chips.set_focus(1)
      flush()
      click("<LeftMouse>", 10)
      assert.equals(2, chips.state().top_n)
      click("<LeftMouse>", 1)
      assert.equals(1, chips.state().top_n)
    end)

    it("tells ui.menu that the pointer is on the bar", function()
      local st = chips.state()
      local original = vim.fn.getmousepos
      vim.fn.getmousepos = function()
        return { winid = st.win, line = 2 }
      end
      assert.is_true(chips.pointer_on_bar())
      local menu = require("ui.menu")
      local opened = false
      local original_open = menu.open
      menu.open = function()
        opened = true
      end
      menu.on_right_click()
      menu.open = original_open
      vim.fn.getmousepos = original
      assert.is_false(opened)
      assert.is_false(chips.pointer_on_bar())
    end)
  end)

  describe("focus", function()
    it("sends the focus back when the bar is entered some other way", function()
      add_yanks(2)
      chips.open()
      local main = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(chips.state().win)
      flush()
      assert.equals(main, vim.api.nvim_get_current_win())
    end)
  end)

  describe("tabs", function()
    it("follows you to another tab page, one bar at a time", function()
      add_yanks(2)
      chips.open()
      local first = chips.state().win
      vim.cmd.tabnew()
      flush()
      local second = chips.state().win
      assert.is_not_nil(second)
      assert.is_not.equals(first, second)
      assert.equals(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(second))
      assert.is_false(vim.api.nvim_win_is_valid(first))
      vim.cmd.tabclose()
      flush()
      assert.equals(
        vim.api.nvim_get_current_tabpage(),
        vim.api.nvim_win_get_tabpage(chips.state().win)
      )
    end)
  end)

  describe("switching on and off", function()
    it("toggle is idempotent and cleans up completely", function()
      add_yanks(2)
      assert.is_true(chips.toggle())
      assert.is_true(chips.is_open())
      assert.is_false(chips.toggle())
      assert.is_false(chips.is_open())
      assert.is_false(chips.wanted())
      local ok, found = pcall(vim.api.nvim_get_autocmds, { group = "ui_slots_bar" })
      assert.is_true(not ok or #found == 0)
      assert.is_true(chips.toggle())
      assert.is_true(chips.is_open())
    end)

    it("open twice does not stack windows or autocommands", function()
      add_yanks(1)
      chips.open()
      local win = chips.state().win
      local count = #vim.api.nvim_get_autocmds({ group = "ui_slots_bar" })
      chips.open()
      assert.equals(win, chips.state().win)
      assert.equals(count, #vim.api.nvim_get_autocmds({ group = "ui_slots_bar" }))
    end)

    it("is a command: :UI slots toggle|open|close", function()
      require("ui.bindings.usrcmds").setup()
      add_yanks(1)
      vim.cmd("UI slots open")
      assert.is_true(chips.is_open())
      vim.cmd("UI slots close")
      assert.is_false(chips.is_open())
      vim.cmd("UI slots toggle")
      assert.is_true(chips.is_open())
      vim.cmd("UI slots toggle")
      assert.is_false(chips.is_open())
    end)

    it("says that it waits for the first slot", function()
      require("ui.bindings.usrcmds").setup()
      vim.cmd("UI slots open")
      assert.is_truthy(table.concat(messages, "\n"):find("first slot", 1, true))
    end)

    it("opens by itself with show = true, and closes with disable()", function()
      start({ show = true })
      add_yanks(2)
      flush()
      assert.is_true(chips.is_open())
      slots.disable()
      assert.is_false(chips.is_open())
      assert.is_false(chips.wanted())
    end)

    it("stays open when setup() runs again in the middle of a session", function()
      add_yanks(2)
      chips.open()
      slots.setup({ data_dir = dir .. "/data", save_delay_ms = 0, style = "double" })
      flush()
      assert.is_true(chips.is_open())
      assert.is_truthy(lines()[1]:find("╔", 1, true))
    end)

    it("does not leave a window behind when the feature is disabled", function()
      add_yanks(1)
      chips.open()
      local win = chips.state().win
      slots.disable()
      assert.is_false(vim.api.nvim_win_is_valid(win))
    end)
  end)
end)
