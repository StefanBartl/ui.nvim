---@module 'ui.slots.kinds.lua'
--- Kind `lua`: call a function. `{ kind = "lua", fn = function(ctx) ... end }`.
---
--- Only a real function is accepted -- never a string that would be compiled --
--- and a function cannot be written to a data file, so these slots come from
--- `setup()` or a host's own Lua. Whoever needs a shell writes one here.
---
--- The function gets a context table: `slot`, `n` and `count`, and every
--- placeholder name (`file`, `dir`, `root`, `cwd`, `line`, `col`, `word`, `sel`,
--- `clip`) read when asked for, so the clipboard is not touched unless used.
--- It runs protected: an error is reported and does not reach the caller; a
--- return of `false` (optionally with a message) counts as a failure.

local resolve = require("ui.slots.resolve")

local M = {}

---@param slot table
---@return string|nil
function M.validate(slot)
  if type(slot.fn) ~= "function" then
    return "a lua slot needs fn, a function (a string is not run)"
  end
  return nil
end

--- The context handed to the function.
---@param slot table
---@param rctx Ui.Slots.Ctx
---@return table
local function context(slot, rctx)
  return setmetatable({ slot = slot, n = slot.n }, {
    __index = function(_, key)
      local v = rctx[key]
      if type(v) == "function" then
        local ok, res = pcall(v)
        return ok and res or nil
      end
      return v
    end,
  })
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  local ok, res, err = pcall(slot.fn, context(slot, ctx.resolve or resolve.context()))
  if not ok then
    return false, tostring(res)
  end
  if res == false or (res == nil and type(err) == "string") then
    return false, type(err) == "string" and err or "the function returned false"
  end
  return true
end

---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(_)
  return { label = "lua", icon = "󰢱", hl = "KitAccent", missing = false }
end

return M
