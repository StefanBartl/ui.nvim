---@module 'ui.config.statusline.custom_minimal'
--- Statusline using NvChad's gen_block pattern

local lazy = require("lib.lua.lazy")
local render_module = lazy.require("ui.statusline.cursor_ctl.renderer")
local progr_calc_module = lazy.require("ui.statusline.cursor_ctl.progress_calculators")
local hl_module = lazy.require("ui.statusline.modules.highlighting")
local lsp_module = lazy.require("ui.statusline.modules.lsp")
local cursor_module = lazy.require("ui.statusline.cursor_ctl")

-- ============================================================================
-- Gen block helper (mirrors NvChad's own nvchad/stl/minimal.lua)
-- ============================================================================

local function get_gen_block()
  local config = require("nvconfig").ui.statusline
  local sep_style = config.separator_style
  local utils = require("nvchad.stl.utils")

  sep_style = (sep_style ~= "round" and sep_style ~= "block") and "block" or sep_style
  local sep_icons = utils.separators
  local separators = (type(sep_style) == "table" and sep_style) or sep_icons[sep_style]

  local sep_l = separators["left"]
  local sep_r = "%#St_sep_r#" .. separators["right"] .. " %#ST_EmptySpace#"

  ---@param icon string
  ---@param txt string
  ---@param sep_l_hlgroup string
  ---@param iconHl_group string
  ---@param txt_hl_group string
  ---@return string
  return function(icon, txt, sep_l_hlgroup, iconHl_group, txt_hl_group)
    return sep_l_hlgroup
      .. sep_l
      .. iconHl_group
      .. icon
      .. " "
      .. txt_hl_group
      .. " "
      .. txt
      .. sep_r
  end
end

return {
  base46 = require("ui.config.base46"),
  ui = {
    statusline = {
      theme = "default",
      separator_style = "arrow",

      order = {
        "mode",
        "git",
        "%=",
        "breadcrumbs",
        "%=",
        "diagnostics",
        "lsp",
        "cursor",
      },

      modules = {
        --- Mode (minimal.lua style)
        mode = function()
          local ok_utils, utils = pcall(require, "nvchad.stl.utils")
          if not ok_utils or not utils.is_activewin() then
            return ""
          end

          local gen_block = get_gen_block()
          local modes = utils.modes
          local m = vim.api.nvim_get_mode().mode

          return gen_block(
            "",
            modes[m][1],
            "%#St_" .. modes[m][2] .. "ModeSep#",
            "%#St_" .. modes[m][2] .. "Mode#",
            "%#St_" .. modes[m][2] .. "ModeText#"
          )
        end,

        --- Git
        git = function()
          local ok_utils, utils = pcall(require, "nvchad.stl.utils")
          if not ok_utils then
            return ""
          end
          return "%#St_gitIcons#" .. utils.git()
        end,

        --- Breadcrumbs (inline, without gen_block)
        breadcrumbs = function()
          local band = hl_module.mode_band_group()
          local content = lsp_module.render_breadcrumbs_inherit_lspfirst(band)

          if not content or content == "" then
            return ""
          end

          return hl_module.hl_open(band) .. content
        end,

        --- Diagnostics
        diagnostics = function()
          local ok_utils, utils = pcall(require, "nvchad.stl.utils")
          if not ok_utils then
            return ""
          end
          return utils.diagnostics()
        end,

        --- LSP
        lsp = function()
          local ok_utils, utils = pcall(require, "nvchad.stl.utils")
          if not ok_utils then
            return ""
          end
          return "%#St_Lsp#" .. utils.lsp()
        end,

        --- Cursor (minimal.lua style mit gen_block)
        cursor = function()
          local gen_block = get_gen_block()
          local mode = cursor_module.get_mode()

          if mode == "off" then
            return ""
          end

          local pieces = { "%l/%v" }

          if mode == "row_progress" then
            pieces[#pieces + 1] = " "
              .. render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
          elseif mode == "col_progress" then
            pieces[#pieces + 1] = " "
              .. render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
          elseif mode == "rows_cols_progress" then
            pieces[#pieces + 1] = " "
              .. render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
            pieces[#pieces + 1] = " "
              .. render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
          end

          local content = table.concat(pieces, "")

          return gen_block("", content, "%#St_Pos_sep#", "%#St_Pos_bg#", "%#St_Pos_txt#")
        end,
      },
    },
  },
}
