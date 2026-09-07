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

--- Accent color (a base46 `base_30` key) per cwd_mode name, for the
--- bg-filled capsule look — the same recipe NvChad's own base46 uses for
--- St_NormalMode/St_NormalModeSep (see nvchad-ui's stl/default.lua
--- `genModes_hl`). Deliberately keyed by MODE NAME rather than filetree's
--- `indicator.hl` group: the mode name is stable regardless of what hl group
--- the user points a mode at, so re-pointing `indicator.hl` in filetree's own
--- config can never silently lose this module's color.
---@type table<string, string>
local DEFAULT_COLOR_BY_MODE = {
  project = "purple",
  nearest = "pink",
  lock = "red",
  manual = "light_grey",
  tree_leads = "vibrant_green",
}
local FALLBACK_COLOR = "light_grey"

--- Badge/separator highlight groups, built lazily per color key and rebuilt
--- on ColorScheme — there is no persistent bg-filled equivalent of
--- "DiagnosticWarn" to reuse, so this derives one from the active theme's
--- own palette instead of hardcoding hex values.
---@type table<string, true>
local _hl_built = {}

---The color the second-stage separator fades into. Reads "ST_EmptySpace"'s
---own `fg` at runtime rather than assuming one hardcoded shade: the active
---statusline preset picks the actual color (grey in NvChad's "default" theme,
---black in "minimal" — see base46's integrations/statusline/*.lua), and this
---way the fade matches whichever one is actually wired up in
---`ui.statusline.theme`, without this module needing to know which.
---@return string? hex
local function empty_space_fg()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "ST_EmptySpace", link = false })
  if ok and hl.fg then
    return string.format("#%06x", hl.fg)
  end
  return nil
end

---@param color_key string  A `base_30` key, e.g. "red", "purple".
---@return string? group   nil if the active theme doesn't expose base46 (e.g. between colorschemes).
local function ensure_hl(color_key)
  local group = "St_Cwd_" .. color_key
  if _hl_built[group] then
    return group
  end

  local ok, base46 = pcall(require, "base46")
  if not ok then
    return nil
  end
  local colors = base46.get_theme_tb("base_30")
  local col = colors and colors[color_key]
  if not col then
    return nil
  end

  vim.api.nvim_set_hl(0, group, { fg = colors.black, bg = col, bold = true })
  vim.api.nvim_set_hl(0, group .. "Sep", { fg = col, bg = empty_space_fg() or colors.grey })
  _hl_built[group] = true
  return group
end

require("lib.nvim.bindings.autocmd").create("ColorScheme", function()
  _hl_built = {}
end, {
  group = require("lib.nvim.bindings.autocmd").group("UiCwdModeBadgeHl", true),
  desc = "Rebuild the filetree cwd-mode badge highlights for the new theme's palette",
})

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
  local group = ensure_hl(color_key)
  if not group then
    -- Between colorschemes, or a base46-less setup: fall back rather than
    -- show nothing.
    return " %#" .. hl .. "#" .. badge.text .. " "
  end

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
