---@module 'ui.statusline.modules.diagnostics_sparkline'
--- A density sparkline instead of a plain diagnostic count: a fixed-width
--- row of glyphs, one per equal-sized slice of the buffer, each showing how
--- many diagnostics sit in that slice (height, via `cursor_ctl.renderer`'s
--- 8-level `pct_bar`) and the worst severity among them (colour, the same
--- `St_lsp*` groups `ui.statusline.utils.primitives.diagnostics` renders
--- with). A mini-minimap: WHERE the problems are, not just how many.
---
--- Renders empty on a clean buffer, same contract as the plain `diagnostics`
--- segment it stands in for -- not wired into any shipped preset, add
--- "diagnostics_sparkline" to a host's own `order`/`modules` to opt in.

local renderer = require("ui.statusline.cursor_ctl.renderer")
local primitives = require("ui.statusline.utils.primitives")

-- Width of the sparkline in glyphs. Fixed rather than derived from
-- `vim.o.columns`: a sparkline that resizes with the window would shift
-- every diagnostic's slice on every resize, which reads as noise, not
-- information -- pick a width once and let a slice cover more or fewer
-- lines as the buffer grows or shrinks instead.
local SLICES = 20

-- Severity, worst first (vim.diagnostic.severity.ERROR == 1 is already the
-- lowest number, so "worst" is just "smallest" -- named here so the sort
-- comparison below reads as what it means rather than a bare `<`).
local SEVERITY_HL = {
  [vim.diagnostic.severity.ERROR] = "St_lspError",
  [vim.diagnostic.severity.WARN] = "St_lspWarning",
  [vim.diagnostic.severity.INFO] = "St_lspInfo",
  [vim.diagnostic.severity.HINT] = "St_lspHints",
}

--- Bucket every diagnostic into `SLICES` equal line ranges.
---@param diagnostics table[] # vim.diagnostic.get()'s own return shape
---@param total_lines integer
---@return { count: integer, severity: integer|nil }[] # length SLICES
local function bucket(diagnostics, total_lines)
  local buckets = {}
  for i = 1, SLICES do
    buckets[i] = { count = 0, severity = nil }
  end

  local lines_per_slice = total_lines / SLICES
  for _, d in ipairs(diagnostics) do
    local idx = math.floor(d.lnum / lines_per_slice) + 1
    if idx < 1 then
      idx = 1
    elseif idx > SLICES then
      idx = SLICES
    end

    local b = buckets[idx]
    b.count = b.count + 1
    if not b.severity or d.severity < b.severity then
      b.severity = d.severity
    end
  end

  return buckets
end

---@return string
return function()
  -- The statusline's own target buffer, not whatever is merely "current" --
  -- the same distinction `ui.statusline.utils.primitives` draws everywhere
  -- else, and one this segment needs too: a statusline can render for a
  -- window that is not the focused one.
  local buf = primitives.stbufnr()
  local diagnostics = vim.diagnostic.get(buf)
  if #diagnostics == 0 then
    return ""
  end

  local total_lines = vim.api.nvim_buf_line_count(buf)
  if total_lines <= 0 then
    return ""
  end

  local buckets = bucket(diagnostics, total_lines)

  local max_count = 0
  for _, b in ipairs(buckets) do
    if b.count > max_count then
      max_count = b.count
    end
  end

  local parts = {}
  for _, b in ipairs(buckets) do
    if b.count == 0 then
      -- Neutral, not the loudest colour left standing -- an empty slice is
      -- "nothing here", not "low severity of something".
      parts[#parts + 1] = "%#St_LspMsg#" .. renderer.pct_bar(0)
    else
      local pct = (b.count / max_count) * 100
      local hl = SEVERITY_HL[b.severity] or "St_lspInfo"
      parts[#parts + 1] = "%#" .. hl .. "#" .. renderer.pct_bar(pct)
    end
  end

  return " " .. table.concat(parts) .. " "
end
