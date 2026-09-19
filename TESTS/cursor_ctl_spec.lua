-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- ui.statusline.cursor_ctl -- get_mode()/set_mode()/toggle_mode(). Covers
--- the PRIN-10 fix: `mode` used to be a public field sitting right beside
--- set_mode()'s five-name whitelist, so a direct `cursor_ctl.mode = ...`
--- assignment bypassed validation entirely.

local cursor_ctl = require("ui.statusline.cursor_ctl")

describe("ui.statusline.cursor_ctl", function()
  after_each(function()
    cursor_ctl.set_mode("row_progress") -- restore the shipped default
  end)

  it("set_mode() accepts a known mode", function()
    cursor_ctl.set_mode("classic")
    assert.equals("classic", cursor_ctl.get_mode())
  end)

  it("set_mode() is a no-op on an unknown mode", function()
    cursor_ctl.set_mode("col_progress")
    cursor_ctl.set_mode("not-a-real-mode")
    assert.equals("col_progress", cursor_ctl.get_mode())
  end)

  it("assigning a `mode` field on the returned module does not change get_mode()", function()
    -- The module's own state lives module-internally now; a stray field
    -- written onto the returned table is inert.
    cursor_ctl.set_mode("off")
    ---@diagnostic disable-next-line: inject-field
    cursor_ctl.mode = "classic"
    assert.equals("off", cursor_ctl.get_mode())
  end)

  it("toggle_mode() cycles through the stable order and wraps", function()
    cursor_ctl.set_mode("off")
    local order = { "classic", "row_progress", "col_progress", "rows_cols_progress", "off" }
    for _, expected in ipairs(order) do
      assert.equals(expected, cursor_ctl.toggle_mode())
    end
  end)
end)
