---@module 'ui.tabline.highlights'
--- The `UiTb*` highlight groups the tabline modules paint with, derived from
--- Neovim's own `TabLine`/`TabLineFill`/`TabLineSel` groups -- every
--- colorscheme defines those three (they are Neovim's own tabline groups,
--- not this plugin's invention), so this needs no palette or bundled theme
--- the way `ui.theme.palette` does for the statusline's mode accents.
---
--- Distinct namespace from NvChad's own `Tb*` groups (`TbBufOn`, `TbTabOn`,
--- ...) on purpose: those come from a `base46`-generated cache file
--- (`dofile(vim.g.base46_cache .. "tbline")`, still loaded by NvChad's own
--- `nvchad.tabufline.lazyload` while that plugin remains installed), and
--- reusing the names would make this module's colors depend on that cache
--- existing -- exactly the coupling ui.nvim's own decoupling is removing.

local M = {}

local api = vim.api

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

--- (Re)derive every `UiTb*` group from the active colorscheme. Safe to call
--- any time -- each call re-reads the groups below fresh, so it is also the
--- `ColorScheme` handler `M.ensure()` registers.
---@return nil
function M.apply()
  local sel_bg = read("TabLineSel", "bg") or read("Normal", "bg") or "#1a1b26"
  local sel_fg = read("TabLineSel", "fg") or read("Normal", "fg") or "#c0caf5"
  local fill_bg = read("TabLineFill", "bg") or read("TabLine", "bg") or sel_bg
  local off_bg = read("TabLine", "bg") or fill_bg
  local off_fg = read("TabLine", "fg") or read("Comment", "fg") or "#565f89"
  local warn_fg = read("DiagnosticWarn", "fg") or "#e0af68"
  local muted_fg = read("Comment", "fg") or off_fg
  local flash_bg = read("Visual", "bg") or read("CursorLine", "bg") or warn_fg
  local flash_fg = read("Visual", "fg") or sel_fg

  local set = api.nvim_set_hl
  set(0, "UiTbFill", { bg = fill_bg })

  set(0, "UiTbBufOn", { fg = sel_fg, bg = sel_bg, bold = true })
  set(0, "UiTbBufOff", { fg = off_fg, bg = off_bg })
  set(0, "UiTbBufOnModified", { fg = warn_fg, bg = sel_bg })
  set(0, "UiTbBufOffModified", { fg = warn_fg, bg = off_bg })
  set(0, "UiTbBufOnClose", { fg = muted_fg, bg = sel_bg })
  set(0, "UiTbBufOffClose", { fg = muted_fg, bg = off_bg })

  -- Click-flash (see ui.tabline.utils.flash) -- a distinct, momentary color,
  -- not a shade of On/Off, so a click reads as feedback rather than an
  -- instant, easy-to-miss re-render.
  set(0, "UiTbBufFlash", { fg = flash_fg, bg = flash_bg, bold = true })

  -- Rounded chip caps: fg matches the chip's own background (the "pill"
  -- color), bg matches the fill between chips -- the same recipe as the
  -- statusline's own mode-chip separator (`ui.statusline.highlights`), one
  -- layer over.
  set(0, "UiTbBufOnCap", { fg = sel_bg, bg = fill_bg })
  set(0, "UiTbBufOffCap", { fg = off_bg, bg = fill_bg })

  -- The "divider" style's plain vertical bar between chips -- muted, on the
  -- fill background, no per-chip color the way the rounded caps have.
  set(0, "UiTbDivider", { fg = muted_fg, bg = fill_bg })

  set(0, "UiTbTabOn", { fg = sel_fg, bg = sel_bg, bold = true })
  set(0, "UiTbTabOff", { fg = off_fg, bg = off_bg })
  set(0, "UiTbTabNewBtn", { fg = sel_fg, bg = fill_bg })
  set(0, "UiTbTitle", { fg = off_fg, bg = fill_bg })

  set(0, "UiTbThemeToggleBtn", { fg = sel_fg, bg = fill_bg })
  set(0, "UiTbCloseAllBufsBtn", { fg = warn_fg, bg = fill_bg })

  set(0, "UiTbTreeOffset", { bg = fill_bg })
end

local ensured = false

--- Apply once, then keep the groups current across `:UI theme`/`:colorscheme`
--- switches. Idempotent -- safe to call from every render path that might be
--- first (`render.lua`'s `enable()`, `:checkhealth ui`, tests).
---@return nil
function M.ensure()
  if ensured then
    return
  end
  ensured = true

  M.apply()

  local autocmd = require("lib.nvim.bindings.autocmd")
  autocmd.create("ColorScheme", M.apply, {
    group = autocmd.group("ui_tabline_highlights", true),
    desc = "ui.tabline: re-derive UiTb* groups from the active colorscheme",
  })
end

return M
