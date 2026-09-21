---@module 'ui.tabline.scroll'
--- Auto-scroll during a tabline drag: holding the pointer at the left/right
--- edge of the buffer-chip run nudges the visible window one chip further
--- that way, on a timer -- the same "hold at the edge of a scrollable list"
--- gesture a long dropdown gives you. Needed because a drag can only re-slot
--- a chip that is actually on screen (`ui.tabline.layout.slot_at` only knows
--- about what got rendered), and more buffers can be open than the bar can
--- show at once.
---
--- The offset kept here is which UNPINNED buffer's index is first in the
--- visible window. `ui.tabline.modules.buffers()` reads it via `M.offset()`
--- and, while it is non-nil, renders exactly that window instead of its own
--- "keep the current buffer visible" sliding logic -- the dragged chip IS
--- the current buffer for the whole gesture, and letting that logic win
--- would snap the window straight back to it on every redraw, fighting the
--- very scroll this module exists to do. `ui.tabline.drag` drives this
--- (`M.on_drag` on every `<LeftDrag>`, `M.reset` when the gesture ends); it
--- is otherwise inert -- outside a drag, `M.offset()` is always nil.

local M = {}

-- How often a held edge nudges the window while the pointer stays there --
-- fast enough to feel responsive, slow enough that one chip's width does not
-- fly past before the drop.
local TICK_MS = 120
-- How many columns from either edge of the chip run count as "at the edge".
-- Roughly a third of the narrowest chip (MIN_BUFWIDTH in modules.lua) --
-- tight enough that merely approaching the edge does not already trigger it.
local EDGE_COLS = 3

---@type integer|nil
local offset = nil
---@type any # a libuv timer handle, nil when idle
local timer = nil
---@type -1|1|nil # which way `timer` is currently nudging
local timer_dir = nil

--- The current window override, or nil (default "keep current visible"
--- behaviour). For `ui.tabline.modules.buffers`.
---@return integer|nil
function M.offset()
  return offset
end

local function stop_timer()
  if timer then
    local t = timer
    timer = nil
    timer_dir = nil
    t:stop()
    pcall(t.close, t)
  end
end

--- Stop nudging and forget the window override. Called when a drag ends
--- (`ui.tabline.drag.cancel`, which also covers its own idle-timeout) and
--- from tests.
---@return nil
function M.reset()
  offset = nil
  stop_timer()
end

--- Buffers in the current tab that are not pinned -- `M.offset()` indexes
--- into this same set, so the clamp below has to count it the same way
--- `ui.tabline.modules.buffers` splits pinned/unpinned.
---@return integer
local function total_unpinned()
  local state = require("ui.bindings.keymaps.tabufline.state")
  local n = 0
  for _, b in ipairs(vim.t.bufs or {}) do
    if not state.is_pinned(b) then
      n = n + 1
    end
  end
  return n
end

---@param dir -1|1
local function nudge(dir)
  local total = total_unpinned()
  if total == 0 then
    return
  end
  local cur = offset or 0
  offset = math.min(math.max(cur + dir, 0), math.max(0, total - 1))
  pcall(vim.cmd.redrawtabline)
end

--- One `<LeftDrag>` event during a tabline drag: (re)arm or disarm the
--- edge-hold timer depending on where `col` (a screen column, as
--- `getmousepos().screencol` reports) sits relative to the rendered chip
--- run. Called from `ui.tabline.drag.on_drag`, ahead of its own re-slot
--- logic -- so the window can already be scrolling by the time the pointer
--- is close enough to a not-yet-visible chip to land on it.
---@param col integer
---@return nil
function M.on_drag(col)
  local left, right = require("ui.tabline.layout").chip_run_bounds()
  if not left then
    stop_timer()
    return
  end

  local dir = nil
  if col <= left + EDGE_COLS then
    dir = -1
  elseif col >= right - EDGE_COLS then
    dir = 1
  end

  if not dir then
    stop_timer()
    return
  end
  if timer_dir == dir then
    return -- already nudging this way
  end

  stop_timer()
  local uv_timer = vim.uv.new_timer()
  if not uv_timer then
    return
  end
  timer = uv_timer
  timer_dir = dir
  uv_timer:start(
    TICK_MS,
    TICK_MS,
    vim.schedule_wrap(function()
      -- `uv_timer:stop()` in `stop_timer()` only blocks FUTURE ticks -- a
      -- tick that had already fired (into this `vim.schedule_wrap` shim,
      -- which defers the real work to the next safe point on the main
      -- loop) is already queued and runs regardless. Without this guard, a
      -- drag ending (or redirecting) right after such a tick fired would
      -- still let one stray `nudge()` through afterwards, un-nil-ing
      -- `offset` right after `M.reset()` cleared it and leaving the
      -- tabline's "keep current buffer visible" logic silently overridden
      -- until the next drag. Same pattern `ui.tabline.drag`'s own idle
      -- timer already uses (`if active == drag then`).
      if timer == uv_timer then
        nudge(dir)
      end
    end)
  )
end

--- Whether the edge-hold timer is currently ticking. For tests.
---@return boolean
function M.is_active()
  return timer ~= nil
end

return M
