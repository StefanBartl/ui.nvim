-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.highlights` -- the `St_*`/`ST_EmptySpace` groups every
--- shipped statusline preset references but that were never actually
--- defined anywhere before this module existed (see its own doc comment).
--- Run WITHOUT NvChad/base46, same constraint as every other spec here.

describe("ui.statusline.highlights.apply", function()
  local highlights = require("ui.statusline.highlights")

  it("runs without throwing", function()
    assert.has_no.errors(function()
      highlights.apply()
    end)
  end)

  it("defines ST_EmptySpace with a background", function()
    highlights.apply()
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "ST_EmptySpace", link = false })
    assert.is_true(ok)
    assert.is_not_nil(hl.bg)
  end)

  it("defines a filled chip (fg+bg) for every mode suffix primitives.modes produces", function()
    highlights.apply()
    local modes = require("ui.statusline.utils.primitives").modes
    local seen = {}
    for _, entry in pairs(modes) do
      local suffix = entry[2]
      if not seen[suffix] then
        seen[suffix] = true
        local hl = vim.api.nvim_get_hl(0, { name = "St_" .. suffix .. "Mode", link = false })
        assert.is_not_nil(hl.fg, "St_" .. suffix .. "Mode has no fg")
        assert.is_not_nil(hl.bg, "St_" .. suffix .. "Mode has no bg")
      end
    end
  end)

  it("a mode's ModeSep fg matches that mode's own Mode bg, for a seamless fade", function()
    highlights.apply()
    local mode = vim.api.nvim_get_hl(0, { name = "St_InsertMode", link = false })
    local sep = vim.api.nvim_get_hl(0, { name = "St_InsertModeSep", link = false })
    assert.equals(mode.bg, sep.fg)
  end)

  it("defines the per-severity diagnostic groups diagnostics() renders with", function()
    highlights.apply()
    for _, group in ipairs({ "St_lspError", "St_lspWarning", "St_lspHints", "St_lspInfo" }) do
      local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
      assert.is_not_nil(hl.fg, group .. " has no fg")
    end
  end)
end)

describe("ui.statusline.highlights.ensure", function()
  local highlights = require("ui.statusline.highlights")

  it("is safe to call more than once", function()
    assert.has_no.errors(function()
      highlights.ensure()
      highlights.ensure()
    end)
  end)
end)

describe("ui.statusline.modules.highlighting.mode_band_group", function()
  it("returns a group name ui.statusline.highlights actually defines", function()
    require("ui.statusline.highlights").apply()
    local hl_module = require("ui.statusline.modules.highlighting")
    local group = hl_module.mode_band_group()
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    assert.is_true(ok)
    assert.is_not_nil(
      hl.bg,
      group .. " has no bg -- mode_band_group()/highlights.apply() names disagree again"
    )
  end)
end)
