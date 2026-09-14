---@module 'ui.statusline.modules.lsp'
--- LSP-first breadcrumbs for NvChad statusline (async + cached), with Treesitter fallback.

local M = {}

-- Lazy-load submodules to break circular dependencies
local lsp_path_helpers
local doc_symbols
local devicons
local formatters

local function ensure_deps()
  if not lsp_path_helpers then
    lsp_path_helpers = require("ui.statusline.modules.lsp.helpers.paths")
  end
  if not doc_symbols then
    doc_symbols = require("ui.statusline.modules.lsp.symbols.document_symbols")
  end
  if not devicons then
    devicons = require("ui.statusline.modules.file_icons.devicons")
  end
  if not formatters then
    formatters = require("ui.statusline.modules.formatters")
  end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.symbol_context_smart()
  ensure_deps()
  return doc_symbols.symbol_context_smart()
end

---@return string
function M.mode_band_group()
  local hl_module = require("ui.statusline.modules.highlighting")
  return hl_module.mode_band_group()
end

---@param group string
function M.hl_open(group)
  local hl_module = require("ui.statusline.modules.highlighting")
  return hl_module.hl_open(group)
end

--------------------------------------------------------------------------------
-- Renderers
--------------------------------------------------------------------------------

local SEP_HEX = "f0058"

-- SEP_HEX never changes at runtime, so resolve its glyph and displayable-ness
-- once here instead of re-decoding + re-measuring it (via a fresh closure) on
-- every single breadcrumb render.
local SEP_GLYPH = require("lib.lua.strings.convert.hex_to_string")(SEP_HEX)
local SEP_GLYPH_USABLE = SEP_GLYPH ~= "" and vim.fn.strdisplaywidth(SEP_GLYPH) == 1

---@return string
local function breadcrumb_sep()
  return " "
    .. (SEP_GLYPH_USABLE and SEP_GLYPH or ((vim.o.columns >= 100) and "⟶" or "›"))
    .. " "
end

---@return string
function M.render_breadcrumbs_lspfirst()
  ensure_deps()
  local utils = require("ui.statusline.utils.primitives")
  local bufnr = utils.stbufnr()
  local rel = lsp_path_helpers.display_path_for_buf(bufnr)
  local ctx = doc_symbols.symbol_context_smart()
  local icon = devicons.file_icon_segment_lsp()

  local line = formatters.compact_breadcrumb_line(rel, ctx, breadcrumb_sep(), nil)
  line = formatters.stl_escape(line)
  return icon .. " " .. line .. "%*"
end

---@param band_group string
function M.render_breadcrumbs_inherit_lspfirst(band_group)
  ensure_deps()
  local utils = require("ui.statusline.utils.primitives")
  local bufnr = utils.stbufnr()
  local rel = lsp_path_helpers.display_path_for_buf(bufnr)
  local ctx = doc_symbols.symbol_context_smart()
  local icon = devicons.file_icon_segment_inherit(band_group)

  local line = formatters.compact_breadcrumb_line(rel, ctx, breadcrumb_sep(), nil)
  line = formatters.stl_escape(line)
  return icon .. " " .. line
end

return M
