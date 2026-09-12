---@module 'ui.bindings.usrcmds.themes'
--- Theme management: real `:colorscheme` switching, plus this plugin's own
--- transparency toggle.
---
--- Was Base46-specific -- loading NvChad's own theme data tables,
--- recompiling every highlight group through `load_all_highlights()`, and
--- hand-rewriting `chadrc.lua` to persist a choice across restarts. Step 6 of
--- the roadmap replaced all of that: `M.load_theme()` is `:colorscheme`, the
--- theme list is `getcompletion("", "color")` (every colorscheme Neovim can
--- see, not a fixed NvChad set), and there is no file-persistence any more --
--- see `README.md` in this directory for why that is a deliberate scope cut,
--- not an oversight.

local transparency = require("ui.theme.transparency")

local M = {}

-----------------------------------------------------------------------
-- Config Access
-----------------------------------------------------------------------

---The active theme config: the most recently assembled `ui.config.setup()`
---result if one exists (so a host override reaches these commands without
---needing to re-run setup), the shipped defaults otherwise.
---@return { transparency: boolean, theme_toggle: string[] }
local function active_theme_cfg()
  local cfg = require("ui.config").last()
  return (cfg and cfg.theme) or require("ui.config.DEFAULTS").theme
end

-----------------------------------------------------------------------
-- Theme Discovery
-----------------------------------------------------------------------

---All colorschemes Neovim can currently see -- built-in and installed.
---@return string[]
function M.list_themes()
  local names = vim.fn.getcompletion("", "color")
  table.sort(names)
  return names
end

---@param theme string
---@return boolean
function M.theme_exists(theme)
  for _, name in ipairs(M.list_themes()) do
    if name == theme then
      return true
    end
  end
  return false
end

---@return string|nil
function M.get_current_theme()
  return vim.g.colors_name
end

-----------------------------------------------------------------------
-- Theme Loading
-----------------------------------------------------------------------

---Switch the active colorscheme.
---@param theme string
---@return boolean success
function M.load_theme(theme)
  if not M.theme_exists(theme) then
    return false
  end
  return (pcall(vim.cmd.colorscheme, theme))
end

-----------------------------------------------------------------------
-- Transparency
-----------------------------------------------------------------------

---@return boolean
function M.get_transparency()
  return transparency.is_enabled()
end

---@param enabled boolean
---@return boolean success # false if already in the requested state
function M.set_transparency(enabled)
  if transparency.is_enabled() == enabled then
    return false
  end
  transparency.set(enabled)
  return true
end

---@return boolean new_state
function M.toggle_transparency()
  return transparency.toggle()
end

-----------------------------------------------------------------------
-- Theme Toggle
-----------------------------------------------------------------------

---Toggle between the two themes named in `theme_toggle`.
---@return string|nil next_theme
function M.toggle_theme()
  local pair = active_theme_cfg().theme_toggle

  if not pair or #pair < 2 then
    return nil
  end

  local current = M.get_current_theme()
  local next_theme = pair[1]
  for i, name in ipairs(pair) do
    if name == current then
      next_theme = pair[(i % #pair) + 1]
      break
    end
  end

  if M.load_theme(next_theme) then
    return next_theme
  end
  return nil
end

-----------------------------------------------------------------------
-- Utility Functions
-----------------------------------------------------------------------

---@return table info {theme: string?, transparency: boolean, toggle_themes: string[]}
function M.get_info()
  return {
    theme = M.get_current_theme(),
    transparency = M.get_transparency(),
    toggle_themes = active_theme_cfg().theme_toggle or {},
  }
end

return M
