---@module 'ui.config'
--- Central configuration loader with statusline variant selection.
--- Loads theme config once and applies selected statusline variant.

local notify = require("lib.nvim.notify").create("[ui.config]")

local M = {}

--- The most recently assembled config, or nil before the first `M.setup()`
--- call. `ui.bindings.usrcmds.themes` reads this (falling back to
--- `ui.config.DEFAULTS`) for the `:UI toggle` pair, so a host override passed
--- to `M.setup({ theme = { theme_toggle = {...} } })` reaches that command
--- without step 7's host rewiring having to exist first.
---@type table?
local _last_config = nil

--- The name `M.setup()` last resolved through `ui.config.variants`, or nil
--- if the most recent call brought an anonymous table via `opts.variant`
--- directly (which has no name to report). `M.get_variant()` and `:UI
--- variant`/`:UI status` read this -- it is the actually active variant,
--- which can differ from `M.STATUSLINE_VARIANT` after a runtime switch
--- (`:UI variant <name>` calls `M.setup` again without touching that
--- constant).
---@type string?
local _current_variant_name = nil

-- ============================================================================
-- STATUSLINE VARIANT SELECTION
-- ============================================================================
-- Change this to switch between the shipped, generic presets:
-- "default"  -> Full-featured, closest to the historical NvChad default
-- "minimal"  -> cursor + cwd + progress, nothing else
-- "lsp"      -> LSP-aware breadcrumbs + enhanced modules
-- "blocks"   -> "lsp"'s segments, drawn as gen_block chips
--
-- A fifth option that is NOT a name in this list: pass a fully-built variant
-- table directly via `M.setup({ variant = <table> })` instead of naming one
-- of the four presets above -- see "Bringing your own variant" below. That is
-- how a host with its own plugin-specific segments (a personal case-tracker,
-- a personal filetree fork, ...) uses them without those segments becoming
-- part of this repo's shipped preset list, which has to stay generic for
-- every other user. `docs/examples/personal-statusline-example.lua` is a
-- worked example: the preset this repo used to ship as "custom", before the
-- 2026-09-12 preset consolidation drew this line.
-- ============================================================================

--- Which of the four shipped presets `setup()` assembles, when `opts.variant`
--- is not given as a table (see `M.setup`).
---
--- A setup-time choice, not a runtime one: NvChad reads the assembled table
--- once while booting, through `chadrc`. Changing this after that has no
--- effect until the next start.
---
--- The shipped value is recorded in `ui.config.DEFAULTS.statusline.variant`
--- as well, and a spec asserts the two agree -- two places that can drift
--- otherwise, since one is the switch and the other is the documentation.
---
--- An unknown name falls back to "default" with a notification rather than
--- throwing; `:checkhealth ui` reports whether the named module resolves,
--- because that fallback is otherwise quiet.
---@type Ui.StatuslineVariant
M.STATUSLINE_VARIANT = "default"

-- ============================================================================
-- Config Assembly
-- ============================================================================

--- Bringing your own variant, two ways:
---
---   * `opts.variant` as a TABLE is used directly, anonymously -- the same
---     shape as any file under `lua/ui/config/statusline/`
---     (`{ ui = { statusline = {...} }, setup = function(config) ... end }`),
---     it just does not have to live inside this plugin.
---     `docs/examples/personal-statusline-example.lua` is the worked example.
---   * `opts.variant` as a STRING, or `M.STATUSLINE_VARIANT` when `opts.variant`
---     is absent, resolves through `ui.config.variants` -- the four shipped
---     presets plus whatever a host registered under its own name via
---     `require("ui.config.variants").register(name, variant)`. Registering
---     first is what makes a variant nameable: `:UI variant <name>` and its
---     completion both read the same registry.
---
--- An anonymous table has no name for `M.get_variant()`/`:UI status` to
--- report; register it under a name instead if that matters.
---@param opts table
---@return table
local function load_statusline_config(opts)
  if type(opts.variant) == "table" then
    _current_variant_name = nil
    return opts.variant
  end

  local variants = require("ui.config.variants")
  local name = (type(opts.variant) == "string" and opts.variant) or M.STATUSLINE_VARIANT
  local resolved = variants.resolve(name)

  if not resolved then
    notify.warn(
      string.format("[ui.config] Unknown statusline variant '%s'. Falling back to 'default'", name)
    )
    name = "default"
    resolved = variants.resolve("default")
  end

  _current_variant_name = name
  return resolved
end

---Setup complete configuration
---@param user_opts? table Optional user overrides for theme, plus an
---  optional `variant` table to bring your own statusline preset (see
---  "Bringing your own variant" above `load_statusline_config`).
---@return table
function M.setup(user_opts)
  user_opts = user_opts or {}

  -- 1. Load theme config (centralized)
  local theme_config = require("ui.config.theme")

  -- 2. Allow user overrides for theme
  if user_opts.theme then
    theme_config = vim.tbl_deep_extend("force", theme_config, user_opts.theme)
  end

  -- 3. Load selected statusline variant (shipped preset, or opts.variant)
  local statusline_config = load_statusline_config(user_opts)

  -- 4. Assemble final config
  local config = {
    theme = theme_config,
    ui = statusline_config.ui or {},
  }

  -- 5. Run variant-specific setup if present
  if type(statusline_config.setup) == "function" then
    local setup_ok, setup_err = pcall(statusline_config.setup, config)
    if not setup_ok then
      notify.error(string.format("[ui.config] Statusline setup failed: %s", tostring(setup_err)))
    end
  end

  -- Remove diagnostic backgrounds
  local ok_diag, diag_err = pcall(function()
    require("ui.highlights.diagnostics").setup()
  end)

  if not ok_diag then
    notify.warn("[config] Diagnostic highlight setup failed: " .. tostring(diag_err))
  end

  _last_config = config
  return config
end

---The name of the variant `M.setup()` actually assembled last time it ran --
---nil before the first call, and nil after a call whose `opts.variant` was
---an anonymous table (see `load_statusline_config`). This is the live
---value, which can differ from `M.STATUSLINE_VARIANT` after a runtime
---switch (`:UI variant <name>`).
---@return string?
function M.get_variant()
  return _current_variant_name
end

---The most recently assembled config, or nil if `M.setup()` has not run yet.
---@return table?
function M.last()
  return _last_config
end

return M
