---@module 'ui.tabline.drag'
--- Drag a buffer chip along the tabline to reorder it.
---
--- Neovim's tabline click protocol (`%N@Func@...%X`) reports the PRESS only:
--- no drag and no release ever reaches a click handler. Mouse drags do arrive
--- as `<LeftDrag>`/`<LeftRelease>` key events, though, so a press on a chip
--- (`ui.tabline.utils`' `GoToBuf` handler) calls `begin()`, which maps exactly
--- those two keys for the length of that one gesture and unmaps them again on
--- release. Nothing is bound between gestures: a permanent global `<LeftDrag>`
--- would sit in the way of every ordinary drag-select in every window, so the
--- mappings are transient by design, and any mapping they shadowed is put back.
---
--- While the button is held, each drag event over the tabline row asks
--- `ui.tabline.layout` which chip is under the pointer and moves the dragged
--- buffer into that chip's slot -- live, the bar re-lays itself out under the
--- pointer as it goes, so the drop needs no separate commit step.

local layout = require("ui.tabline.layout")
local state = require("ui.bindings.keymaps.tabufline.state")

local M = {}

-- Keys the gesture claims, and the modes to claim them in: normal, insert,
-- visual/select and terminal -- the modes a buffer chip can be pressed from.
local KEYS = { "<LeftDrag>", "<LeftRelease>" }
local MODES = { "n", "i", "v", "t" }

-- Safety net, not part of the gesture: a release Neovim never delivers (the
-- button let go outside the terminal window, a focus change mid-drag) would
-- otherwise leave both keys claimed. Re-armed by every drag event, so it only
-- fires once the pointer has been silent this long.
local IDLE_MS = 5000

---@class Ui.Tabline.DragState
---@field bufnr integer     # the buffer being dragged
---@field saved { mode: string, key: string, map: table }[] # global mappings this gesture shadowed
---@field timer? any        # the idle timer (a libuv handle); nil once stopped

---@type Ui.Tabline.DragState|nil
local active = nil

--- Whether a drag gesture is in flight. For tests.
---@return boolean
function M.is_active()
  return active ~= nil
end

--- The buffer being dragged, or nil.
---@return integer|nil
function M.dragged()
  return active and active.bufnr or nil
end

---@param drag Ui.Tabline.DragState
local function stop_timer(drag)
  local timer = drag.timer
  if timer then
    drag.timer = nil
    timer:stop()
    pcall(timer.close, timer)
  end
end

--- End the gesture: unmap both keys and restore whatever they shadowed.
--- Safe to call with no gesture running.
---@return nil
function M.cancel()
  local drag = active
  if not drag then
    return
  end
  active = nil
  stop_timer(drag)

  for _, mode in ipairs(MODES) do
    for _, key in ipairs(KEYS) do
      pcall(vim.keymap.del, mode, key)
    end
  end
  for _, prev in ipairs(drag.saved) do
    pcall(vim.fn.mapset, prev.mode, false, prev.map)
  end
end

--- (Re)start the idle timer that ends a gesture whose release never came.
---@param drag Ui.Tabline.DragState
local function arm_timer(drag)
  stop_timer(drag)
  local timer = vim.uv.new_timer()
  if not timer then
    return
  end
  drag.timer = timer
  timer:start(
    IDLE_MS,
    0,
    vim.schedule_wrap(function()
      if active == drag then
        M.cancel()
      end
    end)
  )
end

--- One `<LeftDrag>` event: move the dragged buffer into the slot under the
--- pointer. Off the tabline row (the pointer wandered down into a window) it
--- does nothing -- the gesture stays alive, so dragging back up carries on.
---@return nil
local function on_drag()
  local drag = active
  if not drag then
    return
  end
  arm_timer(drag)

  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or type(pos) ~= "table" or pos.screenrow ~= 1 then
    return
  end

  local target = layout.slot_at(pos.screencol)
  if not target or target == drag.bufnr then
    return
  end

  local dest = state.index_of(target)
  if dest then
    state.move_buf_to(drag.bufnr, dest)
  end
end

--- Start dragging `bufnr`. Called by the chip's press handler; a plain click
--- (press then release with no drag between) costs one map/unmap pair and
--- moves nothing.
---@param bufnr integer
---@return nil
function M.begin(bufnr)
  M.cancel() -- a previous gesture whose release was lost

  local drag = { bufnr = bufnr, saved = {} }
  active = drag

  for _, mode in ipairs(MODES) do
    for _, key in ipairs(KEYS) do
      -- Only a GLOBAL mapping is ours to shadow and restore; a buffer-local
      -- one wins over these anyway and is left untouched.
      local prev = vim.fn.maparg(key, mode, false, true)
      if type(prev) == "table" and next(prev) ~= nil and prev.buffer == 0 then
        drag.saved[#drag.saved + 1] = { mode = mode, key = key, map = prev }
      end

      vim.keymap.set(mode, key, key == "<LeftDrag>" and on_drag or M.cancel, {
        silent = true,
        desc = "ui.tabline: drag a tab",
      })
    end
  end

  arm_timer(drag)
end

return M
