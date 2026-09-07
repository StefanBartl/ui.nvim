---@module 'ui.bindings.usrcmds.themes'
---Theme management for Base46/NvChad
---
---This module handles the complex theme switching logic for NvChad's Base46 system.
---Unlike typical colorscheme switching, Base46 requires:
---1. Loading the theme data from base46.themes
---2. Recompiling all highlight groups
---3. Persisting changes to chadrc.lua file
---

local notify = require("lib.nvim.notify").create("[ui.bindings.usrcmds.themes]")

local M = {}

-----------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------

---Fallback theme list if Base46 themes can't be loaded
local FALLBACK_THEMES = {
  "ashes",
  "ayu_dark",
  "ayu_light",
  "bearded_arc",
  "catppuccin",
  "chadracula",
  "chocolate",
  "dark_horizon",
  "decay",
  "doomchad",
  "everblush",
  "everforest",
  "falcon",
  "flex_light",
  "gruvbox",
  "gruvbox_light",
  "gruvchad",
  "gatekeeper",
  "javacafe",
  "jellybeans",
  "kanagawa",
  "melange",
  "mito_laser",
  "monekai",
  "mountain",
  "monochrome",
  "nightfox",
  "nightlamp",
  "nord",
  "oceanic_next",
  "one_light",
  "onedark",
  "onenord",
  "onenord_light",
  "pastelDark",
  "pastelbeans",
  "penumbra_dark",
  "penumbra_light",
  "poimandres",
  "radium",
  "rosepine",
  "rxyhn",
  "solarized_dark",
  "solarized_osaka",
  "sweetpastel",
  "tokyodark",
  "tokyonight",
  "tundra",
  "vscode_dark",
  "wombat",
  "yoru",
}

-----------------------------------------------------------------------
-- Config Access
-----------------------------------------------------------------------

---Get the chadrc configuration
---@return table|nil
local function get_chadrc_config()
  local ok, chadrc = pcall(require, "chadrc")
  if ok and chadrc and chadrc.base46 then
    return chadrc.base46
  end
  return nil
end

---Update chadrc in-memory configuration
---@param key string
---@param value any
local function update_chadrc_memory(key, value)
  local chadrc = get_chadrc_config()
  if chadrc then
    chadrc[key] = value
  end
end

---Get current theme from config
---@return string|nil
function M.get_current_theme()
  local config = get_chadrc_config()
  return config and config.theme or nil
end

-----------------------------------------------------------------------
-- Theme Discovery
-----------------------------------------------------------------------

