---@module 'ui.slots.kinds.cmd'
--- Kind `cmd`: run an Ex command with fixed arguments.
--- `{ kind = "cmd", cmd = "Telescope", args = "live_grep cwd={cwd}" }`.
---
--- Code runs from a slot of this kind, so it is never read from the data file
--- (`persistable_kinds` does not list it): a `cmd` slot comes from `setup()` or
--- from a host's own Lua.
---
--- A value that a placeholder puts in (`{clip}`, `{sel}`, a file name) is text
--- from outside the slot's author, and the Ex line it ends up in has more syntax
--- than any one layer of escaping covers. So this kind does not try to quote it,
--- it refuses what is dangerous and says so (fail closed):
---
---   * a value with `|` (a second command in a user command that pastes its raw
---     `<args>`) or a backtick (`:argadd`, `:args`, `:next` run a shell for it);
---   * a value that starts the argument with `+` (`:edit +cmd file` runs `cmd`)
---     or `!` (`:read !cmd`);
---   * a control character becomes a space (a newline would end the line).
---
--- Set `raw_values = true` on a slot to take values as they are, when the command
--- is one that reads `<q-args>`/`<f-args>` and so is safe against all of this.
---
--- The line is built as follows: `args` is split into words BEFORE the
--- placeholders go in, a list (`args = { "a b", "c" }`) is taken as it is, and
--- the command runs through `nvim_cmd` with `magic = { bar = false, file = false }`
--- (`|`, `%`, `#` and wildcards in an argument are not expanded by it). How a
--- command splits an argument further (`:set`, `:args` split on spaces
--- themselves) is that command's business; where it matters, use a `lua` slot.
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

--- The argument list with the placeholders put in; empty results are dropped.
--- `problems` lists the values that were refused (see the header).
---@param slot table
---@param rctx Ui.Slots.Ctx|nil
---@return string[] args
---@return string[] unknown
---@return string[] problems
local function build(slot, rctx)
  local args, unknown_all, problems = {}, {}, {}
  for _, template in ipairs(templates(slot)) do
    -- Does a placeholder start this argument? Then its value is what `+`/`!`
    -- would act on.
    local leads = template:find("^{%w+}") ~= nil
    local first = true
    local value, unknown = resolve.resolve(template, rctx, {
      escape = function(v, name)
        local at_start = first and leads
        first = false
        v = v:gsub("%c", " ")
        if not slot.raw_values then
          if v:find("|", 1, true) or v:find("`", 1, true) then
            problems[#problems + 1] = ("the value of {%s} has a | or a backtick"):format(name)
          elseif at_start and v:match("^%s*[+!]") then
            problems[#problems + 1] = ("the value of {%s} starts with %s"):format(
              name,
              v:match("[+!]")
            )
          end
        end
        return v
      end,
    })
    vim.list_extend(unknown_all, unknown)
    if value ~= "" then
      args[#args + 1] = value
    end
  end
  return args, unknown_all, problems
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
  if slot.raw_values ~= nil and type(slot.raw_values) ~= "boolean" then
    return "raw_values must be true or false"
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
  local args, unknown, problems = build(slot, ctx.resolve)
  util.warn_unknown(unknown, "cmd slot")
  if #problems > 0 then
    return false,
      ("refused, %s (set raw_values = true if :%s reads <q-args>)"):format(
        table.concat(problems, "; "),
        slot.cmd
      )
  end
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
