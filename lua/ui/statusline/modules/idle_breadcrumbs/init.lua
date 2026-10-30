---@module 'ui.statusline.modules.idle_breadcrumbs'
--- The `breadcrumbs` segment (repo-relative path + LSP/Tree-sitter symbol
--- context, mode-band coloured), with more room while the editor is idle:
--- a wider budget and no fixed path cap, so a long path and a deep symbol
--- chain are cut less or not at all -- the "mehr Platz für Breadcrumbs"
--- payload of IDEEN-statusline.md's "Idle-Erweiterung nach N Sekunden
--- Inaktivität", on the same `ui.statusline.utils.idle` primitive as
--- `idle_clock`. The next keystroke shrinks it back.
---
--- A drop-in replacement for `breadcrumbs`: while active it renders exactly
--- what `breadcrumbs` renders. Only placement and width are decided here --
--- the symbol chain itself is `my.nvim`'s (or the Tree-sitter fallback's),
--- read through `ui.statusline.modules.lsp` like every other breadcrumb.
--- The widening is a per-call override of this segment's own budget; the
--- shared `ui.statusline.modules.lsp.config` and every other segment's
--- width logic stay untouched.

local idle = require("ui.statusline.utils.idle")

local DEFAULT_IDLE_WIDTH_FRAC = 0.80

-- Lifted while idle: no fixed path cap (`false` = "use the fraction") and
-- the whole budget the symbol context leaves over may go to the path.
local IDLE_OVERRIDES = { path_max_chars = false, path_max_frac = 1.0 }

---@class Ui.Statusline.IdleBreadcrumbs.Opts
---@field idle_width_frac? number # share of `columns` the breadcrumb may take while idle, in (0, 1]. Default 0.80. Never narrower than the configured (active) budget.

--- The budget `formatters.compact_breadcrumb_line` would compute on its own
--- (`center_width_frac`/`center_width_min` of the lsp config), so the idle
--- budget can be kept from ever being the narrower of the two.
---@return integer
local function active_budget()
  local cfg = require("ui.statusline.modules.lsp.config")
  local frac = cfg.get("center_width_frac") or 0.50
  local minw = cfg.get("center_width_min") or 30
  return math.max(minw, math.floor(vim.o.columns * frac))
end

---@param opts Ui.Statusline.IdleBreadcrumbs.Opts|nil
---@return integer
local function idle_budget(opts)
  local frac = type(opts) == "table" and opts.idle_width_frac or nil
  if type(frac) ~= "number" or frac ~= frac or frac <= 0 or frac > 1 then
    frac = DEFAULT_IDLE_WIDTH_FRAC
  end
  return math.max(active_budget(), math.floor(vim.o.columns * frac))
end

---@param opts Ui.Statusline.IdleBreadcrumbs.Opts|nil
---@return string
return function(opts)
  local lsp = require("ui.statusline.modules.lsp")
  local band = lsp.mode_band_group()
  if not idle.is_idle() then
    return lsp.hl_open(band) .. lsp.render_breadcrumbs_inherit_lspfirst(band)
  end
  return lsp.hl_open(band)
    .. lsp.render_breadcrumbs_inherit_lspfirst(band, idle_budget(opts), IDLE_OVERRIDES)
end
