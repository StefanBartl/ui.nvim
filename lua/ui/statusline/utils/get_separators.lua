---@module 'ui.statusline.utils.get_separators'
-- ============================================================================
-- Separator Helper
-- ============================================================================
--- Resolves a `separator_style` value (a name into `primitives.separators`,
--- or an already-resolved `{left, right}` pair) against this plugin's own
--- glyph sets. Takes the style explicitly rather than reading it from
--- somewhere global -- each statusline variant owns its own separator_style
--- literal, so this stays a pure function of what the caller passes.

---@param sep_style string|{left: string, right: string}
---@return {left: string, right: string}
return function(sep_style)
  local sep_icons = require("ui.statusline.utils.primitives").separators
  -- An unrecognized style name falls back to "default" rather than indexing
  -- nil -- a typo in a custom variant's separator_style degrades instead of
  -- crashing every redraw.
  local separators = (type(sep_style) == "table" and sep_style)
    or sep_icons[sep_style]
    or sep_icons.default

  return {
    left = separators["left"],
    right = separators["right"],
  }
end
