-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, duplicate-set-field

--- `ui.tabline.layout` (which chip is under a screen column) and
--- `ui.tabline.drag` (press a chip, carry it along the bar) -- the parts of
--- reordering tabs by mouse that cannot come from a tabline click handler.
---
--- A drag is driven here by calling the mapped callbacks directly with
--- `vim.fn.getmousepos` stubbed: a headless suite has no main loop consuming
--- typed mouse input while a spec runs. The real gesture -- actual
--- `nvim_input_mouse` press/drag/release against the real tabline -- was run
--- separately against an event loop; see the notes in the commit.

local layout = require("ui.tabline.layout")
local drag = require("ui.tabline.drag")
local state = require("ui.bindings.keymaps.tabufline.state")

describe("ui.tabline.layout.slot_at", function()
  -- Plain text chips: `nvim_eval_statusline` measures them as their length.
  it("finds the chip a column falls on", function()
    layout.record("", { 10, 11, 12 }, { "aaaa", "bbbbbb", "cc" })
    local buf, slot = layout.slot_at(1)
    assert.equals(10, buf)
    assert.equals(1, slot)
    assert.equals(10, (layout.slot_at(4)))
    assert.equals(11, (layout.slot_at(5)))
    assert.equals(11, (layout.slot_at(10)))
    assert.equals(12, (layout.slot_at(11)))
    assert.equals(12, (layout.slot_at(12)))
  end)

  it("counts the text left of the first chip (the tree offset)", function()
    layout.record("    ", { 10, 11 }, { "aaaa", "bbbb" })
    assert.equals(10, (layout.slot_at(2))) -- inside the offset: clamps to the first chip
    assert.equals(10, (layout.slot_at(5))) -- first column of chip 1
    assert.equals(11, (layout.slot_at(9))) -- first column of chip 2
  end)

  it("clamps a column past the last chip to the last chip", function()
    layout.record("", { 10, 11 }, { "aaaa", "bbbb" })
    local buf, slot = layout.slot_at(500)
    assert.equals(11, buf)
    assert.equals(2, slot)
  end)

  it("clamps a column left of everything to the first chip", function()
    layout.record("", { 10, 11 }, { "aaaa", "bbbb" })
    assert.equals(10, (layout.slot_at(0)))
    assert.equals(10, (layout.slot_at(-3)))
  end)

  it("does not count %-directives as width", function()
    layout.record("", { 10, 11 }, { "%#UiTbBufOn#%5@UiTbGoToBuf@ab%X", "cd" })
    assert.equals(10, (layout.slot_at(2)))
    assert.equals(11, (layout.slot_at(3)))
  end)

  it("answers nil, nil when nothing is on the bar", function()
    layout.record("", {}, {})
    local buf, slot = layout.slot_at(3)
    assert.is_nil(buf)
    assert.is_nil(slot)
  end)

  it("is fed by ui.tabline.modules.buffers", function()
    local render = require("ui.tabline.render")
    state.setup()
    vim.cmd("tabnew")
    local a = vim.api.nvim_create_buf(true, false)
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(a, "layout-spec-a.txt")
    vim.api.nvim_buf_set_name(b, "layout-spec-b.txt")
    vim.api.nvim_set_current_buf(a)
    vim.t.bufs = { a, b }

    layout.record("", {}, {}) -- drop whatever an earlier render left behind
    render.generate({ order = { "buffers" }, modules = {} })

    local recorded = layout.current()
    assert.same({ a, b }, recorded.bufs)
    assert.equals(#recorded.bufs, #recorded.chips)

    pcall(vim.api.nvim_buf_delete, a, { force = true })
    pcall(vim.api.nvim_buf_delete, b, { force = true })
    pcall(vim.cmd, "tabclose")
  end)

  it("records the text of the modules left of 'buffers' as the prefix", function()
    local render = require("ui.tabline.render")
    vim.cmd("tabnew")
    vim.t.bufs = { vim.api.nvim_get_current_buf() }

    render.generate({
      order = { "lead", "buffers", "trail" },
      modules = {
        lead = function()
          return "LEAD"
        end,
        trail = function()
          return "TRAIL"
        end,
      },
    })

    assert.equals("LEAD", layout.current().prefix)
    pcall(vim.cmd, "tabclose")
  end)
end)

describe("ui.tabline.drag", function()
  local a, b, c
  local real_getmousepos = vim.fn.getmousepos

  --- Point the fake mouse at `col` on `row` (row 1 is the tabline).
  ---@param col integer
  ---@param row? integer
  local function pointer_at(col, row)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getmousepos = function()
      return { screenrow = row or 1, screencol = col }
    end
  end

  --- What the drag mapping for `lhs` would run, as a plain function.
  ---@param lhs string
  ---@return function
  local function mapped(lhs)
    local map = vim.fn.maparg(lhs, "n", false, true)
    assert.is_function(map.callback, lhs .. " is not mapped")
    return map.callback
  end

  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    a = vim.api.nvim_create_buf(true, false)
    b = vim.api.nvim_create_buf(true, false)
    c = vim.api.nvim_create_buf(true, false)
    vim.t.bufs = { a, b, c }
    -- Three 10-column chips: a = 1-10, b = 11-20, c = 21-30.
    layout.record("", { a, b, c }, { ("a"):rep(10), ("b"):rep(10), ("c"):rep(10) })
  end)

  after_each(function()
    drag.cancel()
    vim.fn.getmousepos = real_getmousepos
    for _, buf in ipairs({ a, b, c }) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    pcall(vim.cmd, "tabclose")
  end)

  it("claims <LeftDrag> and <LeftRelease> only for the length of a gesture", function()
    assert.equals("", vim.fn.maparg("<LeftDrag>", "n"))
    assert.is_false(drag.is_active())

    drag.begin(a)
    assert.is_true(drag.is_active())
    assert.equals(a, drag.dragged())
    assert.is_not.equals("", vim.fn.maparg("<LeftDrag>", "n"))
    assert.is_not.equals("", vim.fn.maparg("<LeftRelease>", "n"))

    drag.cancel()
    assert.is_false(drag.is_active())
    assert.equals("", vim.fn.maparg("<LeftDrag>", "n"))
    assert.equals("", vim.fn.maparg("<LeftRelease>", "n"))
  end)

  it("claims the keys in every mode a chip can be pressed from", function()
    drag.begin(a)
    for _, mode in ipairs({ "n", "i", "v", "t" }) do
      assert.is_not.equals("", vim.fn.maparg("<LeftDrag>", mode), mode)
    end
  end)

  it("moves the dragged buffer into the slot under the pointer", function()
    drag.begin(a)
    pointer_at(15) -- over b
    mapped("<LeftDrag>")()
    assert.same({ b, a, c }, vim.t.bufs)
  end)

  it("carries the buffer along a multi-step drag, re-reading the layout each time", function()
    drag.begin(a)

    pointer_at(15)
    mapped("<LeftDrag>")()
    assert.same({ b, a, c }, vim.t.bufs)

    -- What a real redraw would have recorded after that move.
    layout.record("", { b, a, c }, { ("b"):rep(10), ("a"):rep(10), ("c"):rep(10) })
    pointer_at(25) -- over c
    mapped("<LeftDrag>")()
    assert.same({ b, c, a }, vim.t.bufs)
  end)

  it("is a no-op while the pointer is still over the dragged chip", function()
    drag.begin(a)
    pointer_at(5)
    mapped("<LeftDrag>")()
    assert.same({ a, b, c }, vim.t.bufs)
  end)

  it("ignores a pointer that has left the tabline row", function()
    drag.begin(a)
    pointer_at(25, 6)
    mapped("<LeftDrag>")()
    assert.same({ a, b, c }, vim.t.bufs)
    assert.is_true(drag.is_active()) -- still alive: dragging back up carries on
  end)

  it("treats an overshoot past the last chip as 'to the end'", function()
    drag.begin(a)
    pointer_at(200)
    mapped("<LeftDrag>")()
    assert.same({ b, c, a }, vim.t.bufs)
  end)

  it("ends on release and unmaps", function()
    drag.begin(a)
    mapped("<LeftRelease>")()
    assert.is_false(drag.is_active())
    assert.equals("", vim.fn.maparg("<LeftDrag>", "n"))
  end)

  it("puts back a global mapping it shadowed", function()
    vim.keymap.set("n", "<LeftDrag>", function() end, { desc = "drag-spec: previous owner" })

    drag.begin(a)
    assert.is_not.equals(
      "drag-spec: previous owner",
      vim.fn.maparg("<LeftDrag>", "n", false, true).desc
    )

    drag.cancel()
    assert.equals("drag-spec: previous owner", vim.fn.maparg("<LeftDrag>", "n", false, true).desc)
    vim.keymap.del("n", "<LeftDrag>")
  end)

  it("a second begin() replaces a gesture whose release was lost", function()
    drag.begin(a)
    drag.begin(b)
    assert.equals(b, drag.dragged())
    drag.cancel()
    assert.equals("", vim.fn.maparg("<LeftDrag>", "n"))
  end)

  it("cancel() with no gesture running does nothing", function()
    assert.has_no.errors(function()
      drag.cancel()
      drag.cancel()
    end)
  end)

  it("a drag event after the gesture ended does not throw", function()
    drag.begin(a)
    local on_drag = mapped("<LeftDrag>")
    drag.cancel()
    pointer_at(15)
    assert.has_no.errors(on_drag)
    assert.same({ a, b, c }, vim.t.bufs)
  end)
end)
