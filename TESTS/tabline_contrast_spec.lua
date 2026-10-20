-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Tabline text contrast: the pure helpers in ui.theme.palette and what ui.tabline.highlights.apply() makes of a
--- colorscheme whose TabLine colors sit next to each other (inactive chips were blank).

describe("ui.theme.palette contrast", function()
  local palette = require("ui.theme.palette")

  it("measures the WCAG ratio", function()
    assert.is_true(math.abs(palette.contrast_ratio("#000000", "#ffffff") - 21) < 0.01)
    assert.is_true(math.abs(palette.contrast_ratio("#777777", "#777777") - 1) < 0.01)
  end)

  it("keeps a foreground that already reads", function()
    assert.equals("#ffffff", palette.ensure_contrast("#ffffff", "#000000", 4.5))
  end)

  it("lifts a foreground that sits next to the ground, on a dark ground", function()
    local fg = palette.ensure_contrast("#2a2a3a", "#26263a", 4.5)
    assert.is_true(palette.contrast_ratio(fg, "#26263a") >= 4.5)
  end)

  it("lowers it on a light ground", function()
    local fg = palette.ensure_contrast("#f0f0f8", "#f4f4fa", 4.5)
    assert.is_true(palette.contrast_ratio(fg, "#f4f4fa") >= 4.5)
  end)

  it("uses black or white when the foreground is missing", function()
    assert.equals("#ffffff", palette.ensure_contrast(nil, "#101010", 4.5))
    assert.equals("#000000", palette.ensure_contrast(nil, "#f0f0f0", 4.5))
  end)
end)

describe("ui.tabline.highlights contrast", function()
  local highlights = require("ui.tabline.highlights")
  local palette = require("ui.theme.palette")

  local function fg_bg(group)
    local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
    return string.format("#%06x", hl.fg), string.format("#%06x", hl.bg)
  end

  before_each(function()
    -- The scheme of the bug: TabLine text one step away from its ground on a violet chip.
    vim.api.nvim_set_hl(0, "TabLine", { fg = "#4a3f8a", bg = "#483d8b" })
    vim.api.nvim_set_hl(0, "TabLineFill", { bg = "#1a1b26" })
    vim.api.nvim_set_hl(0, "TabLineSel", { fg = "#c0caf5", bg = "#3b4261" })
    vim.api.nvim_set_hl(0, "Normal", { fg = "#c0caf5", bg = "#1a1b26" })
  end)

  it("makes the inactive chip text readable", function()
    highlights.apply()
    for _, group in ipairs({ "UiTbBufOff", "UiTbTabOff" }) do
      local fg, bg = fg_bg(group)
      assert.is_true(palette.contrast_ratio(fg, bg) >= 4.5, group)
    end
    local fg, bg = fg_bg("UiTbBufOffClose")
    assert.is_true(palette.contrast_ratio(fg, bg) >= 3, "close symbol")
    local tfg, tbg = fg_bg("UiTbTitle")
    assert.is_true(palette.contrast_ratio(tfg, tbg) >= 4.5, "title")
  end)

  it("takes the scheme as it is when min_contrast is false", function()
    local config = require("ui.config")
    local saved = config.__save_state()
    config.setup({ tabline = { min_contrast = false } })
    highlights.apply()
    local fg, bg = fg_bg("UiTbBufOff")
    config.__restore_state(saved)
    assert.is_true(palette.contrast_ratio(fg, bg) < 2)
  end)
end)
