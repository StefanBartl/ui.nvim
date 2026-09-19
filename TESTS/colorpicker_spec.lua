-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.colorpicker` -- the colour arithmetic, and the picker float driven
--- through its own window cursor.

local color = require("ui.colorpicker.color")
local picker = require("ui.colorpicker")

describe("ui.colorpicker.color", function()
  it("parses every accepted spelling and normalises to #rrggbb", function()
    assert.equals("#61afef", color.normalize("#61AFEF"))
    assert.equals("#61afef", color.normalize("61afef"))
    assert.equals("#ffaa00", color.normalize("#fa0"))
    assert.is_nil(color.normalize("#12345"))
    assert.is_nil(color.normalize("red"))
    assert.is_true(color.valid("#000"))
  end)

  it("round-trips hex -> hsl -> hex", function()
    for _, hex in ipairs({
      "#ff0000",
      "#00ff00",
      "#0000ff",
      "#61afef",
      "#123456",
      "#808080",
      "#ffffff",
      "#000000",
    }) do
      local h, s, l = color.hex_to_hsl(hex)
      assert.equals(hex, color.hsl_to_hex(h, s, l), hex)
    end
    local h, s, l = color.hex_to_hsl("#ff0000")
    assert.equals(0, h)
    assert.equals(100, s)
    assert.equals(50, l)
  end)

  it("shifts lightness and picks a readable text colour", function()
    assert.equals("#ffffff", color.shift_lightness("#808080", 60))
    assert.equals("#000000", color.shift_lightness("#808080", -60))
    assert.equals("#ffffff", color.contrast("#000000"))
    assert.equals("#000000", color.contrast("#ffffff"))
  end)

  it("finds the hex literal under a column", function()
    local line = "bg = #61afef, fg = #fff"
    local hex, s, e = color.hex_at(line, 7)
    assert.equals("#61afef", hex)
    assert.equals(5, s)
    assert.equals(12, e)
    assert.equals("#fff", (color.hex_at(line, 21)))
    assert.is_nil((color.hex_at(line, 2)))
    assert.is_nil((color.hex_at("#12345g", 3)))
  end)
end)

describe("ui.colorpicker", function()
  after_each(function()
    vim.cmd("silent! %bwipeout!")
  end)

  it("opens on the hex under the cursor and replaces it on <CR>", function()
    vim.cmd("new")
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "color = #ff0000" })
    vim.api.nvim_win_set_cursor(0, { 1, 10 })
    local surf = picker.open()
    assert.is_not_nil(surf)
    assert.equals(vim.api.nvim_get_current_win(), surf.winid)
    assert.equals("#ff0000", picker.current())
    -- The grid row/col the cursor landed on is the nearest to pure red.
    local lines = vim.api.nvim_buf_get_lines(surf.bufnr, 0, -1, false)
    assert.truthy(lines[#lines - 1]:find("#ff0000  rgb%(255, 0, 0%)"))
    -- Move to the hue row's first cell (hue 0 = red at full saturation).
    vim.api.nvim_win_set_cursor(surf.winid, { 1, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = surf.bufnr })
    assert.equals("#ff0000", picker.current())
    -- Two cells further along the hue row is hue 30.
    vim.api.nvim_win_set_cursor(surf.winid, { 1, 4 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = surf.bufnr })
    assert.equals(color.hsl_to_hex(30, 100, 50), picker.current())
    local chosen = picker.current()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert.is_nil(picker.current())
    assert.equals("color = " .. chosen, vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
  end)

  it("inserts at the cursor when nothing is under it, and yanks", function()
    vim.cmd("new")
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = ""
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "bg = " })
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    local surf = picker.open({ hex = "#123456" })
    assert.equals("#123456", picker.current())
    vim.api.nvim_feedkeys("y", "x", false)
    assert.equals("#123456", vim.fn.getreg('"'))
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert.equals("bg = #123456", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    assert.is_false(vim.api.nvim_win_is_valid(surf.winid))
  end)

  it("hands the pick to on_pick instead when given one", function()
    vim.cmd("new")
    local got
    picker.open({
      hex = "#abcdef",
      on_pick = function(hex)
        got = hex
      end,
    })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert.equals("#abcdef", got)
  end)

  it("closes on q and setup() takes tunables", function()
    vim.cmd("new")
    local surf = picker.open()
    vim.api.nvim_feedkeys("q", "x", false)
    assert.is_false(vim.api.nvim_win_is_valid(surf.winid))
    picker.setup({ hues = 12 })
    assert.equals(12, picker.config().hues)
    picker.setup({ hues = 24 })
  end)
end)
