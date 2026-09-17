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
  -- "follow" is filetree.nvim's inert, no-policy default mode -- most
  -- sessions spend most of their time in it, since it is what a tree starts
  -- in unless something actively re-roots it. Mapped explicitly to "manual"
  -- (same muted accent) rather than left to hit FALLBACK_COLOR below: it
  -- used to fall through by accident, which is indistinguishable from a
  -- deliberate choice until someone asks why the badge is that color at
  -- all.
  follow = "manual",
  tree_leads = "tree_leads",
}
local FALLBACK_COLOR = "manual"

--- Badge/separator highlight groups, built lazily per color key and rebuilt
--- on ColorScheme — there is no persistent bg-filled equivalent of
--- "DiagnosticWarn" to reuse, so this derives one from the active theme's
--- own palette instead of hardcoding hex values.
---@type table<string, true>
local _hl_built = {}

local Autocmd = require("lib.nvim.bindings.autocmd")

-- A colour-derived cache is the same problem as a highlight definition,
-- so it goes through the same helper -- and picks up `OptionSet background`
-- with it. `immediate = false`: there is nothing to drop at registration.
require("lib.nvim.ui.hl").persist(function()
  _hl_built = {}
end, { name = "UiCwdModeBadgeHl", immediate = false })

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

---@param color_key string  A palette semantic key, or a literal "#rrggbb".
---@return string group
--- A plain-foreground sibling of `ensure_hl` for the history dots below --
--- those sit on the statusline's own background, not inside a filled
--- capsule, so a bg-filled group would paint a little colored square around
--- each glyph instead of just tinting it.
local function ensure_dot_hl(color_key)
  local is_hex = color_key:match("^#%x%x%x%x%x%x$") ~= nil
  local group = "St_CwdDot_" .. (is_hex and color_key:sub(2) or color_key)
  if _hl_built[group] then
    return group
  end

  ---@diagnostic disable-next-line: param-type-mismatch -- validated above
  local accent = is_hex and color_key or palette.accent(color_key)
  vim.api.nvim_set_hl(0, group, { fg = accent, bg = palette.statusline_bg() })
  _hl_built[group] = true
  return group
end

--- IDEEN-statusline.md's "Filetree-cwd-mode-Badge: Historie statt nur
--- aktueller Modus" -- the last 3 (mode, root) pairs the badge has shown,
--- oldest first, so a quick round-trip between two cases/projects leaves a
--- visible trail instead of only ever showing "now". Keyed by BOTH mode and
--- root, not mode alone: swapping between two "lock" cases with different
--- roots is exactly the "zwischen zwei Cases hin- und herspringen" case the
--- idea names, and mode alone would show three identical dots for it.
---@class Ui.CwdModeHistory.Entry
---@field mode string
---@field root string|nil

---@type Ui.CwdModeHistory.Entry[]
local history = {}

---@param mode string
---@param root string|nil
---@return nil
local function push_history(mode, root)
  local last = history[#history]
  if last and last.mode == mode and last.root == root then
    return
  end
  history[#history + 1] = { mode = mode, root = root }
  if #history > 3 then
    table.remove(history, 1)
  end
end

local _autocmd_registered = false

---@return nil
local function ensure_history_autocmd()
  if _autocmd_registered then
    return
  end
  _autocmd_registered = true

  Autocmd.create("User", function()
    local ft = package.loaded["filetree"]
    if type(ft) ~= "table" or type(ft.feature) ~= "function" then
      return
    end
    local cwd_mode = ft.feature("cwd_mode")
    if not cwd_mode then
      return
    end
    local badge = cwd_mode.badge()
    if badge.mode then
      push_history(badge.mode, badge.root)
    end
  end, {
    group = Autocmd.group("UiCwdModeHistory", true),
    pattern = "FiletreeCwdModeChanged",
    desc = "ui.statusline: record filetree cwd_mode history for the history-dots badge option",
  })
end

--- Filled circle (current) / hollow circle (earlier) -- U+25CF / U+25CB.
local DOT_CURRENT = "\xE2\x97\x8F"
local DOT_PAST = "\xE2\x97\x8B"

---@param colors table<string, string>|nil  same shape as opts.colors below
---@return string
local function render_history(colors)
  if #history == 0 then
    return ""
  end

  local parts = {}
  local n = #history
  for i = 1, n do
    local entry = history[i]
    local color_key = (colors and colors[entry.mode])
      or DEFAULT_COLOR_BY_MODE[entry.mode]
      or FALLBACK_COLOR
    local group = ensure_dot_hl(color_key)
    local glyph = (i == n) and DOT_CURRENT or DOT_PAST
    parts[#parts + 1] = "%#" .. group .. "#" .. glyph
  end
  return " " .. table.concat(parts) .. " "
end

---@param opts { badge_style?: boolean, colors?: table<string, string>, separator_style?: string|{left: string, right: string}, history?: boolean }?
---  badge_style: bg-filled capsule with a fading separator, like the vim
---               mode segment (default true). false = plain colored text,
---               using filetree's own `indicator.hl` group as-is.
---  colors:      override/extend DEFAULT_COLOR_BY_MODE, e.g. { lock = "orange" }.
---  separator_style: passed to `get_separators()` -- pass the variant's own
---                    `SEPARATOR_STYLE` so this badge's cap matches every
---                    other segment's, instead of silently falling back to
---                    "default" regardless of what the rest of the
---                    statusline is using.
---  history:     append the last 3 (mode, root) badges as small dots
---               (current filled, earlier hollow) -- default false, opt-in
---               since it is a visual addition on top of the existing
---               badge, not a fix to it (IDEEN-statusline.md's
---               "Filetree-cwd-mode-Badge: Historie statt nur aktueller
---               Modus").
---@return string
return function(opts)
  opts = opts or {}
  local badge_style = opts.badge_style ~= false

  ensure_history_autocmd()

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

  -- Seeds the trail for a tree that was already in its current mode before
  -- this module (or the autocmd above) was ever loaded -- same "fall back to
  -- computing it at read time" shape as ui.statusline.modules.time_in_buffer
  -- uses for a buffer that predates its own BufEnter listener.
  if badge.mode and #history == 0 then
    push_history(badge.mode, badge.root)
  end

  local history_str = opts.history and render_history(opts.colors) or ""

  -- badge.hl is a real, always-defined Neovim group (DiagnosticWarn/Info/…),
  -- picked per mode by cwd_mode itself — no local St_* group to keep in sync.
  -- Falls back to "Comment" only if a custom cwd_mode.indicator.hl table omits
  -- an entry for the active mode.
  local hl = badge.hl or "Comment"

  if not badge_style then
    return " %#" .. hl .. "#" .. badge.text .. " " .. history_str
  end

  local color_key = (opts.colors and opts.colors[badge.mode])
    or DEFAULT_COLOR_BY_MODE[badge.mode]
    or FALLBACK_COLOR
  -- ensure_hl always resolves now (palette.accent has its own fallback hex),
  -- unlike the old base46 lookup, which returned nil between colorschemes.
  local group = ensure_hl(color_key)

  local sep = get_separators(opts.separator_style)

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
    .. history_str
end
