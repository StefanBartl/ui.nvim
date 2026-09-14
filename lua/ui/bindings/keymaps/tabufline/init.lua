---@module 'ui.bindings.keymaps.tabufline'
--- Custom buffer navigation without automatic centering.
---
--- `close_n_buffers()` used to reach into `nvchad.tabufline` for
--- `close_buffer()`; that and the `vim.t.bufs` bookkeeping every function
--- here depends on are now `ui.bindings.keymaps.tabufline.state`'s own code
--- -- see that module's doc comment for why the bookkeeping was the part
--- that actually mattered.

local notify = require("lib.nvim.notify").create("[ui.bindings.keymaps.tabufline]")
local state = require("ui.bindings.keymaps.tabufline.state")

local M = {}

local api = vim.api

---@nodiscard
---@param bufnr integer
---@return boolean
local function set_buf_no_center(bufnr)
  local ok, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
  if ok and is_valid then
    local ok2 = pcall(api.nvim_set_current_buf, bufnr)
    return ok2
  end
  return false
end

-- Index of the current buffer within the tab's buffer list
---@param bufnr integer
---@param bufs integer[]
---@return integer|nil
local function buf_index(bufnr, bufs)
  if not bufs then
    return nil
  end

  for i, b in ipairs(bufs) do
    if b == bufnr then
      return i
    end
  end
  return nil
end

---@nodiscard
---@return integer
local function cur_buf()
  local ok, bufnr = pcall(api.nvim_get_current_buf)
  return ok and bufnr or 0
end

---@return boolean
function M.next()
  -- IMPORTANT: read vim.t.bufs fresh on every call
  local bufs = vim.t.bufs
  if not bufs or #bufs == 0 then
    return false
  end

  local current = cur_buf()
  if current == 0 then
    return false
  end

  local idx = buf_index(current, bufs)
  if not idx then
    return set_buf_no_center(bufs[1])
  end

  local next_buf = (idx == #bufs) and bufs[1] or bufs[idx + 1]
  return set_buf_no_center(next_buf)
end

---@return boolean
function M.prev()
  -- IMPORTANT: read vim.t.bufs fresh on every call
  local bufs = vim.t.bufs
  if not bufs or #bufs == 0 then
    return false
  end

  local current = cur_buf()
  if current == 0 then
    return false
  end

  local idx = buf_index(current, bufs)
  if not idx then
    return set_buf_no_center(bufs[1])
  end

  local prev_buf = (idx == 1) and bufs[#bufs] or bufs[idx - 1]
  return set_buf_no_center(prev_buf)
end

---@param n integer
---@return boolean
function M.move_next_n(n)
  if type(n) ~= "number" or n < 1 then
    return false
  end

  local success = true
  for _ = 1, n do
    if not M.next() then
      success = false
      break
    end

    -- Force a redraw so NvChad refreshes vim.t.bufs before the next step
    vim.cmd("redraw")
  end
  return success
end

---@param n integer
---@return boolean
function M.move_prev_n(n)
  if type(n) ~= "number" or n < 1 then
    return false
  end

  local success = true
  for _ = 1, n do
    if not M.prev() then
      success = false
      break
    end

    -- Force a redraw so NvChad refreshes vim.t.bufs before the next step
    vim.cmd("redraw")
  end
  return success
end

--- Close the current buffer, and repeat `count` times.
---
--- `n == 1` (a plain, uncounted `<leader>bc`, by far the common case) goes
--- through `ui.tabline.utils.close_buffer()` -- flashed, then deferred --
--- so the keymap gets the same close-flash feedback the tabline's own "x"
--- button does. `n > 1` stays exactly as before, `state.close_buffer()`
--- called synchronously in a loop: each iteration depends on the previous
--- one having already landed on a new current buffer (`close_buffer()`'s own
--- `vim.cmd("b" .. neighbour)` before it deletes), which a deferred close
--- would break -- all `n` calls would fire against the same still-current
--- buffer before any of them actually closed it.
---@param n integer
---@return boolean
function M.close_n_buffers(n)
  if type(n) ~= "number" or n < 1 then
    return false
  end

  if n == 1 then
    local ok, err = pcall(require("ui.tabline.utils").close_buffer)
    if not ok then
      notify.warn("[ui.tabufline] close_buffer failed: " .. tostring(err))
      return false
    end
    return true
  end

  -- UI-01: ask once for the whole batch instead of letting the loop below
  -- pop `confirm bd`'s save-changes prompt once per modified buffer it
  -- happens to touch. `vim.t.bufs` is an upper-bound approximation of what
  -- `n` iterations of close-then-land-on-neighbour will visit -- accepting
  -- an occasional over-ask (confirming when the actually-touched buffers
  -- turn out unmodified) is preferable to precisely simulating the
  -- traversal just to decide whether to ask at all.
  local any_modified = false
  for _, bufnr in ipairs(vim.t.bufs or {}) do
    if state.__needs_close_confirm(bufnr) then
      any_modified = true
      break
    end
  end

  if any_modified then
    local choice = vim.fn.confirm("Discard changes in modified buffer(s)?", "&Yes\n&No", 2)
    if choice ~= 1 then
      return false
    end
  end

  local success = true

  for _ = 1, n do
    local ok, err = pcall(state.close_buffer, nil, true)
    if not ok then
      notify.warn("[ui.tabufline] close_buffer failed: " .. tostring(err))
      success = false
      break
    end

    -- Same here: redraw so vim.t.bufs (and any tabline reading it) refreshes.
    vim.cmd("redraw")
  end
  return success
end

return M
