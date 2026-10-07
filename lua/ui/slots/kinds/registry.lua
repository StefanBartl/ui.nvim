---@module 'ui.slots.kinds.registry'
--- The kinds a slot can be: one table per kind with the behaviour behind a
--- slot's `kind` field. `file`, `yank` and `url` ship with the plugin and are
--- loaded on first use (requiring this module registers nothing); a host adds
--- its own with `register()` or `setup({ kinds = { name = kind } })`.
---
--- A kind is:
---
---   * `apply(slot, ctx)` -- required; returns `true`, or `false, err`;
---   * `validate(slot)` -- optional; returns an error string, or nil;
---   * `render(slot)` -- optional; `{ label?, icon?, hl?, missing? }` for the
---     views (the slot's own `label`/`icon` always win);
---   * `preview(slot, ctx)` -- optional, used by the preview pane;
---   * `persist` -- optional boolean; `true` lets a data file hold slots of
---     this kind, in addition to the config's `persistable_kinds`. Leave it
---     unset for anything that runs code: those slots come from `setup()`.
---
--- `apply()` here is the one entry point everything else calls: it checks the
--- slot, builds the placeholder context, and turns an error raised inside a
--- kind into `false, err` so one bad kind cannot take a view down with it.

require("ui.slots.@types")

local resolve = require("ui.slots.resolve")

local M = {}

local BUILTIN = { "file", "yank", "url" }

---@type table<string, Ui.Slots.Kind>
local kinds = {}
local builtin_loaded = false

local function ensure_builtins()
  if builtin_loaded then
    return
  end
  builtin_loaded = true
  for _, name in ipairs(BUILTIN) do
    local ok, kind = pcall(require, "ui.slots.kinds." .. name)
    if ok and kinds[name] == nil then
      kinds[name] = kind
    end
  end
end

---@param kind any
---@return string|nil err
local function check_kind(kind)
  if type(kind) ~= "table" then
    return "a kind is a table"
  end
  if type(kind.apply) ~= "function" then
    return "a kind needs an apply function"
  end
  for _, field in ipairs({ "validate", "render", "preview" }) do
    if kind[field] ~= nil and type(kind[field]) ~= "function" then
      return ("kind.%s must be a function"):format(field)
    end
  end
  if kind.persist ~= nil and type(kind.persist) ~= "boolean" then
    return "kind.persist must be a boolean"
  end
  return nil
end

--- Register a kind.
---@param name string
---@param kind Ui.Slots.Kind
---@param opts { force?: boolean }|nil  # `force` replaces a kind of the same name
---@return boolean ok
---@return string|nil err
function M.register(name, kind, opts)
  if type(name) ~= "string" or not name:match("^[%w_%-]+$") then
    return false, "a kind name is letters, digits, '_' and '-'"
  end
  local err = check_kind(kind)
  if err then
    return false, err
  end
  ensure_builtins()
  if kinds[name] and not (opts and opts.force) then
    return false, ("kind '%s' is already registered"):format(name)
  end
  kinds[name] = kind
  return true
end

--- Register a name -> kind table (the `kinds` option). Replaces what is there.
---@param map table<string, Ui.Slots.Kind>|nil
---@return string[] errors  # one line per kind that was refused
function M.load(map)
  local errors = {}
  for name, kind in pairs(map or {}) do
    local ok, err = M.register(name, kind, { force = true })
    if not ok then
      errors[#errors + 1] = ("kinds.%s: %s"):format(tostring(name), err)
    end
  end
  return errors
end

---@param name string
---@return boolean removed
function M.unregister(name)
  ensure_builtins()
  local had = kinds[name] ~= nil
  kinds[name] = nil
  return had
end

---@param name string
---@return Ui.Slots.Kind|nil
function M.get(name)
  ensure_builtins()
  return kinds[name]
end

---@return string[]
function M.names()
  ensure_builtins()
  local names = vim.tbl_keys(kinds)
  table.sort(names)
  return names
end

--- Does the kind itself ask to be written to a data file?
---@param name string
---@return boolean
function M.persists(name)
  local kind = M.get(name)
  return kind ~= nil and kind.persist == true
end

--- Forget every registration; the built-in kinds load again on next use.
function M.reset()
  kinds = {}
  builtin_loaded = false
end

--- What is wrong with `slot` for its kind, or nil.
---@param slot table
---@return string|nil err
function M.validate(slot)
  if type(slot) ~= "table" or type(slot.kind) ~= "string" then
    return "a slot needs a kind"
  end
  local kind = M.get(slot.kind)
  if not kind then
    return ("unknown kind '%s'"):format(slot.kind)
  end
  if kind.validate then
    local ok, err = pcall(kind.validate, slot)
    if not ok then
      return ("validate raised: %s"):format(tostring(err))
    end
    return err
  end
  return nil
end

--- Run a slot.
---@param slot table
---@param ctx { count?: integer, resolve?: Ui.Slots.Ctx }|nil
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  local err = M.validate(slot)
  if err then
    return false, err
  end
  ctx = ctx or {}
  ctx.resolve = ctx.resolve or resolve.context(ctx.count)
  local kind = M.get(slot.kind)
  local ok, res, apply_err = pcall(kind.apply, slot, ctx)
  if not ok then
    return false, tostring(res)
  end
  -- `false, err` and `nil, err` both say no; a bare `nil` means "done".
  if res == false or (res == nil and apply_err ~= nil) then
    return false, apply_err or "the slot could not be applied"
  end
  return true
end

--- How a view draws a slot: the kind's answer with the slot's own `label` and
--- `icon` on top, and a fallback for a kind that is not registered.
---@param slot table
---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(slot)
  local kind = M.get(slot.kind)
  local r = {}
  if kind and kind.render then
    local ok, res = pcall(kind.render, slot)
    if ok and type(res) == "table" then
      r = res
    end
  end
  local unknown = kind == nil
  return {
    label = slot.label or r.label or tostring(slot.kind),
    icon = slot.icon or r.icon or (unknown and "?" or ""),
    hl = r.hl or (unknown and "KitError" or "KitMuted"),
    missing = unknown or r.missing == true,
  }
end

--- The text a slot stands for (its path, address or text), or nil plus a
--- reason when its kind has none.
---@param slot table
---@param ctx { count?: integer, resolve?: Ui.Slots.Ctx }|nil
---@return string|nil text
---@return string|nil err
function M.text(slot, ctx)
  local kind = M.get(slot.kind)
  if not kind then
    return nil, ("unknown kind '%s'"):format(tostring(slot.kind))
  end
  if not kind.text then
    return nil, ("a '%s' slot has nothing to copy"):format(slot.kind)
  end
  local err = M.validate(slot)
  if err then
    return nil, err
  end
  ctx = ctx or {}
  ctx.resolve = ctx.resolve or resolve.context(ctx.count)
  local ok, res = pcall(kind.text, slot, ctx)
  if not ok then
    return nil, tostring(res)
  end
  return res
end

--- The preview of a slot (kind-specific), or nil when its kind has none.
---@param slot table
---@param ctx table|nil
---@return table|nil
function M.preview(slot, ctx)
  local kind = M.get(slot.kind)
  if not (kind and kind.preview) then
    return nil
  end
  ctx = ctx or {}
  ctx.resolve = ctx.resolve or resolve.context(ctx.count)
  local ok, res = pcall(kind.preview, slot, ctx)
  if ok then
    return res
  end
  return nil
end

return M
