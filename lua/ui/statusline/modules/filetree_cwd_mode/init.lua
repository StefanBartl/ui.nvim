---@module 'ui.statusline.modules.filetree_cwd_mode'
--- filetree.nvim's cwd_mode badge (PROJECT/PKG/LOCK/MANUAL/TREE, or whatever
--- `indicator.style` renders it as), read via its external-statusline API
--- rather than filetree's own tree-window badge.
---
--- Requires `features.cwd_mode.indicator.enabled = false` in the filetree
--- setup() call (see lua/plugins/personal/init.lua) — otherwise the mode
--- shows twice: once here, once bottom-left in the tree window.
---
--- No manual refresh wiring needed: cwd_mode fires a scheduled `:redrawstatus`
--- itself whenever the badge text/highlight would change (see its
--- `User FiletreeCwdModeChanged` autocmd), and NvChad's statusline re-evaluates
--- this function on every redraw regardless.

local get_separators = require("ui.statusline.utils.get_separators")
local palette = require("ui.theme.palette")

--- Semantic accent key (see `ui.theme.palette`) per cwd_mode name, for the
--- bg-filled capsule look — the same recipe NvChad's own base46 used for
--- St_NormalMode/St_NormalModeSep (see nvchad-ui's stl/default.lua
--- `genModes_hl`), now derived from the active colorscheme instead of a
--- bundled theme table (step 6). Deliberately keyed by MODE NAME rather than
--- filetree's `indicator.hl` group: the mode name is stable regardless of
--- what hl group the user points a mode at, so re-pointing `indicator.hl` in
--- filetree's own config can never silently lose this module's color.
---@type table<string, Ui.Theme.SemanticKey>
local DEFAULT_COLOR_BY_MODE = {
  project = "project",
  nearest = "nearest",
  lock = "lock",
  manual = "manual",
  tree_leads = "tree_leads",
}
local FALLBACK_COLOR = "manual"

--- Badge/separator highlight groups, built lazily per color key and rebuilt
--- on ColorScheme — there is no persistent bg-filled equivalent of
--- "DiagnosticWarn" to reuse, so this derives one from the active theme's
--- own palette instead of hardcoding hex values.
---@type table<string, true>
local _hl_built = {}

require("lib.nvim.bindings.autocmd").create("ColorScheme", function()
  _hl_built = {}
end, {
  group = require("lib.nvim.bindings.autocmd").group("UiCwdModeBadgeHl", true),
  desc = "Rebuild the filetree cwd-mode badge highlights for the new theme's palette",
})

---@param color_key string  A palette semantic key, or a literal "#rrggbb".
---@return string group
local function ensure_hl(color_key)
  local is_hex = color_key:match("^#%x%x%x%x%x%x$") ~= nil
  local group = "St_Cwd_" .. (is_hex and color_key:sub(2) or color_key)
  if _hl_built[group] then
    return group
  end

  ---@diagnostic disable-next-line: param-type-mismatch -- validated above
  local accent = is_hex and color_key or palette.accent(color_key)
  local fg = palette.contrast_fg(accent)

  vim.api.nvim_set_hl(0, group, { fg = fg, bg = accent, bold = true })
  vim.api.nvim_set_hl(0, group .. "Sep", { fg = accent, bg = palette.statusline_bg() })
  _hl_built[group] = true
  return group
end

---@param opts { badge_style?: boolean, colors?: table<string, string> }?
---  badge_style: bg-filled capsule with a fading separator, like the vim
---               mode segment (default true). false = plain colored text,
---               using filetree's own `indicator.hl` group as-is.
---  colors:      override/extend DEFAULT_COLOR_BY_MODE, e.g. { lock = "orange" }.
---@return string
return function(opts)
  opts = opts or {}
  local badge_style = opts.badge_style ~= false

  -- `package.loaded` rather than `require`: the statusline is evaluated on the
  -- very first redraw, so a `require` here PULLS filetree.nvim in before the
  -- first paint -- measured at ~202ms, for a badge nobody can read yet. The
  -- plugin loads on VeryLazy by itself moments later; until then this segment
  -- is simply empty, and cwd_mode fires its own `:redrawstatus` once it has
  -- something to show (see the module header).
  local ft = package.loaded["filetree"]
  if type(ft) ~= "table" or type(ft.feature) ~= "function" then
    return ""
  end

  local cwd_mode = ft.feature("cwd_mode")
  if not cwd_mode then
    return ""
  end

  local badge = cwd_mode.badge()
  if badge.text == "" then
    return ""
  end

  -- badge.hl is a real, always-defined Neovim group (DiagnosticWarn/Info/…),
  -- picked per mode by cwd_mode itself — no local St_* group to keep in sync.
  -- Falls back to "Comment" only if a custom cwd_mode.indicator.hl table omits
  -- an entry for the active mode.
  local hl = badge.hl or "Comment"

  if not badge_style then
    return " %#" .. hl .. "#" .. badge.text .. " "
  end

  local color_key = (opts.colors and opts.colors[badge.mode])
    or DEFAULT_COLOR_BY_MODE[badge.mode]
    or FALLBACK_COLOR
  -- ensure_hl always resolves now (palette.accent has its own fallback hex),
  -- unlike the old base46 lookup, which returned nil between colorschemes.
  local group = ensure_hl(color_key)

  local sep = get_separators()

  return "%#"
    .. group
    .. "# "
    .. badge.text
    .. " "
    .. "%#"
    .. group
    .. "Sep#"
    .. sep.right
    .. "%#ST_EmptySpace#"
    .. sep.right
end
