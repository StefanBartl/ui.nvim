---@module 'ui.statusline.modules.highlighting'
--- Helpers for Neovim statusline highlight sequences (%#Group#, %*): strip,
--- open, wrap, and resolve the current mode-band group. Per-function docs
--- are in @types/init.lua.

local Autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

-- Cache for mode band groups
local mode_band_cache = nil
local last_mode = nil

---@nodiscard
--- Strip embedded statusline highlights
---@param s string
---@return string
function M.stl_strip_hl(s)
  -- Use lib.strings for replace operations
  local str = require("lib.lua.strings")
  s = str.replace_all(s, "%%#.-#", "")
  s = str.replace_all(s, "%%%*", "")
  return s
end

---@nodiscard
--- Open highlight group without reset
---@param group string
---@return string
function M.hl_open(group)
  return "%#" .. group .. "#"
end

---@nodiscard
--- Wrap payload with highlight group
---@param group string
---@param s string
---@return string
function M.hl_wrap(group, s)
  if not s or s == "" then
    return ""
  end
  return "%#" .. group .. "#" .. s .. "%*"
end

---@nodiscard
--- Get current mode band group with caching
---@return string
function M.mode_band_group()
  local ok_mode, mode_info = pcall(vim.api.nvim_get_mode)
  if not ok_mode or not mode_info or not mode_info.mode then
    return "St_Normalmode" -- Fallback
  end

  local m = mode_info.mode

  -- Return cached if mode unchanged
  if last_mode == m and mode_band_cache then
    return mode_band_cache
  end

  -- Update cache
  last_mode = m

  local utils = require("ui.statusline.utils.primitives")
  local name = (utils.modes[m] and utils.modes[m][2]) or "Normal"
  mode_band_cache = "St_" .. name .. "mode"

  return mode_band_cache
end

-- Clear cache on mode change
Autocmd.create("ModeChanged", function()
  mode_band_cache = nil
  last_mode = nil
end, {
  group = Autocmd.group("UiHighlightCache", true),
  desc = "Clear mode band cache on mode change",
})

return M
