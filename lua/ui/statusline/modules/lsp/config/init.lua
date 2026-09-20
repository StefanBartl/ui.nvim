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

-- The set of legitimate field names, captured once from `cfg`'s own initial
-- keys (every one of which starts non-nil, `path_max_chars` -- the one
-- field typed `number|nil` -- included, since its shipped default is 45,
-- not nil). `M.update` below used to test "is this a known key" with
-- `cfg[key] ~= nil`, which reads as "does it currently hold a value" --
-- indistinguishable, in plain Lua table indexing, from "was this key ever
-- explicitly cleared". `M.update({ path_max_chars = nil })` (an explicitly
-- supported, documented call: "allow explicit nil for nullable fields")
-- left `cfg.path_max_chars` nil, and every later attempt to set it back to
-- a real number then read as an unknown key too and was silently swallowed
-- -- a field, once nulled, could never be set again. A fixed snapshot of
-- the real keys sidesteps that: it does not change when `cfg[key]` does.
---@type table<string, true>
local KNOWN_KEYS = {}
-- Declared type for each known field, from the same initial `cfg` snapshot.
-- `apply_field` below cannot type-check a value against `cfg[key]`'s own
-- live type once `path_max_chars` -- the one nullable field -- has been
-- cleared: with the live value nil there is no live type left to compare
-- against. Without this fixed snapshot, that left
-- `apply_field("path_max_chars", <wrong type>)` falling through as if it
-- were the field's first-ever assignment, accepting any type silently (no
-- `notify.warn`, ERR-22 again) -- e.g. `set("path_max_chars", nil)` then
-- `set("path_max_chars", "45")` stored the string, which
-- `formatters.compact_breadcrumb_line`'s `math.min(room,
-- options.path_max_chars)` then threw on.
---@type table<string, string>
local KNOWN_TYPES = {}
for key, value in pairs(cfg) do
  KNOWN_KEYS[key] = true
  KNOWN_TYPES[key] = type(value)
end

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

---@internal
--- Validate and apply one `key = value` write to `cfg` -- shared by `M.set`
--- and `M.update`'s per-key loop, and NOT expressed as `M.set(key, value)`
--- calling `M.update({ [key] = value })`: a Lua table constructor silently
--- drops a `nil`-valued key (`{ [key] = nil }` never inserts `key` at all,
--- same as `({}).x = nil` never had), so building a one-entry patch table
--- around `value` loses the "explicit nil" case the moment `value` actually
--- is nil -- `M.set("path_max_chars", nil)` went through `pairs({})` and
--- silently did nothing instead of clearing the field. Calling this
--- function directly with `value` as an ordinary argument has no such
--- pitfall: a Lua function call, unlike a table constructor, does not drop
--- an explicit nil.
---@param key string
---@param value any
local function apply_field(key, value)
  -- ignore unknown keys
  if not KNOWN_KEYS[key] then
    return
  end

  -- allow explicit nil for nullable fields
  if value == nil then
    cfg[key] = nil
    return
  end

  -- Checked against `KNOWN_TYPES`'s fixed snapshot, not `type(cfg[key])`:
  -- a nullable field that is presently nil (explicitly cleared) still has
  -- a declared type to enforce, same as before it was ever cleared.
  local expected = KNOWN_TYPES[key]
  if type(value) == expected then
    cfg[key] = value
  else
    notify.warn(
      ("LSP config update rejected: field '%s' expects %s, got %s"):format(
        key,
        expected,
        type(value)
      )
    )
  end
end

--- Set a single config field with strict typing.
---
--- Shares `apply_field` with `M.update` rather than assigning `cfg[key]`
--- directly (ERR-22: an invalid config VALUE must degrade to the field's
--- current/default value instead of crashing a downstream consumer). The
--- docstring here always claimed "strict typing", but the implementation
--- used to skip the check `apply_field` (then inlined in `M.update`) already
--- did -- a caller passing the wrong type for a numeric field (a realistic
--- slip: `set("center_width_frac", "0.5")` reads like the number but is a
--- string) reached `formatters.compact_breadcrumb_line`'s arithmetic on the
--- very next LSP-breadcrumbs statusline redraw and threw ("attempt to
--- perform arithmetic on a string value"), taking the whole segment down.
--- Going through `apply_field` rejects the mismatched field (keeping its
--- prior value) and emits the same `notify.warn` a batch patch would,
--- instead of corrupting live config state silently.
---@param key Ui.UI.Stl.Modules.Lsp.CfgKey
---@param value any
---@return nil
function M.set(key, value)
  apply_field(key, value)
end

--- Update multiple fields at once with runtime type checks.
--- Unknown keys are ignored (checked against `KNOWN_KEYS`, not against
--- whether `cfg[key]` currently happens to be non-nil -- a nullable field
--- that is presently nil is still a known key, see `KNOWN_KEYS`'s own doc
--- comment).
--- Type mismatches are rejected -- per field, not for the whole patch: a bad
--- field must not cost the other, valid fields in the same call (`pairs()`
--- order is unspecified, so a `return` here used to drop an arbitrary subset
--- of an otherwise-valid patch depending on hash order).
---
--- Unlike `M.set`, a batch patch cannot actually clear a field to nil: the
--- `patch` table this receives is itself a Lua table, built by the caller
--- before this function ever runs -- `M.update({ path_max_chars = nil })`
--- never puts `path_max_chars` in `patch` to begin with, for the exact
--- table-constructor reason `apply_field`'s own doc comment explains. Use
--- `M.set(key, nil)` to clear a single nullable field instead.
---@param patch table<string, any>
function M.update(patch)
  for key, value in pairs(patch) do
    apply_field(key, value)
  end
end

---@type Ui.UI.Stl.Modules.LSP.Cfg.Module
return M
