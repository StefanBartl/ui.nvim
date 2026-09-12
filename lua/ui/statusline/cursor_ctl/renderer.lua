---@module 'ui.statusline.cursor_ctl.renderer'
-- Renderers for progress text ----------------------------------------------

local M = {}

--- Escape "%" for statusline so it is treated as a literal percent sign.
--- @param s string
--- @return string
local function esc_percent(s)
  local out = s:gsub("%%", "%%%%")
  return out
end

--- Compute an 8-level bar index from a 0..100 percentage.
--- @param pct integer
--- @return string
local function pct_bar(pct)
  if pct < 0 then
    pct = 0
  elseif pct > 100 then
    pct = 100
  end
  local bars = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
  local step = 100 / #bars
  local idx = math.floor(pct / step) + 1
  if idx < 1 then
    idx = 1
  elseif idx > #bars then
    idx = #bars
  end
  return bars[idx]
end

--- Build a compact progress token like "  37% ▅ " (escaped for statusline).
---
--- A space separates "%" from the bar glyph -- without it, a full/near-full
--- block character (█) sits close enough to the percent sign that they read
--- as touching/overlapping in most fonts, especially at the high end of the
--- 8-level scale.
--- @param pct integer|nil
--- @param prefix string  -- e.g. "R" or "C" or ""
--- @return string
function M.pct_token(pct, prefix)
  if not pct then
    return esc_percent("  --%  ")
  end
  local bar = pct_bar(pct)
  local txt = string.format(" %s%3d%% %s ", (prefix and (prefix .. "") or ""), pct, bar)
  return esc_percent(txt)
end

--- Classic cursor string (no escaping; uses statusline placeholders).
--- @return string
function M.cursor_classic()
  -- Keep placeholders so NVim fills line/col dynamically.
  return " Ln %l, Col %v "
end

return M
