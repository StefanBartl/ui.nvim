---@module 'ui.slots.kinds.mark'
--- Kind `mark`: the n-th entry of the mark list of `sessions.nvim`.
--- `{ kind = "mark", index = 2 }`.
---
--- Only the index is kept; the path and the cursor position come from
--- `sessions.marks` when the slot runs, so the two never disagree. The marks
--- open in the current window (their own `select`), whatever `target` says.
--- Without sessions.nvim the slot is shown as missing and says why when run.

local M = {}

--- The marks module, or nil plus the reason.
---@return table|nil marks
---@return string|nil err
local function marks()
  local ok, mod = pcall(require, "sessions.marks")
  if not ok then
    -- Not there at all is one thing; installed but broken is another, and the
    -- reason must not be thrown away.
    if tostring(mod):find("module 'sessions.marks' not found", 1, true) then
      return nil, "sessions.nvim is not installed"
    end
    return nil, "sessions.marks failed to load: " .. tostring(mod):match("[^\n]*")
  end
  if type(mod) ~= "table" then
    return nil, "sessions.nvim is not installed"
  end
  return mod
end

---@param slot table
---@return string|nil
function M.validate(slot)
  local i = slot.index
  if type(i) ~= "number" or i < 1 or i ~= math.floor(i) then
    return "a mark slot needs index, a positive whole number"
  end
  return nil
end

--- The mark behind the slot, or nil plus why not.
---@param slot table
---@return table|nil item
---@return string|nil err
local function item(slot)
  local mod, err = marks()
  if not mod then
    return nil, err
  end
  local list = mod.list()
  local it = list[slot.index]
  if not it then
    return nil, ("no mark at %d (%d listed)"):format(slot.index, #list)
  end
  return it
end

---@param slot table
---@return boolean ok
---@return string|nil err
function M.apply(slot)
  local mod, err = marks()
  if not mod then
    return false, err
  end
  return mod.select(slot.index)
end

---@param slot table
---@return string
function M.text(slot)
  local it, err = item(slot)
  if not it then
    error(err, 0)
  end
  return it.path
end

---@param slot table
---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(slot, opts)
  if opts and opts.cheap then
    -- The list of marks is read from disk: not for a row that is not in view.
    return { label = ("mark %s"):format(tostring(slot.index)), icon = "󰃀", hl = "KitAccent" }
  end
  local it = item(slot)
  if not it then
    return {
      label = ("mark %s"):format(tostring(slot.index)),
      icon = "󰃀",
      hl = "KitMuted",
      missing = true,
    }
  end
  local mod = marks() or {}
  local ok, label = pcall(mod.label, it.path)
  return {
    label = ok and label or vim.fs.basename(it.path),
    icon = "󰃀",
    hl = "KitAccent",
    missing = vim.uv.fs_stat(it.path) == nil,
  }
end

---@param slot table
---@return Ui.Slots.Preview|nil
function M.preview(slot)
  local it, err = item(slot)
  if not it then
    return { lines = { err or "" } }
  end
  return { lines = { it.path } }
end

return M
