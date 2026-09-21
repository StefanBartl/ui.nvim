---@module 'ui.statusline.highlights'
--- The `St_*`/`ST_EmptySpace` highlight groups the statusline modules paint
--- with, derived from the active colorscheme -- the statusline's equivalent
--- of `ui.tabline.highlights`.
---
--- This was missing entirely. Step 6 of the roadmap ("the palette") replaced
--- `base46`'s raw color-table access with `ui.theme.palette`, but nothing
--- ever rebuilt the roughly thirty `St_*` groups `base46` used to compile per
--- theme -- every shipped statusline preset (`default`/`minimal`/`lsp`/
--- `blocks`) kept referencing them by name the whole time. An undefined
--- highlight group has no attributes, which is why the statusline looked
--- flat/uncolored next to the old base46-rendered one, and why the mode
--- chip's separator looked like a duplicated glyph instead of a fade -- there
--- was never a background for it to fade against.
---
--- Colors are deliberately restrained: a direct side-by-side against the old
--- base46 statusline showed a strongly colored mode chip plus per-severity
--- diagnostic counts as the only real color, everything else (file/git/lsp/
--- cwd/cursor) plain statusline-foreground text with no filled background.
--- Matched here rather than inventing a busier palette -- "same config, same
--- look" is the actual goal, not "more color".

local M = {}

local api = vim.api
local palette = require("ui.theme.palette")

--- One derived group per base group `ui.statusline.render` has recolored for
--- the currently hovered module: `base`'s own attributes (background, bold,
--- ...) untouched, `fg` swapped to a single hover accent -- "the text
--- brightens", not "the module repaints itself in a new color scheme".
--- Reset by `M.apply()`, since a stale entry would otherwise survive a
--- `:colorscheme` switch with the previous theme's colors baked in.
---@type table<string, string>
local hover_variants = {}

---@param n integer|nil
---@return string|nil
local function to_hex(n)
  if type(n) ~= "number" then
    return nil
  end
  return string.format("#%06x", n)
end

---@param group string
---@param field "fg"|"bg"
---@return string|nil
local function read(group, field)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = group, link = false })
  if not ok or not hl then
    return nil
  end
  return to_hex(hl[field])
end

-- Every mode suffix `ui.statusline.utils.primitives.modes` produces as an
-- entry's second element -- the set `ui.statusline.themes.default`'s
-- `T.mode()` and `ui.config.statusline.blocks`'s `mode()` module already key
-- their `St_<suffix>Mode*` group names on.
---@type string[]
local MODE_SUFFIXES = {
  "Normal",
  "NTerminal",
  "Visual",
  "Insert",
  "Terminal",
  "Replace",
  "Select",
  "Command",
  "Confirm",
}

