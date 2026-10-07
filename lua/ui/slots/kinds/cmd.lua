---@module 'ui.slots.kinds.cmd'
--- Kind `cmd`: run an Ex command with fixed arguments.
--- `{ kind = "cmd", cmd = "Telescope", args = "live_grep cwd={cwd}" }`.
---
--- Code runs from a slot of this kind, so it is never read from the data file
--- (`persistable_kinds` does not list it): a `cmd` slot comes from `setup()` or
--- from a host's own Lua. Nothing here goes through a shell, and the arguments
--- are built so a placeholder cannot add more of them:
---
---   * `args` is split into words BEFORE the placeholders are put in, so a value
---     with spaces stays one argument; a list (`args = { "a b", "c" }`) is taken
---     as it is;
---   * a control character in a value (a newline from `{sel}`) becomes a space;
---   * `|` and `%` in an argument are plain text: the command is run through
---     `nvim_cmd` with `magic = { bar = false, file = false }`.
---
--- The command must exist when the slot runs, and an unknown placeholder in
--- `args` makes the slot invalid (so `:checkhealth` and `add` can say so).

local resolve = require("ui.slots.resolve")
local util = require("ui.slots.util")

local M = {}

--- The words of `args`: a string is split on whitespace, a list is kept.
---@param slot table
---@return string[]
local function templates(slot)
  local args = slot.args
  if args == nil or args == "" then
    return {}
  end
  if type(args) == "table" then
    return args
  end
  local out = {}
  for word in args:gmatch("%S+") do
    out[#out + 1] = word
  end
  return out
end

--- A value as one argument: control characters would end the command line.
---@param value string
---@return string
local function flatten(value)
  return (value:gsub("%c", " "))
end

--- The argument list with the placeholders put in; empty results are dropped.
---@param slot table
---@param rctx Ui.Slots.Ctx|nil
---@return string[] args
---@return string[] unknown
local function build(slot, rctx)
  local args, unknown_all = {}, {}
  for _, template in ipairs(templates(slot)) do
    local value, unknown = resolve.resolve(template, rctx, { escape = flatten })
    vim.list_extend(unknown_all, unknown)
    if value ~= "" then
      args[#args + 1] = value
    end
  end
  return args, unknown_all
end

---@param slot table
---@return string|nil
function M.validate(slot)
  if type(slot.cmd) ~= "string" or not slot.cmd:match("^%a%w*$") then
    return "a cmd slot needs the name of a command (letters and digits)"
  end
  if slot.bang ~= nil and type(slot.bang) ~= "boolean" then
    return "bang must be true or false"
  end
  local args = slot.args
  if args ~= nil and type(args) ~= "string" and type(args) ~= "table" then
    return "args is a string or a list of strings"
  end
  for _, template in ipairs(templates(slot)) do
    if type(template) ~= "string" then
      return "args is a string or a list of strings"
    end
    local unknown = resolve.unknown(template)
    if #unknown > 0 then
      return ("args: unknown placeholder {%s}"):format(unknown[1])
    end
  end
  return nil
end

--- The command line as text: `:Cmd arg arg`.
---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return string
function M.text(slot, ctx)
  local args = build(slot, ctx.resolve)
  return ":"
    .. slot.cmd
    .. (slot.bang and "!" or "")
    .. (#args > 0 and " " or "")
    .. table.concat(args, " ")
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  if vim.fn.exists(":" .. slot.cmd) == 0 then
    return false, ("no such command: :%s"):format(slot.cmd)
  end
  local args, unknown = build(slot, ctx.resolve)
  util.warn_unknown(unknown, "cmd slot")
  local ok, err = pcall(vim.cmd, {
    cmd = slot.cmd,
    args = args,
    bang = slot.bang == true or nil,
    magic = { file = false, bar = false },
  })
  if not ok then
    return false, tostring(err)
  end
  return true
end

---@param slot table
---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(slot)
  return {
    label = ":" .. tostring(slot.cmd),
    icon = "",
    hl = "KitAccent",
    missing = type(slot.cmd) ~= "string" or vim.fn.exists(":" .. slot.cmd) == 0,
  }
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return Ui.Slots.Preview
function M.preview(slot, ctx)
  return { lines = { M.text(slot, ctx) } }
end

return M
