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
  local muted_fg = read("Comment", "fg") or fg
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

  -- Plain-text segments: no fill, same foreground the statusline itself
  -- uses. Their `*_sep`/`*sep` companions fade to invisible against
  -- `empty_bg` rather than drawing a visible cap -- there is no chip
  -- background on either side of them to cap between.
  set(0, "St_file", { fg = fg, bg = "NONE" })
  set(0, "St_file_sep", { fg = empty_bg, bg = empty_bg })
  set(0, "St_gitIcons", { fg = muted_fg, bg = "NONE" })
  set(0, "St_LspMsg", { fg = muted_fg, bg = "NONE" })
  set(0, "St_Lsp", { fg = muted_fg, bg = "NONE" })
  set(0, "St_cwd_icon", { fg = muted_fg, bg = "NONE" })
  set(0, "St_cwd_text", { fg = muted_fg, bg = "NONE" })
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
  set(0, "St_LspProgress", { fg = muted_fg, bg = "NONE" })
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

  M.apply()

  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("ColorScheme", M.apply, {
    group = autocmd.group("ui_statusline_highlights", true),
    desc = "ui.statusline: re-derive St_*/ST_EmptySpace groups from the active colorscheme",
  })
end

return M