--- (Re)derive every `St_*`/`ST_EmptySpace` group from the active colorscheme.
--- Safe to call any time -- also the `ColorScheme` handler `M.ensure()`
--- registers.
---@return nil
function M.apply()
  local empty_bg = palette.statusline_bg()
  local fg = read("StatusLine", "fg") or read("Normal", "fg") or "#c0caf5"
  local set = api.nvim_set_hl

  set(0, "ST_EmptySpace", { bg = empty_bg })

  -- One filled mode chip + one fading separator + one text-only variant
  -- (the "blocks" preset's breadcrumbs use the text-only one via
  -- `ui.statusline.modules.highlighting.mode_band_group()`), per mode.
  for _, suffix in ipairs(MODE_SUFFIXES) do
    local accent = palette.mode_accent(suffix)
    local contrast = palette.contrast_fg(accent)
    set(0, "St_" .. suffix .. "Mode", { fg = contrast, bg = accent, bold = true })
    set(0, "St_" .. suffix .. "ModeSep", { fg = accent, bg = empty_bg })
    set(0, "St_" .. suffix .. "ModeText", { fg = accent, bg = empty_bg, bold = true })
  end

  -- Plain-text segments: no fill, the SAME foreground throughout -- the
  -- statusline's own `fg`, not a dimmer "Comment"-derived one some of these
  -- used to read. Mixing the two read as an inconsistent, half-legible
  -- statusline (some segments brighter than others for no reason tied to
  -- meaning), which is what this line-up fixes; the mode chip is the one
  -- deliberate exception, kept on its own contrast colour below because it
  -- sits on a filled accent background, not on the plain statusline one.
  -- Their `*_sep`/`*sep` companions fade to invisible against `empty_bg`
  -- rather than drawing a visible cap -- there is no chip background on
  -- either side of them to cap between.
  set(0, "St_file", { fg = fg, bg = "NONE" })
  set(0, "St_file_sep", { fg = empty_bg, bg = empty_bg })
  set(0, "St_gitIcons", { fg = fg, bg = "NONE" })
  set(0, "St_LspMsg", { fg = fg, bg = "NONE" })
  set(0, "St_Lsp", { fg = fg, bg = "NONE" })
  set(0, "St_cwd_icon", { fg = fg, bg = "NONE" })
  set(0, "St_cwd_text", { fg = fg, bg = "NONE" })
  set(0, "St_cwd_sep", { fg = empty_bg, bg = empty_bg })
  set(0, "St_pos_sep", { fg = empty_bg, bg = empty_bg })
  set(0, "St_pos_icon", { fg = fg, bg = "NONE" })
  set(0, "St_pos_text", { fg = fg, bg = "NONE" })
  set(0, "St_sep_r", { fg = empty_bg, bg = empty_bg })

  -- Per-severity diagnostic counts -- the one place besides the mode chip
  -- that keeps real color, same anchor groups `ui.theme.palette` already
  -- trusts as close to universally defined by modern colorschemes.
  set(0, "St_lspError", { fg = read("DiagnosticError", "fg") or "#e06c75", bg = "NONE" })
  set(0, "St_lspWarning", { fg = read("DiagnosticWarn", "fg") or "#e0af68", bg = "NONE" })
  set(0, "St_lspHints", { fg = read("DiagnosticHint", "fg") or "#a0a8b7", bg = "NONE" })
  set(0, "St_lspInfo", { fg = read("DiagnosticInfo", "fg") or "#7aa2f7", bg = "NONE" })

  -- The "blocks" preset's own gen_block cursor chip is a real filled capsule
  -- (the point of that preset), unlike `default`'s plain `St_pos_*` above --
  -- reuses the "Insert" mode accent rather than adding a tenth semantic key
  -- for one chip that is not mode-dependent itself.
  local pos_accent = palette.mode_accent("Insert")
  local pos_contrast = palette.contrast_fg(pos_accent)
  set(0, "St_Pos_bg", { fg = pos_contrast, bg = pos_accent, bold = true })
  set(0, "St_Pos_txt", { fg = pos_contrast, bg = pos_accent })
  set(0, "St_Pos_sep", { fg = pos_accent, bg = empty_bg })

  -- `plugin_progress`'s transient status line (used by the "default" preset).
  set(0, "St_LspProgress", { fg = fg, bg = "NONE" })

  -- Every `St_Hover__*` variant (see `M.hover_variant` below) was derived
  -- from groups this same colorscheme just changed -- stale otherwise, since
  -- nothing else invalidates them.
  hover_variants = {}
end

--- `DiagnosticWarn` is the hover accent's anchor (an amber/orange in most
--- colorschemes, already what `St_lspWarning` above reads), same "close to
--- universally defined" reasoning `ui.theme.palette` documents for its own
--- anchors.
---@return string hex
local function hover_fg()
  return read("DiagnosticWarn", "fg") or read("WarningMsg", "fg") or "#e0af68"
end

--- The hover variant of `base_group`, creating and caching it on first use.
--- Safe to call with any group name, defined or not -- `nvim_get_hl` on an
--- unknown group simply returns no attributes, so the variant degrades to
--- "just the hover fg, no background", never an error.
---@param base_group string
---@return string
function M.hover_variant(base_group)
  local cached = hover_variants[base_group]
  if cached then
    return cached
  end

  local ok, hl = pcall(api.nvim_get_hl, 0, { name = base_group, link = false })
  local attrs = (ok and type(hl) == "table") and vim.deepcopy(hl) or {}
  attrs.fg = hover_fg()

  local name = "St_Hover__" .. base_group
  api.nvim_set_hl(0, name, attrs)
  hover_variants[base_group] = name
  return name
end

local ensured = false

--- Apply once, then keep the groups current across `:UI theme`/`:colorscheme`
--- switches. Idempotent -- safe to call from every path that might be first
--- (`ui.statusline.render`'s `enable()`, `:checkhealth ui`, tests).
---@return nil
function M.ensure()
  if ensured then
    return
  end
  ensured = true

  -- `hl.persist` rather than a hand-written apply-plus-autocmd: it also
  -- covers `OptionSet background`, which this block did not. Switching
  -- background selects the other half of a light/dark palette without
  -- necessarily re-sourcing the colorscheme, so the statusline could keep
  -- the old palette's derived colours until the next real theme change.
  require("lib.nvim.ui.hl").persist(M.apply, { name = "ui_statusline_highlights" })
end

return M
