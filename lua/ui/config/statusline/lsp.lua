---@module 'ui.config.statusline.lsp'
--- LSP-aware generic preset: breadcrumbs, diagnostics and LSP status wrapped
--- in the current mode's color band, cursor position with optional
--- row/column progress.
---
--- Was two files: "lspbased" (a thin variant declaring `order` and
--- delegating module registration) and "custom_light" (the actual segment
--- logic, reached through a merge-based `setup()` that only worked because
--- of an unrelated `vim.tbl_deep_extend` reference-sharing detail -- keys
--- present in only one of the two merged tables are shared by reference, not
--- deep-copied, which is what let the mutation reach the real config object
--- despite `custom_light.M.setup()`'s own local `config` shadowing it. One
--- file now, one explicit contract: `M.setup(config)` mutates
--- `config.ui.statusline` in place, the same pattern this repo's other
--- inline-table presets (`default`, `minimal`) use without needing a
--- `setup()` at all.

local lazy = require("lib.lua.lazy")
local lsp_module = lazy.require("ui.statusline.modules.lsp")
local cursor_ctl_module = lazy.require("ui.statusline.cursor_ctl")
local hl_module = lazy.require("ui.statusline.modules.highlighting")
local renderer = lazy.require("ui.statusline.cursor_ctl.renderer")
local pct = lazy.require("ui.statusline.cursor_ctl.progress_calculators")

local M = {}

M.ui = {
  statusline = {
    order = {
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
    },

    -- Filled in by M.setup() below.
    modules = {},
  },
}

---@param config table
function M.setup(config)
  local stl = config.ui and config.ui.statusline
  if not stl then
    return
  end
  stl.modules = stl.modules or {}

  -- Breadcrumbs module (LSP-aware)
  stl.modules.breadcrumbs = function()
    local band = lsp_module.mode_band_group()
    return lsp_module.hl_open(band) .. lsp_module.render_breadcrumbs_inherit_lspfirst(band)
  end

  -- Diagnostics module (re-wrapped with mode band)
  stl.modules.diagnostics = function()
    local U = require("ui.statusline.utils.primitives")
    local s = U.diagnostics()
    return hl_module.hl_wrap(hl_module.mode_band_group(), hl_module.stl_strip_hl(s))
  end

  -- LSP status module
  stl.modules.lsp = function()
    local U = require("ui.statusline.utils.primitives")
    local s = U.lsp()
    return hl_module.hl_wrap(hl_module.mode_band_group(), hl_module.stl_strip_hl(s))
  end

  -- Cursor module with progress support
  stl.modules.cursor = function()
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

  -- Progress module (empty since progress is folded into cursor)
  stl.modules.progress = function()
    return ""
  end
end

return M
