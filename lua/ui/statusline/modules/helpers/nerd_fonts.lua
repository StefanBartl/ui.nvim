---@module 'ui.statusline.modules.helpers.nerd_fonts'
------------------------------------
-- NERD FONTS HELPER
-------------------------------------

local M = {}

--- Choose the breadcrumb separator: prefer the given Nerd Font codepoint,
--- but fall back to a Unicode arrow if the glyph is not available or too wide.
---@param hex string                 -- preferred Nerd Font codepoint in hex, e.g. "F0056"
---@return string                    -- separator surrounded by spaces, e.g. "  "
function M.nerdf_sep_or_fallback(hex)
  local g = require("lib.lua.strings.convert.hex_to_string")(hex)
  -- Only accept if it renders as a single display cell (prevents centering drift)
  if g ~= "" and vim.fn.strdisplaywidth(g) == 1 then
    return " " .. g .. " "
  end
  -- Fallbacks with broad font coverage
  local wide = vim.o.columns >= 100
  return wide and " ⟶ " or " › "
end

return M
