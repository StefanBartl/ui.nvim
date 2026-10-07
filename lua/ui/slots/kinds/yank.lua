---@module 'ui.slots.kinds.yank'
--- Kind `yank`: put text into the clipboard registers.
--- `{ kind = "yank", text = "git rebase -i HEAD~{count}" }`.
---
--- The text may hold placeholders. It goes into every register of the config's
--- `clipboard` (`+`, `*` and `"` by default) -- or only into the slot's own
--- one-character `register`. A register that refuses (no clipboard provider
--- for `+`) is skipped; the slot fails only when none took it.

local config = require("ui.slots.config")
local resolve = require("ui.slots.resolve")
local util = require("ui.slots.util")

local M = {}

---@param slot table
---@return string|nil
function M.validate(slot)
  if type(slot.text) ~= "string" then
    return "a yank slot needs a text"
  end
  if slot.register ~= nil and (type(slot.register) ~= "string" or #slot.register ~= 1) then
    return "register must be a one-character register name"
  end
  return nil
end

--- Write `text` into the registers (the config's `clipboard` unless given).
--- A register that refuses is skipped; fails only when none took it.
---@param text string
---@param registers string[]|nil
---@return boolean ok
---@return string|nil err
function M.put(text, registers)
  local done = {}
  for _, reg in ipairs(registers or config.get().clipboard) do
    if pcall(vim.fn.setreg, reg, text) then
      done[#done + 1] = reg
    end
  end
  if #done == 0 then
    return false, "no register took the text"
  end
  util.notify(
    ("copied %d characters to %s"):format(vim.fn.strchars(text), table.concat(done, " ")),
    vim.log.levels.INFO
  )
  return true
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return string
function M.text(slot, ctx)
  local text, unknown = resolve.resolve(slot.text, ctx.resolve)
  util.warn_unknown(unknown, "yank slot")
  return text
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  return M.put(M.text(slot, ctx), slot.register and { slot.register } or nil)
end

---@param slot table
---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(slot)
  local first = (slot.text or ""):gsub("%s+", " ")
  return {
    label = vim.fn.strcharpart(first, 0, 24),
    icon = "󰆏",
    hl = "KitMuted",
    missing = false,
  }
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return Ui.Slots.Preview
function M.preview(slot, ctx)
  local text = resolve.resolve(slot.text or "", ctx.resolve)
  return { lines = vim.split(text, "\n", { plain = true }) }
end

return M
