---@module 'ui.statusline.modules.custom.breadcrumbs.render'
-------------------------------------
-- RENDER BREADCRUMBS
-------------------------------------

local nerd_font_helpers = require("ui.statusline.modules.helpers.nerd_fonts")
local devicons = require("ui.statusline.modules.file_icons.devicons")

local M = {}

--- Render the centered breadcrumbs module (no leading/trailing spaces to keep centering exact).
--- @return string
function M.render_breadcrumbs()
  local utils = require("nvchad.stl.utils")
  local bufnr = utils.stbufnr()
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    return ""
  end

  local rel = M.repo_relative(path)
  local ctx = M.symbol_context()

  -- Prefix the relative path with a filetype icon (colored to match the mode band)
  local icon_seg = devicons.file_icon_segment()

  -- separate filepath from breadcrumb with nerd font hex code
  local sep = nerd_font_helpers.nerdf_sep_or_fallback("f0058")

  local line = ctx and (#ctx > 0) and (rel .. sep .. ctx) or rel
  -- Optional: scale with window width (use ~40% of columns)
  local maxw = math.max(30, math.floor(vim.o.columns * 0.5))
  line = M.ellipsize_middle(line, maxw)
  line = M.stl_escape(line)

  -- No leading/trailing spaces overall; add a single space between icon and text.
  line = icon_seg .. " " .. line

  return line .. "%*"
end

return M
