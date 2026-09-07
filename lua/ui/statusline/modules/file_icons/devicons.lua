---@module 'ui.statusline.modules.file_icons.devicons'
--- Optimized devicons with proper caching and lazy-loading

local M = {}

local api = vim.api
local Autocmd = require("lib.nvim.bindings.autocmd")

-- Lazy-load dependencies
local hl_module
local function get_hl_module()
  if not hl_module then
    ---@type Ui.UI.Stl.Modules.Highlighting
    hl_module = require("lib.lua.lazy").require("ui.statusline.modules.highlighting")
  end
  return hl_module
end

-- Caches with proper invalidation
local icon_cache = require("lib.lua.memo.lru").new(256)
local hl_cache = { name = "St_FileIcon", fg = nil, bg = nil }

-- Devicons module lazy-loaded
local devicons_mod = nil

---@nodiscard
---@param n integer|nil
---@return string|nil
local function int_to_hex(n)
  if type(n) ~= "number" then
    return nil
  end
  return string.format("#%06x", n)
end

---@nodiscard
---@return string|nil
local function mode_band_bg_hex()
  local hl = get_hl_module()
  local group = hl.mode_band_group()

  local ok, hl_def = pcall(api.nvim_get_hl, 0, { name = group, link = false })
  if not ok or not hl_def then
    return nil
  end

  return int_to_hex(hl_def.bg)
end

---@nodiscard
---@param fg string|nil
---@param band_bg string|nil
---@return string
local function ensure_icon_hl(fg, band_bg)
  -- Skip if unchanged
  if hl_cache.fg == fg and hl_cache.bg == band_bg then
    return hl_cache.name
  end

  local ok = pcall(api.nvim_set_hl, 0, hl_cache.name, { fg = fg, bg = band_bg })
  if ok then
    hl_cache.fg = fg
    hl_cache.bg = band_bg
  end

  return hl_cache.name
end

---@nodiscard
---@param path string
---@return string icon, string|nil color
local function devicon_for_path(path)
  -- Check cache first
  local cache_key = path
  local cached = icon_cache:get(cache_key)
  if cached then
    return cached.icon, cached.color
  end

  local filename = (path == "" or path == nil) and "[No Name]" or vim.fn.fnamemodify(path, ":t")
  local ext = filename:match("^.+%.(.+)$") or ""

  -- Lazy-load devicons
  if not devicons_mod then
    local ok, mod = pcall(require, "nvim-web-devicons")
    if ok then
      devicons_mod = mod
    else
      -- Cache failure result
      local result = { icon = "󰈙", color = nil }
      icon_cache:put(cache_key, result)
      return result.icon, result.color
    end
  end

  local icon, color

  -- Try get_icon_color first (most complete)
  local ok_get = pcall(function()
    icon, color = devicons_mod.get_icon_color(filename, ext, { default = true })
  end)

  -- Fallback to separate calls
  if not ok_get or not icon then
    icon = devicons_mod.get_icon(filename, ext, { default = true })
    if devicons_mod.get_color then
      pcall(function()
        color = devicons_mod.get_color(filename, ext, { default = true })
      end)
    end
  end

  -- Final fallback
  if not icon or icon == "" then
    icon = "󰈙"
  end

  -- Cache result
  local result = { icon = icon, color = color }
  icon_cache:put(cache_key, result)

  return icon, color
end

---@nodiscard
---@return string
function M.file_icon_segment()
  local ok_utils, utils = pcall(require, "nvchad.stl.utils")
  if not ok_utils then
    return ""
  end

  local bufnr = utils.stbufnr()

  -- Validate buffer
  if not bufnr or bufnr <= 0 then
    return ""
  end

  local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
  if not ok_valid or not is_valid then
    return ""
  end

  local ok_name, path = pcall(api.nvim_buf_get_name, bufnr)
  path = ok_name and path or ""

  local icon, fg = devicon_for_path(path)
  local bg = mode_band_bg_hex()
  local group = ensure_icon_hl(fg, bg)

  return "%#" .. group .. "#" .. icon .. "%*"
end

---@nodiscard
---@param band_group string
---@return string
function M.file_icon_segment_inherit(band_group)
  local ok_utils, utils = pcall(require, "nvchad.stl.utils")
  if not ok_utils then
    return ""
  end

  local bufnr = utils.stbufnr()

  -- Validate buffer
  if not bufnr or bufnr <= 0 then
    return ""
  end

  local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
  if not ok_valid or not is_valid then
    return ""
  end

  local ok_name, path = pcall(api.nvim_buf_get_name, bufnr)
  path = ok_name and path or ""

  local icon, fg = devicon_for_path(path)
  local bg = mode_band_bg_hex()
  local group = ensure_icon_hl(fg, bg)

  return "%#" .. group .. "#" .. icon .. "%#" .. band_group .. "#"
end

---@nodiscard
---@return string
function M.file_icon_segment_lsp()
  local ok_utils, utils = pcall(require, "nvchad.stl.utils")
  if not ok_utils then
    return ""
  end

  local bufnr = utils.stbufnr()

  -- Validate buffer
  if not bufnr or bufnr <= 0 then
    return ""
  end

  local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
  if not ok_valid or not is_valid then
    return ""
  end

  -- Check LSP clients
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  if not clients or vim.tbl_isempty(clients) then
    return ""
  end

  local ok_name, path = pcall(api.nvim_buf_get_name, bufnr)
  path = ok_name and path or ""

  if path == "" then
    return ""
  end

  local icon, fg = devicon_for_path(path)
  if not icon or icon == "" then
    return ""
  end

  local bg = mode_band_bg_hex()
  local group = ensure_icon_hl(fg, bg)

  return "%#" .. group .. "#" .. icon .. "%*"
end

-- Clear cache on colorscheme change
Autocmd.create("ColorScheme", function()
  icon_cache = require("lib.lua.memo.lru").new(256)
  hl_cache = { name = "St_FileIcon", fg = nil, bg = nil }
end, {
  group = Autocmd.group("UiDeviconsCache", true),
  desc = "Clear devicons cache on colorscheme change",
})

return M
