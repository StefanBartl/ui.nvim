---@module 'ui.statusline.modules.showcmd.loc'
--- Owns `'showcmdloc'` for the `showcmd` segment: `"statusline"` while the
--- key `"showcmd"` is in the active statusline `order`, and the value from
--- before that again once it no longer is (variant switch without it, the
--- "Remove" entry of `ui.statusline.menu`, `ui.statusline.render.disable()`).
---
--- Two entry points, because the order can change in two ways:
---   * `apply(want)` -- immediate. `render.enable()`/`render.disable()` call
---     it: a variant switch is an ordinary command, not a redraw.
---   * `sync(order)` -- deferred. `render.render()` (the `'%!'` callback)
---     calls it on every redraw, which catches an `order` changed in place
---     (the menu's "Add module"/"Remove", a host editing its own config
---     table). It only compares two booleans per redraw; the option itself
---     is set from a `vim.schedule` callback, never while Neovim is in the
---     middle of evaluating the statusline.
---
--- Restoring leaves the option alone when something else changed it away
--- from `"statusline"` in the meantime -- that value is somebody's explicit
--- choice, not this module's leftover.

local M = {}

local KEY = "showcmd"

---@type boolean # true while this module holds 'showcmdloc' at "statusline"
local applied = false
---@type string|nil # 'showcmdloc' from before `applied` became true
local saved = nil
---@type boolean # the value the pending `vim.schedule` callback will apply
local desired = false
local pending = false

---@param order string[]|nil
---@return boolean
function M.wanted(order)
  for _, key in ipairs(order or {}) do
    if key == KEY then
      return true
    end
  end
  return false
end

--- Take or release `'showcmdloc'` right now.
---@param want boolean
---@return nil
function M.apply(want)
  desired = want
  if want and not applied then
    saved = vim.o.showcmdloc
    vim.o.showcmdloc = "statusline"
    applied = true
  elseif not want and applied then
    if vim.o.showcmdloc == "statusline" and saved ~= nil then
      vim.o.showcmdloc = saved
    end
    applied = false
    saved = nil
  end
end

--- Redraw-safe variant of `apply`: schedules the change when `order` no
--- longer matches what is applied, and does nothing otherwise.
---@param order string[]|nil
---@return nil
function M.sync(order)
  desired = M.wanted(order)
  if desired == applied or pending then
    return
  end
  pending = true
  vim.schedule(function()
    pending = false
    M.apply(desired)
  end)
end

--- For tests and `:checkhealth`.
---@return boolean applied, string|nil saved
function M.status()
  return applied, saved
end

return M
