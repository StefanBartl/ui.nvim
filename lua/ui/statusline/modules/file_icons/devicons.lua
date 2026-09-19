---@module 'ui.statusline.modules.file_icons.devicons'
--- Optimized devicons with proper caching and lazy-loading

local M = {}

local api = vim.api

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

-- One highlight group PER (fg, bg) combination actually seen, not one shared
-- mutable group: with a single global group, two windows on different
-- filetypes/modes at the same time (any split layout) had the second
-- window's redraw silently overwrite the first window's icon color, because
-- both `%#St_FileIcon#` references pointed at the one group this module kept
-- repainting. Keyed by hex, not by table identity, so it survives across
-- calls; reset on ColorScheme since the color values themselves go stale.
---@type table<string, true>
local hl_built = {}

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
---@param hex string|nil
---@return string
local function hex_key(hex)
  return hex and hex:gsub("#", "") or "none"
end

---@nodiscard
---@param fg string|nil
---@param band_bg string|nil
---@return string
local function ensure_icon_hl(fg, band_bg)
  local name = "St_FileIcon_" .. hex_key(fg) .. "_" .. hex_key(band_bg)
  if hl_built[name] then
    return name
  end

  local ok = pcall(api.nvim_set_hl, 0, name, { fg = fg, bg = band_bg })
  if ok then
    hl_built[name] = true
  end

  return name
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
    local mod = require("ui.util.soft_require").try("nvim-web-devicons")
    if mod then
      devicons_mod = mod
    else
      -- No plugin: lib.nvim's own icon table (a curated devicons subset)
      -- instead of one generic glyph for every file. `prefer_plugin =
      -- false` because this branch already knows the plugin is absent, and
      -- `fallback` keeps the old generic glyph for a host without a Nerd
      -- Font declaration -- the column used to show that glyph regardless.
      local result = { icon = "󰈙", color = nil }
      local ok_lib, lib_icons = pcall(require, "lib.nvim.ui.icons")
      if ok_lib then
        local ok_get, icon, color = pcall(lib_icons.get, filename, nil, {
          prefer_plugin = false,
          fallback = "󰈙",
        })
        if ok_get and icon and icon ~= "" then
          result = { icon = icon, color = color }
        end
      end
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
  local utils = require("ui.statusline.utils.primitives")
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
  local utils = require("ui.statusline.utils.primitives")
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
  local utils = require("ui.statusline.utils.primitives")
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
require("lib.nvim.ui.hl").persist(function()
  icon_cache = require("lib.lua.memo.lru").new(256)
  hl_built = {}
end, { name = "UiDeviconsCache", immediate = false })

return M
