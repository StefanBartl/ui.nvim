---@module 'ui.config'
--- Central configuration loader with statusline variant selection.
--- Loads base46 config once and applies selected statusline variant.

local notify = require("lib.nvim.notify").create("[ui.config]")

local M = {}

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
---@param user_opts? table Optional user overrides for base46
---@return table
function M.setup(user_opts)
  user_opts = user_opts or {}

  -- 1. Load base46 config (centralized)
  local base46_config = require("ui.config.base46")

  -- 2. Allow user overrides for base46
  if user_opts.base46 then
    base46_config = vim.tbl_deep_extend("force", base46_config, user_opts.base46)
  end

  -- 3. Load selected statusline variant
  local statusline_config = load_statusline_config()

  -- 4. Assemble final config
  local config = {
    base46 = base46_config,
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

  return config
end

---Get current statusline variant
---@return string
function M.get_variant()
  return M.STATUSLINE_VARIANT
end

return M
