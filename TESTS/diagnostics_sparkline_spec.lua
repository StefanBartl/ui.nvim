-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.diagnostics_sparkline` -- a density row instead of
--- a plain count, from IDEEN-statusline.md's "klein, isoliert, schnell"
--- bucket. Not wired into any shipped preset, a host adds it to its own
--- `order`/`modules`.

local sparkline = require("ui.statusline.modules.diagnostics_sparkline")

---@param n integer
---@return integer buf
local function make_buf(n)
  local buf = vim.api.nvim_create_buf(true, false)
  local lines = {}
  for i = 1, n do
    lines[i] = "line " .. i
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

---@param buf integer
---@param diags { lnum: integer, severity: integer }[]
---@return integer ns
local function set_diagnostics(buf, diags)
  local ns = vim.api.nvim_create_namespace("diagnostics_sparkline_spec")
  local items = {}
  for _, d in ipairs(diags) do
    items[#items + 1] = { lnum = d.lnum, col = 0, message = "test", severity = d.severity }
  end
  vim.diagnostic.set(ns, buf, items)
  return ns
end

---@param buf integer
local function cleanup(buf)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
end

describe("ui.statusline.modules.diagnostics_sparkline", function()
  it("renders empty on a buffer with no diagnostics", function()
    local buf = make_buf(100)
    assert.equals("", sparkline())
    cleanup(buf)
  end)

  it("renders exactly 20 slices when there is at least one diagnostic", function()
    local buf = make_buf(100)
    local ns = set_diagnostics(buf, { { lnum = 0, severity = vim.diagnostic.severity.ERROR } })

    local out = sparkline()

    vim.diagnostic.reset(ns, buf)
    cleanup(buf)

    local _, slice_count = out:gsub("%%#St_%a+#", "")
    assert.equals(20, slice_count, out)
  end)

  it("colours an occupied slice by its worst severity", function()
    local buf = make_buf(100)
    -- Lines 0-4 are slice 1 (100 lines / 20 slices = 5 lines each). Mixing an
    -- error and a warning in the same slice must show the error's colour.
    local ns = set_diagnostics(buf, {
      { lnum = 1, severity = vim.diagnostic.severity.WARN },
      { lnum = 2, severity = vim.diagnostic.severity.ERROR },
    })

    local out = sparkline()

    vim.diagnostic.reset(ns, buf)
    cleanup(buf)

    -- The very first glyph group in the row is slice 1.
    assert.is_true(out:find("St_lspError", 1, true) ~= nil, out)
    assert.equals(1, select(2, out:gsub("St_lspError", "")))
  end)

  it("leaves an empty slice in the neutral St_LspMsg colour, not a severity one", function()
    local buf = make_buf(100)
    -- One diagnostic, in slice 1 only -- every other slice must be neutral.
    local ns = set_diagnostics(buf, { { lnum = 0, severity = vim.diagnostic.severity.ERROR } })

    local out = sparkline()

    vim.diagnostic.reset(ns, buf)
    cleanup(buf)

    local _, neutral_count = out:gsub("St_LspMsg", "")
    assert.equals(19, neutral_count, out)
  end)

  it("gives a denser slice a taller bar than a sparser one", function()
    local buf = make_buf(100)
    -- Slice 1 (lines 0-4): one error. Slice 2 (lines 5-9): five errors --
    -- the busiest slice, so it renders the tallest glyph (█, U+2588),
    -- while slice 1 renders something shorter than that.
    local diags = { { lnum = 0, severity = vim.diagnostic.severity.ERROR } }
    for lnum = 5, 9 do
      diags[#diags + 1] = { lnum = lnum, severity = vim.diagnostic.severity.ERROR }
    end
    local ns = set_diagnostics(buf, diags)

    local out = sparkline()

    vim.diagnostic.reset(ns, buf)
    cleanup(buf)

    -- Strip highlight groups, leaving just the 20 glyphs plus the leading/
    -- trailing space this module wraps them in. Each glyph is a multi-byte
    -- UTF-8 character -- gmatch(".") would split those apart, so this reads
    -- one display character at a time via `strcharpart` instead.
    local glyphs = out:gsub("%%#St_%a+#", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local glyph_list = {}
    for i = 0, 19 do
      glyph_list[#glyph_list + 1] = vim.fn.strcharpart(glyphs, i, 1)
    end

    assert.equals("█", glyph_list[2], out) -- slice 2, the busiest, is full height
    assert.is_not.equals("█", glyph_list[1], out) -- slice 1 has only 1/5th the density
  end)

  it("renders empty when the buffer has diagnostics but somehow zero lines", function()
    -- nvim_buf_line_count never actually returns 0 for a real buffer (an
    -- "empty" buffer still counts as one blank line) -- this guards the
    -- division in `bucket()` against ever seeing a zero denominator, not a
    -- case that occurs in practice.
    local buf = make_buf(1)
    local original = vim.api.nvim_buf_line_count
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_buf_line_count = function(b)
      if b == buf then
        return 0
      end
      return original(b)
    end

    local ns = set_diagnostics(buf, { { lnum = 0, severity = vim.diagnostic.severity.ERROR } })
    local out = sparkline()

    vim.api.nvim_buf_line_count = original
    vim.diagnostic.reset(ns, buf)
    cleanup(buf)

    assert.equals("", out)
  end)
end)
