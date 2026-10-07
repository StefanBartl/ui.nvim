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
    -- One turn of the loop first (a click's action is scheduled), then until the
    -- redraw an event asked for has run.
    vim.wait(20, function()
      return false
    end)
    vim.wait(2000, function()
      return not chips._pending()
    end, 2)
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

  --- A `getmousepos()` for the screen cell of line `line` of the bar. The bar is
  --- not focusable, so `winid` names the window under it, as in a real session.
  ---@param line integer
  ---@return table
  local function pointer(line)
    local at = vim.api.nvim_win_get_position(chips.state().win)
    return {
      winid = vim.api.nvim_get_current_win(),
      line = 1,
      screenrow = at[1] + line,
      screencol = at[2] + 3,
    }
  end

  --- Run `fn` with the pointer stubbed to `pos`.
  ---@param pos table
  ---@param fn fun(): any
  ---@return any
  local function with_pointer(pos, fn)
    local original = vim.fn.getmousepos
    vim.fn.getmousepos = function()
      return pos
    end
    local ok, res = pcall(fn)
    vim.fn.getmousepos = original
    assert(ok, res)
    return res
  end

  --- Deliver mouse key `name` at line `line` of the bar; returns what the
  --- listener answered ("" = the key was taken, nil = left alone).
  ---@param name string
  ---@param line integer
  ---@return string|nil
  local function key_at(name, line)
    local res = with_pointer(pointer(line), function()
      return chips._on_key("", vim.api.nvim_replace_termcodes(name, true, true, true))
    end)
    flush()
    return res
  end

  --- Click `key` at line `line` of the bar.
  ---@param key string
  ---@param line integer
  local function click(key, line)
    key_at(key, line)
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    messages = {}
    original_notify = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    saved = {
      lines = vim.o.lines,
      columns = vim.o.columns,
      cmdheight = vim.o.cmdheight,
      laststatus = vim.o.laststatus,
      showtabline = vim.o.showtabline,
      ambiwidth = vim.o.ambiwidth,
      normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false }),
      normal_float = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }),
    }
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
    vim.o.cmdheight, vim.o.laststatus = saved.cmdheight, saved.laststatus
    vim.o.showtabline, vim.o.ambiwidth = saved.showtabline, saved.ambiwidth
    vim.api.nvim_set_hl(0, "Normal", saved.normal)
    vim.api.nvim_set_hl(0, "NormalFloat", saved.normal_float)
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
    local path

    before_each(function()
      path = require("lib.nvim.fs.normkey")((function()
        local p = dir .. "/a.txt"
        vim.fn.writefile({ "one", "two" }, p)
        return p
      end)())
      slots.add({ kind = "file", path = path })
      slots.add({ kind = "yank", text = "copy me" })
      chips.open()
    end)

    it("is not focusable: the window cycle and :windo never meet it", function()
      local cfg = vim.api.nvim_win_get_config(chips.state().win)
      assert.is_false(cfg.focusable)
    end)

    it("applies the slot under a left click, takes the key and moves no focus", function()
      vim.cmd("enew")
      local win = vim.api.nvim_get_current_win()
      local answer = key_at("<LeftMouse>", 2)
      assert.equals("", answer)
      assert.equals(win, vim.api.nvim_get_current_win())
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

    it("counts a fast second click (<2-LeftMouse>) as a click again", function()
      config.get().clipboard = { "a" }
      vim.fn.setreg("a", "")
      click("<2-LeftMouse>", 5)
      assert.equals("copy me", vim.fn.getreg("a"))
    end)

    it("takes a modified click without acting on it", function()
      config.get().clipboard = { "a" }
      vim.fn.setreg("a", "")
      assert.equals("", key_at("<C-LeftMouse>", 5))
      assert.equals("", vim.fn.getreg("a"))
    end)

    it("takes the drag and the release of a press that began on the bar", function()
      assert.equals("", key_at("<LeftMouse>", 2))
      assert.equals("", key_at("<LeftDrag>", 5))
      assert.equals("", key_at("<LeftRelease>", 5))
      -- and a release with no press behind it belongs to whoever wants it
      assert.is_nil(key_at("<LeftRelease>", 5))
    end)

    it("leaves a drag alone that began in the editor", function()
      assert.is_nil(key_at("<LeftDrag>", 5))
      assert.is_nil(key_at("<LeftRelease>", 5))
    end)

    it("ignores a click that is not on the bar", function()
      vim.cmd("enew")
      local answer = with_pointer(
        { winid = vim.api.nvim_get_current_win(), line = 1, screenrow = 2, screencol = 1 },
        function()
          return chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
        end
      )
      flush()
      assert.is_nil(answer)
      assert.equals("", vim.api.nvim_buf_get_name(0))
    end)

    it("ignores keys that are no mouse keys, and a cell past the last row", function()
      assert.is_nil(chips._on_key("j", "j"))
      local at = vim.api.nvim_win_get_position(chips.state().win)
      local answer = with_pointer(
        { winid = 1000, line = 1, screenrow = at[1] + 99, screencol = at[2] + 2 },
        function()
          return chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
        end
      )
      assert.is_nil(answer)
    end)

    it("leaves a click to a float that is stacked above the bar", function()
      config.get().clipboard = { "a" }
      vim.fn.setreg("a", "")
      local over = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
        relative = "editor",
        row = 0,
        col = vim.o.columns - 12,
        width = 12,
        height = 8,
        zindex = 60,
      })
      local pos = pointer(5)
      pos.winid = over
      local answer = with_pointer(pos, function()
        return chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
      end)
      flush()
      pcall(vim.api.nvim_win_close, over, true)
      assert.is_nil(answer)
      assert.equals("", vim.fn.getreg("a"))
    end)

    it("takes the side buttons of the mouse away from the code below, too", function()
      assert.equals("", key_at("<X1Mouse>", 2))
      assert.equals("", key_at("<X1Drag>", 2))
      assert.equals("", key_at("<X1Release>", 2))
      assert.equals("", key_at("<X2Mouse>", 2))
      assert.equals("", key_at("<X2Release>", 2))
    end)

    it("forgets a press that never got its release as soon as another press comes", function()
      assert.equals("", key_at("<LeftMouse>", 2))
      -- the bar is gone before the release; the next press is in the editor
      with_pointer(
        { winid = vim.api.nvim_get_current_win(), line = 1, screenrow = 1, screencol = 1 },
        function()
          assert.is_nil(
            chips._on_key("", vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true))
          )
          assert.is_nil(
            chips._on_key("", vim.api.nvim_replace_termcodes("<LeftDrag>", true, true, true))
          )
          assert.is_nil(
            chips._on_key("", vim.api.nvim_replace_termcodes("<LeftRelease>", true, true, true))
          )
        end
      )
    end)

    it("takes the middle click and the sideways wheel away from the code below", function()
      assert.equals("", key_at("<MiddleMouse>", 2))
      assert.equals("", key_at("<ScrollWheelLeft>", 2))
      assert.equals("", key_at("<ScrollWheelRight>", 2))
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
      assert.same({ "Apply", "Edit", "Copy", "Clear" }, names)
      seen.on_select(seen.items[4])
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

    it("scrolls by one on a click on a counter, also on a fast second click", function()
      vim.o.lines = 14
      slots.clear_all()
      add_yanks(10)
      chips.set_focus(1)
      flush()
      click("<LeftMouse>", #lines())
      assert.equals(2, chips.state().top_n)
      -- the counters moved with the redraw: the down counter is the last row again
      click("<2-LeftMouse>", #lines())
      assert.equals(3, chips.state().top_n)
      click("<LeftMouse>", 1)
      assert.equals(2, chips.state().top_n)
    end)

    it("tells ui.menu that the pointer is on the bar, by the screen cell", function()
      local menu = require("ui.menu")
      local opened = false
      local original_open = menu.open
      menu.open = function()
        opened = true
      end
      with_pointer(pointer(2), function()
        assert.is_true(chips.pointer_on_bar())
        menu.on_right_click()
      end)
      menu.open = original_open
      assert.is_false(opened)
      with_pointer(
        { winid = vim.api.nvim_get_current_win(), line = 1, screenrow = 1, screencol = 1 },
        function()
          assert.is_false(chips.pointer_on_bar())
        end
      )
    end)
  end)

  describe("what a slot may look like", function()
    it("survives a label with a newline, a NUL or a tab, and a label that is no string", function()
      store.set(1, { kind = "yank", text = "x", label = "two\nlines" })
      store.set(2, { kind = "yank", text = "x", label = "a\0b" })
      store.set(3, { kind = "yank", text = "x", label = "a\tb", icon = "i\nj" })
      store.set(4, { kind = "yank", text = "x", label = { "table" } })
      chips.open()
      flush()
      local st = chips.state()
      assert.is_not_nil(st.win)
      local width = vim.api.nvim_win_get_width(st.win)
      for _, l in ipairs(st.lines) do
        assert.is_nil(l:find("[%c]"))
        assert.equals(width, vim.fn.strdisplaywidth(l))
      end
      assert.is_false(vim.bo[st.buf].modifiable)
    end)

    it("leaves the buffer read-only and says so once if a line is refused anyway", function()
      add_yanks(1)
      chips.open()
      local st = chips.state()
      local original = vim.api.nvim_buf_set_lines
      vim.api.nvim_buf_set_lines = function(buf, ...)
        if buf == st.buf then
          error("refused")
        end
        return original(buf, ...)
      end
      chips.refresh()
      chips.refresh()
      vim.api.nvim_buf_set_lines = original
      assert.is_false(vim.bo[st.buf].modifiable)
      local told = vim.tbl_filter(function(m)
        return m:find("could not be drawn", 1, true) ~= nil
      end, messages)
      assert.equals(1, #told)
    end)
  end)

  describe("editors of unusual size and setup", function()
    it("shows the slot itself, not its borders, when only a row or two are free", function()
      vim.o.lines, vim.o.cmdheight, vim.o.laststatus = 5, 3, 0
      add_yanks(5)
      chips.open()
      chips.set_focus(3)
      flush()
      local st = chips.state()
      assert.is_not_nil(st.win)
      assert.is_true(vim.api.nvim_win_get_height(st.win) <= 2)
      assert.is_truthy(table.concat(st.lines, "\n"):find("slot 3", 1, true))
      vim.o.cmdheight, vim.o.laststatus = 1, 1
    end)

    it("draws a border of the right width when box characters are two cells wide", function()
      local original = vim.o.ambiwidth
      vim.o.ambiwidth = "double"
      add_yanks(2)
      chips.open()
      local width = vim.api.nvim_win_get_width(chips.state().win)
      for _, l in ipairs(lines()) do
        assert.equals(width, vim.fn.strdisplaywidth(l), l)
      end
      vim.o.ambiwidth = original
    end)

    it("has the Kit colours ready before the first solid chip is built", function()
      pcall(vim.api.nvim_set_hl, 0, "KitAccent", {})
      start({ style = "solid" })
      add_yanks(1)
      chips.open()
      local g = vim.api.nvim_get_hl(0, { name = "UiSlotsSolid_KitMuted", link = false })
      local v = vim.api.nvim_get_hl(0, { name = "UiSlotsSolid_KitAccent", link = false })
      assert.is_true(g.bg ~= nil or g.reverse == true)
      assert.is_true(v.bg ~= nil or v.reverse == true or next(v) == nil)
    end)

    it("keeps the border straight with odd widths and two-cell box characters", function()
      vim.o.ambiwidth = "double"
      start({ width = 17 })
      slots.add({ kind = "yank", text = "abcdefghijk" })
      slots.add({ kind = "yank", text = "abcdefghijkl" })
      chips.open()
      local width = vim.api.nvim_win_get_width(chips.state().win)
      for _, l in ipairs(lines()) do
        assert.equals(width, vim.fn.strdisplaywidth(l), l)
      end
      assert.equals(0, (width - 2 * vim.fn.strdisplaywidth("╭")) % vim.fn.strdisplaywidth("─"))
    end)

    it("warns once on a Neovim that cannot discard a key", function()
      local original = chips._discard_supported
      chips._discard_supported = function()
        return false
      end
      add_yanks(1)
      chips.open()
      chips.close()
      chips.open()
      chips._discard_supported = original
      local told = vim.tbl_filter(function(m)
        return m:find("0.10 cannot take a click", 1, true) ~= nil
      end, messages)
      assert.equals(1, #told)
    end)

    it("draws a solid chip even when the editor has no background colour", function()
      vim.api.nvim_set_hl(0, "Normal", {})
      vim.api.nvim_set_hl(0, "NormalFloat", {})
      start({ style = "solid" })
      add_yanks(1)
      chips.open()
      local hl = vim.api.nvim_get_hl(0, { name = "UiSlotsSolid_KitMuted", link = false })
      local accent = vim.api.nvim_get_hl(0, { name = "UiSlotsSolid_KitAccent", link = false })
      assert.is_true(hl.reverse == true or hl.bg ~= nil or next(accent) ~= nil)
    end)

    it("follows a change of the command-line height and of the tab line", function()
      -- The runner's child is still starting up, and Neovim sends no OptionSet then:
      -- the event is sent by hand. (Outside the runner `:set cmdheight=4` sends it.)
      local function set(name, value)
        vim.o[name] = value
        vim.api.nvim_exec_autocmds("OptionSet", { pattern = name })
        flush()
      end
      vim.o.lines = 14
      add_yanks(10)
      chips.open()
      local before = #lines()
      set("cmdheight", 4)
      assert.is_true(#lines() < before)
      set("cmdheight", 1)
      assert.equals(before, #lines())
      set("showtabline", 2)
      assert.equals(1, vim.api.nvim_win_get_config(chips.state().win).row)
      set("showtabline", 1)
    end)

    it("learns the file of a relative path anew after :cd", function()
      start({ scope = "global" })
      local a, b = dir .. "/da", dir .. "/db"
      vim.fn.mkdir(a, "p")
      vim.fn.mkdir(b, "p")
      vim.fn.writefile({ "a" }, a .. "/f.txt")
      vim.fn.writefile({ "b" }, b .. "/f.txt")
      local old = vim.fn.getcwd()
      vim.cmd.cd(a)
      slots.add({ kind = "file", path = "f.txt" })
      vim.cmd.edit(a .. "/f.txt")
      chips.open()
      assert.is_truthy(lines()[2]:find("•", 1, true))
      vim.cmd.cd(b)
      vim.cmd.edit(b .. "/f.txt")
      flush()
      assert.is_truthy(lines()[2]:find("•", 1, true))
      vim.cmd.cd(old)
    end)

    it("comes back when its window is closed from outside", function()
      add_yanks(2)
      chips.open()
      local win = chips.state().win
      vim.api.nvim_win_close(win, true)
      flush()
      assert.is_not_nil(chips.state().win)
      assert.is_not.equals(win, chips.state().win)
    end)

    it("survives a colour scheme change", function()
      add_yanks(2)
      chips.open()
      vim.api.nvim_exec_autocmds("ColorScheme", {})
      flush()
      assert.is_not_nil(chips.state().win)
    end)
  end)

  describe("a long list", function()
    it("asks the file system only about the chips that are drawn", function()
      start()
      for i = 1, 500 do
        store.add({ kind = "file", path = dir .. "/gone/file" .. i .. ".txt" })
      end
      local uv = vim.uv or vim.loop
      local original = uv.fs_stat
      local stats = 0
      uv.fs_stat = function(path)
        if tostring(path):find("/gone/", 1, true) then
          stats = stats + 1
        end
        return original(path)
      end
      chips.open()
      flush()
      uv.fs_stat = original
      -- the chips in view are the real thing: the file is not there
      assert.is_truthy(text():find("✗", 1, true))
      -- 30 rows of editor: a few chips, not five hundred
      assert.is_true(stats < 40, "stat'ed " .. stats .. " files for the first draw")
    end)

    it("scrolls to a chip far down and draws that one in full", function()
      start()
      for i = 1, 300 do
        store.add({ kind = "file", path = dir .. "/gone/file" .. i .. ".txt" })
      end
      chips.open()
      flush()
      chips.set_focus(250)
      flush()
      assert.is_truthy(text():find("file250.txt", 1, true))
      assert.is_truthy(text():find("✗", 1, true))
    end)
  end)

  describe("focus", function()
    it("never lets the bar into the window cycle", function()
      add_yanks(2)
      chips.open()
      vim.cmd.vsplit()
      local bar = chips.state().win
      for _ = 1, 6 do
        vim.cmd.wincmd("w")
        assert.is_not.equals(bar, vim.api.nvim_get_current_win())
      end
      vim.cmd("only")
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

    it("the first :UI slots toggle with show = true leaves the bar open, not shut", function()
      require("ui.bindings.usrcmds").setup()
      slots.reset()
      store.reset()
      chips.reset()
      slots.setup({ data_dir = dir .. "/data", save_delay_ms = 0, show = true })
      assert.is_false(slots.is_enabled())
      slots.add({ kind = "yank", text = "x" })
      slots.disable()
      chips.reset()
      vim.cmd("UI slots toggle")
      flush()
      assert.is_true(chips.wanted())
      assert.is_true(chips.is_open())
      vim.cmd("UI slots toggle")
      assert.is_false(chips.wanted())
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
