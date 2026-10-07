---@module 'ui.slots.view.editor'
--- Add or change one slot in a `ui.kit.sheet`: the fields of its kind, then the
--- ones every slot has (label, icon, style) and its number.
---
--- Which kinds the editor makes: only those a data file may hold
--- (`persistable_kinds`, or a kind with `persist = true`) and that it has fields
--- for -- `file`, `url`, `yank`, `mark`. A `cmd` or `lua` slot runs code, comes
--- from `setup()` or a host's Lua and is not made or changed here; a fixed slot
--- (from `setup({ slots })`) cannot be changed by anything but its config.
---
--- Validation is the kind's own: each field is checked through
--- `registry.validate` on a slot made of just that field, and the finished slot
--- once more on submit.

require("ui.slots.@types")

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local store = require("ui.slots.store")
local util = require("ui.slots.util")

local M = {}

--- The fields each editable kind has of its own.
---@type table<string, { name: string, label: string, kind?: string, choices?: string[], required?: boolean, completion?: string }[]>
local FIELDS = {
  file = {
    { name = "path", label = "Path", required = true, completion = "file" },
    {
      name = "target",
      label = "Open in",
      kind = "select",
      choices = { "current", "split", "vsplit", "tab" },
    },
  },
  url = {
    { name = "url", label = "Address", required = true },
  },
  yank = {
    { name = "text", label = "Text", required = true },
    { name = "register", label = "Register" },
  },
  mark = {
    { name = "index", label = "Mark number", required = true },
  },
}

local STYLES = { "(default)", "rounded", "double", "ascii", "solid", "minimal" }