---Get all available Base46 themes
---@return string[]
function M.list_themes()
  -- Method 1: Try base46.themes module (most reliable)
  local ok, themes_module = pcall(require, "base46.themes")
  if ok and themes_module then
    local names = {}
    for name, _ in pairs(themes_module) do
      names[#names + 1] = name
    end
    table.sort(names)
    if #names > 0 then
      return names
    end
  end

  -- Method 2: Scan themes directory
  local themes_path = vim.fn.stdpath("data") .. "/lazy/base46/lua/base46/themes"
  local ok2, files = pcall(vim.fn.readdir, themes_path)
  if ok2 and files then
    local names = {}
    for _, file in ipairs(files) do
      if file:match("%.lua$") then
        local theme_name = file:gsub("%.lua$", "")
        names[#names + 1] = theme_name
      end
    end
    table.sort(names)
    if #names > 0 then
      return names
    end
  end

  -- Method 3: Fallback list
  notify.notify("[ui.command.themes] themes list cannot be loaded", vim.log.levels.INFO)
  return FALLBACK_THEMES
end

---Check if a theme exists
---@param theme string
---@return boolean
function M.theme_exists(theme)
  local themes = M.list_themes()
  for _, name in ipairs(themes) do
    if name == theme then
      return true
    end
  end
  return false
end

-----------------------------------------------------------------------
-- Theme Persistence
-----------------------------------------------------------------------

---Find chadrc.lua file path
---@return string|nil
local function find_chadrc_path()
  -- Common locations
  local paths = {
    vim.fn.stdpath("config") .. "/lua/chadrc.lua",
    vim.fn.stdpath("config") .. "/chadrc.lua",
  }

  for _, path in ipairs(paths) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

---Persist theme change to chadrc.lua file
---@param theme string
---@return boolean success
local function persist_theme(theme)
  local chadrc_path = find_chadrc_path()

  if not chadrc_path then
    notify.warn("Warnung: chadrc.lua nicht gefunden. Theme nur für diese Sitzung aktiv.")
    return false
  end

  -- Read file
  local ok, content = pcall(vim.fn.readfile, chadrc_path)
  if not ok then
    return false
  end

  -- Find and replace theme line
  local modified = false
  for i, line in ipairs(content) do
    -- Match: theme = "something"
    if line:match('%s*theme%s*=%s*"[^"]*"') then
      local old_theme = line:match('theme%s*=%s*"([^"]*)"')
      content[i] = line:gsub('theme%s*=%s*"' .. old_theme .. '"', 'theme = "' .. theme .. '"')
      modified = true
      break
    end
  end

  if not modified then
    return false
  end

  -- Write back
  local ok2 = pcall(vim.fn.writefile, content, chadrc_path)
  return ok2
end

-----------------------------------------------------------------------
-- Theme Loading (Core Logic)
-----------------------------------------------------------------------

---Load a theme using Base46's system
---
---This is the core function that properly loads themes in NvChad.
---Key differences from normal colorscheme switching:
---
---1. Base46 doesn't use vim.cmd.colorscheme()
---2. Themes are data tables, not colorscheme files
---3. load_all_highlights() recompiles everything
---4. Changes must be persisted to chadrc.lua
---
---@param theme string Theme name
---@return boolean success
function M.load_theme(theme)
  -- Validate theme exists
  if not M.theme_exists(theme) then
    return false
  end

  -- Get Base46 module
  local ok, base46 = pcall(require, "base46")
  if not ok then
    notify.error("Fehler: Base46 nicht geladen. Ist NvChad installiert?")
    return false
  end

  -- Update in-memory config
  update_chadrc_memory("theme", theme)

  -- Reload chadrc module to pick up new theme
  package.loaded.chadrc = nil
  pcall(require, "chadrc")

  -- Load all highlights (this is the key function!)
  -- This recompiles the entire highlight system with the new theme
  base46.load_all_highlights()

  -- Persist to file (async, don't block on failure)
  vim.schedule(function()
    persist_theme(theme)
  end)

  return true
end

-----------------------------------------------------------------------
-- Transparency Management
-----------------------------------------------------------------------

---Get current transparency setting
---@return boolean
function M.get_transparency()
  local config = get_chadrc_config()
  return config and config.transparency or false
end

---Set transparency state
---@param enabled boolean
---@return boolean success
function M.set_transparency(enabled)
  local current = M.get_transparency()

  -- Only toggle if different from current state
  if current ~= enabled then
    local ok, base46 = pcall(require, "base46")
    if ok and base46 and base46.toggle_transparency then
      base46.toggle_transparency()
      return true
    end
  end

  return false
end

---Toggle transparency
---@return boolean new_state
function M.toggle_transparency()
  local ok, base46 = pcall(require, "base46")
  if ok and base46 and base46.toggle_transparency then
    base46.toggle_transparency()
    return M.get_transparency()
  end
  return false
end

-----------------------------------------------------------------------
-- Theme Toggle
-----------------------------------------------------------------------

---Toggle between configured themes
---@return string|nil next_theme
function M.toggle_theme()
  local config = get_chadrc_config()

  if not config or not config.theme_toggle or #config.theme_toggle < 2 then
    return nil
  end

  local current = M.get_current_theme()
  local themes = config.theme_toggle
  local next_theme

  -- Find next theme in toggle list
  for i, theme in ipairs(themes) do
    if theme == current then
      next_theme = themes[(i % #themes) + 1]
      break
    end
  end

  -- If current not in list, use first
  next_theme = next_theme or themes[1]

  if M.load_theme(next_theme) then
    return next_theme
  end

  return nil
end

-----------------------------------------------------------------------
-- Utility Functions
-----------------------------------------------------------------------

---Get theme display info
---@return table info {theme: string, transparency: boolean, toggle_themes: string[]}
function M.get_info()
  local config = get_chadrc_config()

  return {
    theme = M.get_current_theme(),
    transparency = M.get_transparency(),
    toggle_themes = config and config.theme_toggle or {},
  }
end

return M
