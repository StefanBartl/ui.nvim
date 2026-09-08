---@module 'ui.config.statusline.custom_light'
--- Central configuration setup for Ui UI modules.
--- Provides a setup function that merges user config with base defaults.

local M = {}

-- Lazy-load modules to avoid circular dependencies
local lsp_module
local cursor_ctl_module
local hl_module
local renderer
local pct

local function ensure_modules()
  if not lsp_module then
    lsp_module = require("ui.statusline.modules.lsp")
  end
  if not cursor_ctl_module then
    cursor_ctl_module = require("ui.statusline.cursor_ctl")
  end
  if not hl_module then
    hl_module = require("ui.statusline.modules.highlighting")
  end
  if not renderer then
    renderer = require("ui.statusline.cursor_ctl.renderer")
  end
  if not pct then
    pct = require("ui.statusline.cursor_ctl.progress_calculators")
  end
end

---@param user_config? table User configuration to merge with defaults
---@return table config Complete configuration with all modules registered
function M.setup(user_config)
  user_config = user_config or {}

  -- Get base defaults
  local BASE_CFG = require("ui.config.base46")

  -- Deep merge: user config overrides base defaults
  local config = vim.tbl_deep_extend("force", BASE_CFG, user_config)

  -- Ensure UI structure exists
  config.ui = config.ui or {}
  config.ui.statusline = config.ui.statusline or {}
  config.base46 = require("ui.config.base46")

  -- Register statusline modules
  M.register_statusline_modules(config.ui.statusline)

  return config
end

---@param stl_config table Statusline configuration table
function M.register_statusline_modules(stl_config)
  ensure_modules()

  stl_config.modules = stl_config.modules or {}
  stl_config.order = stl_config.order
    or {
      "mode",
      "git",
      "%=",
      "breadcrumbs",
      "%=",
      "diagnostics",
      "lsp",
      "cursor",
      "progress",
      "cwd",
    }

  -- Breadcrumbs module (LSP-aware)
  stl_config.modules.breadcrumbs = function()
    local band = lsp_module.mode_band_group()
    return lsp_module.hl_open(band) .. lsp_module.render_breadcrumbs_inherit_lspfirst(band)
  end

  -- Diagnostics module (re-wrapped with mode band)
  stl_config.modules.diagnostics = function()
    local U = require("ui.statusline.utils.primitives")
    local s = U.diagnostics()
    return hl_module.hl_wrap(hl_module.mode_band_group(), hl_module.stl_strip_hl(s))
  end

  -- LSP status module
  stl_config.modules.lsp = function()
    local U = require("ui.statusline.utils.primitives")
    local s = U.lsp()
    return hl_module.hl_wrap(hl_module.mode_band_group(), hl_module.stl_strip_hl(s))
  end

  -- Cursor module with progress support
  stl_config.modules.cursor = function()
    local band = hl_module.mode_band_group()
    local mode = cursor_ctl_module.get_mode()

    if mode == "off" then
      return ""
    end

    local pieces = { renderer.cursor_classic() }

    if mode == "row_progress" then
      pieces[#pieces + 1] = renderer.pct_token(pct.compute_row_pct(), "R")
    elseif mode == "col_progress" then
      pieces[#pieces + 1] = renderer.pct_token(pct.compute_col_pct(), "C")
    elseif mode == "rows_cols_progress" then
      pieces[#pieces + 1] = renderer.pct_token(pct.compute_row_pct(), "R")
      pieces[#pieces + 1] = renderer.pct_token(pct.compute_col_pct(), "C")
    end

    return hl_module.hl_wrap(band, table.concat(pieces, ""))
  end

  -- Progress module (empty since progress is in cursor)
  stl_config.modules.progress = function()
    return ""
  end
end

-- Public API for cursor progress control
---@param mode Ui.UI.Stl.CursorCtl.Progress.Mode
M.set_cursor_progress_mode = function(mode)
  ensure_modules()
  return cursor_ctl_module.set_mode(mode)
end

M.toggle_cursor_progress_mode = function()
  ensure_modules()
  return cursor_ctl_module.toggle_mode()
end

M.get_cursor_progress_mode = function()
  ensure_modules()
  return cursor_ctl_module.get_mode()
end

return M
