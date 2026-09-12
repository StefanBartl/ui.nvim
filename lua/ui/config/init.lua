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
-- Change this to switch between statusline variants:
-- "normal"         -> Default NvChad statusline (no customization)
-- "base"           -> Minimal custom statusline (cursor + cwd + progress)
-- "lspbased"       -> LSP-aware breadcrumbs + enhanced modules
-- "custom"         -> Legacy custom breadcrumbs implementation
-- "custom_light"   -> "custom" with a merge-based setup() path
-- "custom_minimal" -> "custom" built on NvChad's gen_block pattern
-- ============================================================================

--- Which of the six layouts `setup()` assembles.
---
--- A setup-time choice, not a runtime one: NvChad reads the assembled table
--- once while booting, through `chadrc`. Changing this after that has no
--- effect until the next start.
---
--- The shipped value is recorded in `ui.config.DEFAULTS.statusline.variant`
--- as well, and a spec asserts the two agree -- two places that can drift
--- otherwise, since one is the switch and the other is the documentation.
---
--- An unknown name falls back to "normal" with a notification rather than
--- throwing; `:checkhealth ui` reports whether the named module resolves,
--- because that fallback is otherwise quiet.
---@type Ui.StatuslineVariant
M.STATUSLINE_VARIANT = "normal"

-- ============================================================================
-- Config Assembly
-- ============================================================================

---Load the selected statusline config
---@return table
local function load_statusline_config()
  local variant = M.STATUSLINE_VARIANT
  local config_path = "ui.config.statusline." .. variant

  local ok, config = pcall(require, config_path)
  if not ok then
    notify.warn(
      string.format(
        "[ui.config] Failed to load statusline variant '%s': %s\nFalling back to 'normal'",
        variant,
        tostring(config)
      )
    )
    return (require("ui.config.statusline.normal"))
  end

  return config
end

---Setup complete configuration
---@param user_opts? table Optional user overrides for theme
---@return table
function M.setup(user_opts)
  user_opts = user_opts or {}

  -- 1. Load theme config (centralized)
  local theme_config = require("ui.config.theme")

  -- 2. Allow user overrides for theme
  if user_opts.theme then
    theme_config = vim.tbl_deep_extend("force", theme_config, user_opts.theme)
  end

  -- 3. Load selected statusline variant
  local statusline_config = load_statusline_config()

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
