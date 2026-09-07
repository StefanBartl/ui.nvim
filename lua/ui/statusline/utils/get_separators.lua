---@module 'ui.statusline.utils.get_separators'
-- ============================================================================
-- Separator Helper
-- ============================================================================

return function()
  local config = require("nvconfig").ui.statusline
  local sep_style = config.separator_style
  local utils = require("nvchad.stl.utils")
  local sep_icons = utils.separators

  -- NvChad's separator table
  local separators = (type(sep_style) == "table" and sep_style) or sep_icons[sep_style]

  return {
    left = separators["left"],
    right = separators["right"],
  }
end
