---@module 'ui.statusline.modules.lsp.config'
-- ============================================================================
-- Typed configuration accessor for LSP-based statusline module

local notify = require("lib.nvim.notify").create("[ui.statusline.modules.lsp.config]")

local M = {}

---@type Ui.UI.Stl.Modules.LSP.Cfg
local cfg = {
  debounce_ms = 250,
  update_events = {
    "BufEnter",
    "CursorHold",
    "CursorHoldI",
    "InsertLeave",
    "TextChanged",
    "LspAttach",
  },
  center_width_frac = 0.50,
  center_width_min = 20,
  path_max_frac = 0.60,
  path_max_chars = 45,
  path_min_room = 30,
  path_mode = "absolute",
  path_home_tilde = true,
}

-- ---------------------------------------------------------------------------
-- Accessors
-- ---------------------------------------------------------------------------

--- Get a copy of the full config table.
--- Mutating the returned table has no effect on this module's own state --
--- use `M.set`/`M.update` to actually change it.
---@return Ui.UI.Stl.Modules.LSP.Cfg
function M.get_cfg()
  return vim.deepcopy(cfg)
end

--- Get a single config field with exact type.
---
---@param key Ui.UI.Stl.Modules.Lsp.CfgKey
---@return any
function M.get(key)
  return cfg[key]
end

--- Set a single config field with strict typing.
---
---@param key Ui.UI.Stl.Modules.Lsp.CfgKey
---@param value any
---@return nil
function M.set(key, value)
  cfg[key] = value
end

--- Update multiple fields at once with runtime type checks.
--- Unknown keys are ignored.
--- Type mismatches are rejected -- per field, not for the whole patch: a bad
--- field must not cost the other, valid fields in the same call (`pairs()`
--- order is unspecified, so a `return` here used to drop an arbitrary subset
--- of an otherwise-valid patch depending on hash order).
---
---@param patch table<string, any>
function M.update(patch)
  for key, value in pairs(patch) do
    local current = cfg[key]

    -- ignore unknown keys
    if current ~= nil then
      local current_type = type(current)
      local value_type = type(value)

      -- allow explicit nil for nullable fields
      if value == nil then
        cfg[key] = nil
      elseif current_type == value_type then
        cfg[key] = value
      else
        notify.warn(
          ("LSP config update rejected: field '%s' expects %s, got %s"):format(
            key,
            current_type,
            value_type
          )
        )
      end
    end
  end
end

---@type Ui.UI.Stl.Modules.LSP.Cfg.Module
return M
