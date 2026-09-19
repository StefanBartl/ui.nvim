---@module 'ui.statusline.modules.lsp'
--- LSP-first breadcrumbs for NvChad statusline (async + cached), with Treesitter fallback.

local soft_require = require("ui.util.soft_require")

local M = {}

-- Lazy-load submodules to break circular dependencies
local lsp_path_helpers
local ts_symbols
local devicons
local formatters

local function ensure_deps()
  if not lsp_path_helpers then
    lsp_path_helpers = require("ui.statusline.modules.lsp.helpers.paths")
  end
  if not ts_symbols then
    ts_symbols = require("ui.statusline.modules.lsp.symbols.treesitter")
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

--- The symbol chain around the cursor, or nil.
---
--- **`my.nvim` owns this content; this plugin renders it.** The async
--- `documentSymbol` engine used to live here, in the frame plugin, while
--- `my.nvim` -- whose declared scope is breadcrumb *content* -- had a
--- provider pipeline whose LSP stage read a buffer variable nothing ever
--- set. Two plugins, one feature, and the working half in the wrong one.
--- The engine moved to `my.hl_config.breadcrumbs.ctx.providers.lsp_symbols`
--- (cross-feature report, finding B1); this asks for the string.
---
--- It is the mirror of `ui.winbar`, where `my.nvim` produces the line and
--- this plugin writes it: one producer, two surfaces, one direction.
---
--- Without `my.nvim` the Tree-sitter fallback below is the whole answer --
--- the same graceful degradation `my.nvim` performs when this plugin is
--- absent and it applies the winbar itself.
---@nodiscard
---@return string|nil
local function compute_symbol_context_smart()
  local lsp_symbols = soft_require.try("my.hl_config.breadcrumbs.ctx.providers.lsp_symbols")
  if lsp_symbols then
    local ok, ctx = pcall(lsp_symbols.context, nil)
    if ok and type(ctx) == "string" and #ctx > 0 then
      return ctx
    end
  end

  ensure_deps()
  local ok_ts, ctx_ts = pcall(ts_symbols.symbol_context_ts)
  if ok_ts and type(ctx_ts) == "string" and #ctx_ts > 0 then
    return ctx_ts
  end

  return nil
end

---@type { winid: integer, bufnr: integer, value: string|nil, at: integer }|nil
--- Last `compute_symbol_context_smart()` result, reused for `debounce_ms`
--- (`ui.statusline.modules.lsp.config`) instead of recomputed on every call --
--- 'statusline' is re-evaluated on essentially every cursor move and
--- keystroke, and a full Tree-sitter ancestor walk plus node-text extraction
--- is not a guard's cheap exit, so the hot path needs the throttle this
--- module's own config already declares (PERF-93).
---
--- Keyed by window as well as buffer: the symbol chain depends on the
--- cursor position (`lsp_symbols.context()`/`symbol_context_ts()` both read
--- it), and two windows can show the same buffer at two different cursor
--- lines. A bufnr-only key would hand one window's breadcrumb to the other
--- for up to `debounce_ms` whenever both redraw within that window.
local ctx_cache = nil

---@nodiscard
---@return string|nil
function M.symbol_context_smart()
  local config_mod = require("ui.statusline.modules.lsp.config")
  local debounce_ms = config_mod.get("debounce_ms")
  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_get_current_buf()
  local now = (vim.uv or vim.loop).now()

  if
    type(debounce_ms) == "number"
    and debounce_ms > 0
    and ctx_cache
    and ctx_cache.winid == winid
    and ctx_cache.bufnr == bufnr
    and (now - ctx_cache.at) < debounce_ms
  then
    return ctx_cache.value
  end

  local value = compute_symbol_context_smart()
  ctx_cache = { winid = winid, bufnr = bufnr, value = value, at = now }
  return value
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

-- SEP_HEX never changes at runtime, so resolve its glyph once here instead
-- of re-decoding + re-measuring it on every single breadcrumb render.
--
-- `lib.nvim.ui.nerd_font.glyph` rather than a hand-rolled decode plus width
-- measurement: it is the same check, plus the `vim.g.have_nerd_font` gate
-- this used to skip -- which is what kept a Nerd Font glyph on screen for
-- users who never declared one.
--
-- `""` is a sentinel here, not a rendered fallback: the real fallback
-- depends on `columns`, which changes on resize, so it cannot be resolved
-- until render time.
local SEP_GLYPH = require("lib.nvim.ui.nerd_font").glyph(SEP_HEX, "")

---@return string
local function breadcrumb_sep()
  return " "
    .. (SEP_GLYPH ~= "" and SEP_GLYPH or ((vim.o.columns >= 100) and "⟶" or "›"))
    .. " "
end

---@return string
function M.render_breadcrumbs_lspfirst()
  ensure_deps()
  local utils = require("ui.statusline.utils.primitives")
  local bufnr = utils.stbufnr()
  local rel = lsp_path_helpers.display_path_for_buf(bufnr)
  local ctx = M.symbol_context_smart()
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
  local ctx = M.symbol_context_smart()
  local icon = devicons.file_icon_segment_inherit(band_group)

  local line = formatters.compact_breadcrumb_line(rel, ctx, breadcrumb_sep(), nil)
  line = formatters.stl_escape(line)
  return icon .. " " .. line
end

return M
