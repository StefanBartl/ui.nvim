-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.layout` (column -> key hit-testing), `ui.statusline.hover`
--- (the `<MouseMove>` tooltip + fg recolor) and `ui.statusline.menu` (the
--- right/double-click "manage this module" menu) -- the three new pieces
--- behind the statusline hover popup and add/remove menu. `render.lua`'s own
--- side of the wiring (generic click wrap, hover recolor at redraw time) is
--- covered in `statusline_render_spec.lua`/`statusline_clickable_spec.lua`;
--- this file is the three modules on their own.

describe("ui.statusline.layout", function()
  local layout = require("ui.statusline.layout")

  it("returns nil before anything has been recorded for a winid", function()
    assert.is_nil(layout.key_at(999999, 1))
  end)

  it("finds the key at a column with no '%=' involved", function()
    local winid = vim.api.nvim_get_current_win()
    layout.record(winid, { "a", "b" }, { a = "AA", b = "BBB" })

    -- "AA" occupies columns 1-2, "BBB" columns 3-5.
    assert.equals("a", layout.key_at(winid, 1, 10))
    assert.equals("a", layout.key_at(winid, 2, 10))
    assert.equals("b", layout.key_at(winid, 3, 10))
    assert.equals("b", layout.key_at(winid, 5, 10))
  end)

  it("returns nil for a column past the end of the row", function()
    local winid = vim.api.nvim_get_current_win()
    layout.record(winid, { "a" }, { a = "AA" })

    assert.is_nil(layout.key_at(winid, 3, 10))
  end)

  it("resolves columns on both sides of a '%=' gap, and nil inside the gap", function()
    local winid = vim.api.nvim_get_current_win()
    -- Evaluated against a fixed maxwidth of 20: "left" (4 cols) then padding
    -- then "right" (5 cols) flush to column 20.
    layout.record(winid, { "left", "%=", "right" }, { left = "left", right = "right" })

    assert.equals("left", layout.key_at(winid, 1, 20))
    assert.equals("left", layout.key_at(winid, 4, 20))
    assert.is_nil(layout.key_at(winid, 10, 20)) -- inside the expanded gap
    assert.equals("right", layout.key_at(winid, 16, 20))
    assert.equals("right", layout.key_at(winid, 20, 20))
  end)

  it("skips a key that rendered empty -- no screen cells belong to it", function()
    local winid = vim.api.nvim_get_current_win()
    layout.record(winid, { "a", "empty", "b" }, { a = "A", empty = "", b = "B" })

    -- "A" at column 1, "B" at column 2 -- "empty" contributes nothing between them.
    assert.equals("a", layout.key_at(winid, 1, 10))
    assert.equals("b", layout.key_at(winid, 2, 10))
  end)

  it("keeps separate windows' layouts independent", function()
    -- `nvim_eval_statusline` needs a real window for context, so this uses
    -- an actual split rather than two made-up winids.
    local win_a = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local win_b = vim.api.nvim_get_current_win()

    layout.record(win_a, { "a" }, { a = "A" })
    layout.record(win_b, { "b" }, { b = "B" })

    local found_a = layout.key_at(win_a, 1, 10)
    local found_b = layout.key_at(win_b, 1, 10)

    pcall(vim.api.nvim_win_close, win_b, true)

    assert.equals("a", found_a)
    assert.equals("b", found_b)
  end)

  it(
    "survives a click-region-wrapped rendered string -- markers ignore it, widths stay right",
    function()
      local winid = vim.api.nvim_get_current_win()
      layout.record(winid, { "a", "b" }, {
        a = "%12@UiSlClick@AA%X",
        b = "%13@UiSlClick@BB%X",
      })

      assert.equals("a", layout.key_at(winid, 1, 10))
      assert.equals("a", layout.key_at(winid, 2, 10))
      assert.equals("b", layout.key_at(winid, 3, 10))
      assert.equals("b", layout.key_at(winid, 4, 10))
    end
  )
end)

describe("ui.statusline.hover", function()
  local hover = require("ui.statusline.hover")

  after_each(function()
    hover.disable()
  end)

  it("current_key() is nil before anything is hovered", function()
    assert.is_nil(hover.current_key())
  end)

  it("enable() is idempotent and degrades silently without throwing", function()
    assert.has_no.errors(function()
      hover.enable()
      hover.enable()
    end)
  end)

  it("disable() is safe to call before enable()", function()
    assert.has_no.errors(function()
      hover.disable()
    end)
  end)

  it("pointer_target() returns nil when getmousepos() is not over a statusline row", function()
    local original = vim.fn.getmousepos
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getmousepos = function()
      return {
        winid = vim.api.nvim_get_current_win(),
        line = 5,
        wincol = 3,
        winrow = 2,
        screenrow = 5,
        screencol = 3,
      }
    end

    local target = hover.pointer_target()

    vim.fn.getmousepos = original
    assert.is_nil(target)
  end)

  it(
    "pointer_target() resolves a per-window statusline row (line == 0, winrow == height + 1)",
    function()
      local winid = vim.api.nvim_get_current_win()
      local height = vim.api.nvim_win_get_height(winid)

      local original = vim.fn.getmousepos
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.getmousepos = function()
        return {
          winid = winid,
          line = 0,
          wincol = 7,
          winrow = height + 1,
          screenrow = 99,
          screencol = 12,
        }
      end

      local target = hover.pointer_target()

      vim.fn.getmousepos = original
      assert.is_not_nil(target)
      assert.equals(winid, target.winid)
      assert.equals(7, target.col)
      assert.is_nil(target.maxwidth)
    end
  )
end)

describe("ui.statusline.menu", function()
  local menu = require("ui.statusline.menu")
  local render = require("ui.statusline.render")
  local catalog = require("ui.statusline.catalog")

  ---@type string
  local extra_key
  before_each(function()
    -- A catalog key that is not in any shipped preset's default `order`, so
    -- add/remove has something to actually toggle without disturbing a real
    -- module's state.
    for _, entry in ipairs(catalog) do
      if #entry.used_by == 0 then
        extra_key = entry.key
        break
      end
    end
    assert.is_not_nil(
      extra_key,
      "fixture assumption: at least one opt-in-only catalog entry exists"
    )

    render.enable({ order = { "mode" }, modules = {} })
  end)

  after_each(function()
    render.disable()
  end)

  it("items() offers 'Remove' only for a key currently in order", function()
    local items = menu.items("mode")
    local labels = {}
    for _, item in ipairs(items) do
      labels[#labels + 1] = item.name
    end
    assert.is_true(vim.tbl_contains(labels, "Remove mode"))
  end)

  it("items() does not offer 'Remove' for a key not in order", function()
    local items = menu.items(extra_key)
    local labels = {}
    for _, item in ipairs(items) do
      labels[#labels + 1] = item.name
    end
    assert.is_false(vim.tbl_contains(labels, "Remove " .. extra_key))
  end)

  it("add_module (via the 'Add module' submenu) appends the key to the live order", function()
    local items = menu.items("mode")
    local add_submenu = nil
    for _, item in ipairs(items) do
      if item.name == "Add module" then
        add_submenu = item
      end
    end
    assert.is_not_nil(add_submenu)

    local entry = nil
    for _, sub in ipairs(add_submenu.items) do
      if sub.name:find(extra_key, 1, true) == 1 then
        entry = sub
      end
    end
    assert.is_not_nil(entry, ("no 'Add module' entry for %q"):format(extra_key))

    entry.cmd()

    assert.is_true(vim.tbl_contains(render.current().order, extra_key))
  end)

  it("remove (via 'Remove <key>') drops the key from the live order", function()
    local cfg = render.current()
    cfg.order[#cfg.order + 1] = extra_key
    -- A standalone catalog entry needs a real module or generate() warns;
    -- irrelevant to this test (only `order` membership is asserted), so a
    -- trivial stub is enough.
    cfg.modules[extra_key] = function()
      return ""
    end

    local items = menu.items(extra_key)
    local remove_entry = nil
    for _, item in ipairs(items) do
      if item.name == "Remove " .. extra_key then
        remove_entry = item
      end
    end
    assert.is_not_nil(remove_entry)

    remove_entry.cmd()

    assert.is_false(vim.tbl_contains(render.current().order, extra_key))
  end)

  it("open() draws through ui.contextmenu", function()
    local contextmenu = require("ui.contextmenu")
    local original_open = contextmenu.open
    local opened_with = nil
    ---@diagnostic disable-next-line: duplicate-set-field
    contextmenu.open = function(items)
      opened_with = items
    end

    menu.open("mode")
    contextmenu.open = original_open

    assert.equals("table", type(opened_with))
    assert.is_true(#opened_with > 0)
  end)

  it("pointer_on_statusline() reflects ui.statusline.hover.pointer_target()", function()
    local hover = require("ui.statusline.hover")
    local original = hover.pointer_target
    ---@diagnostic disable-next-line: duplicate-set-field
    hover.pointer_target = function()
      return { winid = 1, col = 1, maxwidth = nil, screenrow = 1, screencol = 1 }
    end

    local result = menu.pointer_on_statusline()

    hover.pointer_target = original
    assert.is_true(result)
  end)
end)
