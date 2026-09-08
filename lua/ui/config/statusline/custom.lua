---@module 'ui.config.statusline.custom'
--- Statusline with properly integrated separators

local lazy = require("lib.lua.lazy")
local render_module = lazy.require("ui.statusline.cursor_ctl.renderer")
local progr_calc_module = lazy.require("ui.statusline.cursor_ctl.progress_calculators")
local hl_module = lazy.require("ui.statusline.modules.highlighting")
local lsp_module = lazy.require("ui.statusline.modules.lsp")
local cursor_module = lazy.require("ui.statusline.cursor_ctl")
local get_separators = lazy.require("ui.statusline.utils.get_separators")
local plugin_progress = lazy.require("ui.statusline.modules.plugin_progress")
local plugin_summary = lazy.require("ui.statusline.modules.plugin_summary")
local filetree_cwd_mode = lazy.require("ui.statusline.modules.filetree_cwd_mode")
local casedesk = lazy.require("ui.statusline.modules.casedesk")

-- ============================================================================
-- Modules
-- ============================================================================

-- The single source for this variant's separator style: the config table
-- below and the module closures that call `get_separators` both read this,
-- rather than a global config that separator style used to be read back from.
local SEPARATOR_STYLE = "round" -- "arrow", "round", "block", "default"

return {
  base46 = require("ui.config.base46"),
  ui = {
    statusline = {
      theme = "minimal", -- or "vscode_colored"
      separator_style = SEPARATOR_STYLE,

      order = {
        "mode",
        "git",
        "%=",
        "breadcrumbs",
        "%=",
        "diagnostics",
        "lsp",
        "plugin_progress",
        "plugin_summary",
        "casedesk",
        "filetree_cwd_mode",
        "cursor",
      },

      modules = {
        plugin_progress = function()
          return plugin_progress()
        end,

        plugin_summary = function()
          return plugin_summary()
        end,

        -- Case short-info (number · company · N replies), empty outside a
        -- case folder — see lua/bindings/usrcmds/case/, ROADMAP.md v7.
        casedesk = function()
          return casedesk()
        end,

        -- The label itself (PROJECT/PKG/LOCK/… vs P/N/L/… vs 1/2/3/… vs a
        -- Nerd Font glyph) is filetree's own `features.cwd_mode.indicator.
        -- style` (see lua/plugins/personal/init.lua) — this only controls
        -- how THIS statusline renders whatever text that produces.
        filetree_cwd_mode = function()
          return filetree_cwd_mode({
            badge_style = true, -- bg-filled capsule + fading separator, like `mode`. false = plain colored text.
            -- colors = { lock = "orange" },  -- override the accent per cwd mode; see the module's DEFAULT_COLOR_BY_MODE.
          })
        end,

        --- Mode (overrides the NvChad default, adds separators)
        --- @return string
        mode = function()
          local utils = require("ui.statusline.utils.primitives")
          if not utils.is_activewin() then
            return ""
          end

          local modes = utils.modes
          local m = vim.api.nvim_get_mode().mode
          local mode_name = modes[m][1]
          local mode_type = modes[m][2]

          local sep = get_separators(SEPARATOR_STYLE)

          local current_mode = "%#St_" .. mode_type .. "Mode#  " .. mode_name
          local mode_sep1 = "%#St_" .. mode_type .. "ModeSep#" .. sep.right

          return current_mode .. mode_sep1 .. "%#ST_EmptySpace#" .. sep.right
        end,

        --- @return string
        git = function()
          local utils = require("ui.statusline.utils.primitives")
          local git_status = utils.git()
          if not git_status or git_status == "" then
            return ""
          end

          return " %#St_gitIcons#" .. git_status .. "%#St_gitIcons# " .. " "
        end,

        --- @return string
        breadcrumbs = function()
          local band = hl_module.mode_band_group()
          local content = lsp_module.render_breadcrumbs_inherit_lspfirst(band)

          if not content or content == "" then
            return ""
          end

          local sep = get_separators(SEPARATOR_STYLE)

          return hl_module.hl_open(band) .. content .. "%#" .. band .. "Sep#" .. sep.right .. " "
        end,

        --- @return string
        diagnostics = function()
          local utils = require("ui.statusline.utils.primitives")
          local diag = utils.diagnostics()
          if not diag or diag == "" then
            return ""
          end

          return diag
        end,

        --- @return string
        lsp = function()
          local utils = require("ui.statusline.utils.primitives")
          local lsp_status = utils.lsp()
          if not lsp_status or lsp_status == "" then
            return ""
          end

          return "%#St_Lsp#" .. lsp_status .. " "
        end,

        --- @return string
        cursor = function()
          local mode = cursor_module.get_mode()

          if mode == "off" then
            return ""
          end

          local pieces = { render_module.cursor_classic() }

          if mode == "row_progress" then
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
          elseif mode == "col_progress" then
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
          elseif mode == "rows_cols_progress" then
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
          end

          local content = table.concat(pieces, "")
          local sep = get_separators()

          -- Cursor as in the default theme: left + right separator
          return "%#St_pos_sep#" .. sep.left .. "%#St_pos_icon# %#St_pos_text# " .. content .. " "
        end,
      },
    },
  },
}
