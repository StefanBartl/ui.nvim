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

--- Bringing your own variant: `opts.variant`, when it is a table, is used
--- directly instead of resolving `M.STATUSLINE_VARIANT` against this repo's
--- own `ui.config.statusline.*` modules. The table has the same shape as any
--- file under `lua/ui/config/statusline/` -- `{ ui = { statusline = {...} },
--- setup = function(config) ... end }` -- it just does not have to live
--- inside this plugin to be usable. This is the mechanism
--- `docs/examples/personal-statusline-example.lua` assumes.
---@param opts table
---@return table
local function load_statusline_config(opts)
  if type(opts.variant) == "table" then
    return opts.variant
  end

  local variant = M.STATUSLINE_VARIANT
  local config_path = "ui.config.statusline." .. variant

  local ok, config = pcall(require, config_path)
  if not ok then
    notify.warn(
      string.format(
        "[ui.config] Failed to load statusline variant '%s': %s\nFalling back to 'default'",
        variant,
        tostring(config)
      )
    )
    return (require("ui.config.statusline.default"))
  end

  return config
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

---Get current statusline variant
---@return string
function M.get_variant()
  return M.STATUSLINE_VARIANT
end

---The most recently assembled config, or nil if `M.setup()` has not run yet.
---@return table?
function M.last()
  return _last_config
end

return M