--- Kinds the editor can make, in a stable order.
---@return string[]
function M.kinds()
  local out = {}
  for _, name in ipairs({ "file", "url", "yank", "mark" }) do
    local persists = vim.tbl_contains(config.get().persistable_kinds, name)
      or registry.persists(name)
    if FIELDS[name] and registry.get(name) and persists then
      out[#out + 1] = name
    end
  end
  return out
end

--- Why `slot` cannot be changed in the editor, or nil.
---@param n integer
---@return string|nil
function M.refusal(n)
  local slot = store.get(n)
  if not slot then
    return ("slot %d is empty"):format(n)
  end
  if slot.fixed then
    return ("slot %d is fixed in setup() and cannot be changed here"):format(n)
  end
  if not FIELDS[slot.kind] or not vim.tbl_contains(M.kinds(), slot.kind) then
    return ("a '%s' slot is made in setup() or in Lua and cannot be changed here"):format(slot.kind)
  end
  return nil
end

---@param name string
---@param value string
---@return any
local function coerce(name, value)
  if name == "index" then
    return tonumber(value) or value
  end
  return value
end

--- The slot a set of answers describes.
---@param kind string
---@param values table<string, string>
---@return table
function M.build(kind, values)
  local slot = { kind = kind }
  for _, f in ipairs(FIELDS[kind] or {}) do
    local v = vim.trim(values[f.name] or "")
    if v ~= "" then
      slot[f.name] = coerce(f.name, v)
    end
  end
  for _, name in ipairs({ "label", "icon" }) do
    local v = vim.trim(values[name] or "")
    if v ~= "" then
      slot[name] = v
    end
  end
  local style = values.style
  if style and style ~= "" and style ~= STYLES[1] then
    slot.style = style
  end
  return slot
end

--- A field's check: the kind's own validate on a slot of just this field.
---@param kind string
---@param name string
---@return fun(value: string): boolean, string|nil
local function field_check(kind, name)
  return function(value)
    local probe = { kind = kind }
    -- the other required fields are not asked here
    for _, f in ipairs(FIELDS[kind] or {}) do
      if f.required and f.name ~= name then
        probe[f.name] = (f.name == "index") and 1 or "x"
      end
    end
    probe[name] = coerce(name, vim.trim(value))
    local err = registry.validate(probe)
    if err then
      return false, err
    end
    return true
  end
end

---@param kind string
---@param slot table|nil   # the slot being changed
---@param n integer|nil
---@param defaults table|nil
---@return table[] fields
local function sheet_fields(kind, slot, n, defaults)
  local cfg = config.get()
  local fields = {}
  for _, f in ipairs(FIELDS[kind]) do
    local field = vim.deepcopy(f)
    field.validate = field_check(kind, f.name)
    local current = slot and slot[f.name]
    if current ~= nil then
      field.default = tostring(current)
    elseif defaults and defaults[f.name] ~= nil then
      field.default = tostring(defaults[f.name])
    elseif f.name == "target" then
      field.default = cfg.target
    end
    fields[#fields + 1] = field
  end
  fields[#fields + 1] = { name = "label", label = "Label", default = slot and slot.label or nil }
  fields[#fields + 1] = { name = "icon", label = "Icon", default = slot and slot.icon or nil }
  local styles = vim.deepcopy(STYLES)
  fields[#fields + 1] = {
    name = "style",
    label = "Style",
    kind = "select",
    choices = styles,
    default = (slot and type(slot.style) == "string" and vim.tbl_contains(styles, slot.style))
        and slot.style
      or styles[1],
  }
  fields[#fields + 1] = {
    name = "number",
    label = "Number",
    required = true,
    default = tostring(n or store.next_free()),
    validate = function(value)
      local num = tonumber(value)
      if not num or num ~= math.floor(num) or num < 1 or num > config.MAX_N then
        return false, ("a whole number from 1 to %d"):format(config.MAX_N)
      end
      if num ~= n and store.get(num) then
        return false, ("slot %d is taken"):format(num)
      end
      return true
    end,
  }
  return fields
end

--- Save what the sheet answered.
---@param kind string
---@param values table<string, string>
---@param n integer|nil   # the slot being changed, nil when adding
---@return integer|nil number
---@return string|nil err
function M.save(kind, values, n)
  local slot = M.build(kind, values)
  local err = registry.validate(slot)
  if err then
    return nil, err
  end
  -- Changing the slot of a file keeps where the cursor was in it.
  local old = n and store.get(n) or nil
  if old and old.kind == "file" and slot.kind == "file" and old.path == slot.path then
    slot.line, slot.col = old.line, old.col
  end
  local target = tonumber(values.number) or n or store.next_free()
  if n and target ~= n then
    -- A new number is a move: the old one is freed only if the new one is taken.
    local ok_set, set_err = store.set(target, slot)
    if not ok_set then
      return nil, set_err
    end
    store.clear(n)
    return target
  end
  local ok, set_err
  if n then
    ok, set_err = store.set(n, slot)
  else
    ok, set_err = store.set(target, slot)
  end
  if not ok then
    return nil, set_err
  end
  return target
end

--- Open the sheet for `kind`.
---@param kind string
---@param opts { n?: integer, defaults?: table, on_close?: fun(n: integer|nil) }
local function open_sheet(kind, opts)
  local slot = opts.n and store.get(opts.n) or nil
  local done = false
  local function finish(n)
    if done then
      return
    end
    done = true
    if opts.on_close then
      opts.on_close(n)
    end
  end
  local sheet = require("ui.kit.sheet").open({
    title = opts.n and ("Slot %d (%s)"):format(opts.n, kind) or ("New %s slot"):format(kind),
    fields = sheet_fields(kind, slot, opts.n, opts.defaults),
    width = 64,
    on_submit = function(values)
      local num, err = M.save(kind, values, opts.n)
      if not num then
        util.notify(err or "the slot could not be saved")
      end
      finish(num)
    end,
    on_cancel = function()
      finish(nil)
    end,
  })
  if not sheet then
    util.notify("the editor could not be opened")
    finish(nil)
  end
end

--- Add a slot (`opts.n` nil) or change slot `opts.n`.
---@param opts { n?: integer, kind?: string, defaults?: table, on_close?: fun(n: integer|nil) }|nil
function M.open(opts)
  opts = opts or {}
  if opts.n then
    local why = M.refusal(opts.n)
    if why then
      util.notify(why)
      if opts.on_close then
        opts.on_close(nil)
      end
      return
    end
    return open_sheet(store.get(opts.n).kind, opts)
  end

  local kinds = M.kinds()
  if opts.kind then
    if not vim.tbl_contains(kinds, opts.kind) then
      util.notify(("the editor makes no '%s' slots"):format(opts.kind))
      if opts.on_close then
        opts.on_close(nil)
      end
      return
    end
    return open_sheet(opts.kind, opts)
  end
  if #kinds == 0 then
    util.notify("no kind to make a slot of")
    if opts.on_close then
      opts.on_close(nil)
    end
    return
  end
  require("ui.kit.select").open({
    title = "Kind of slot",
    items = kinds,
    on_select = function(kind)
      open_sheet(kind, opts)
    end,
    on_cancel = function()
      if opts.on_close then
        opts.on_close(nil)
      end
    end,
  })
end

return M
