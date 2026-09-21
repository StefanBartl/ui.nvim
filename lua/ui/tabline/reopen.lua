---@module 'ui.tabline.reopen'
--- A ring of recently closed file buffers -- "reopen closed tab", the
--- tabline's counterpart to a browser's Ctrl+Shift+T. `M.record()` is called
--- from `ui.bindings.keymaps.tabufline.state`'s own `BufDelete` autocmd
--- (see that module's doc comment for why the bookkeeping lives there);
--- this module only owns the ring itself and reopening from it.
---
--- Global for the session, not tab-local: closing a tab's last buffer and
--- reopening it from another tab is a reasonable thing to want, and `vim.t`
--- would make that impossible. `M.reopen()` always lands the file in the
--- CURRENT tab, at the slot it remembers from wherever it actually closed --
--- it does not jump tabs to find "the" original one, which may itself be
--- gone by the time this runs.

local api = vim.api

local M = {}

-- How many closed files to remember. Past this, "which one did I just
-- close" stops being something a user scans a list for by eye anyway.
local MAX_ENTRIES = 20

---@class Ui.Tabline.ClosedEntry
---@field path string      # absolute path
---@field cursor integer[] # {row, col}, from nvim_buf_get_mark(buf, '"')
---@field tabpage integer  # the tabpage handle it closed from (display only)
---@field slot integer     # its 1-based position in that tab's vim.t.bufs when it closed

---@type Ui.Tabline.ClosedEntry[]
local ring = {}

--- Whether `buf` is worth remembering: a real, readable file, not a
--- scratch/terminal/quickfix buffer -- the same filter the handover calls
--- for. `buftype == ""` rules out terminals and the quickfix list alike;
--- `filereadable` rules out `[No Name]` and anything already gone from disk
--- by the time it closes.
---@param buf integer
---@return string|nil path # nil when `buf` should not be recorded
local function real_file_path(buf)
  if vim.bo[buf].buftype ~= "" then
    return nil
  end
  local ok, path = pcall(api.nvim_buf_get_name, buf)
  if not ok or path == "" then
    return nil
  end
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return path
end

--- Record `buf` closing. Called from `state.lua`'s `BufDelete` handler while
--- the buffer (and its name/marks) still exists -- a no-op for anything
--- `real_file_path` rejects.
---@param buf integer
---@return nil
function M.record(buf)
  local path = real_file_path(buf)
  if not path then
    return
  end

  local bufs = vim.t.bufs or {}
  local slot = 1
  for i, b in ipairs(bufs) do
    if b == buf then
      slot = i
      break
    end
  end

  local ok, mark = pcall(api.nvim_buf_get_mark, buf, '"')
  local cursor = (ok and type(mark) == "table" and mark[1] and mark[1] > 0) and mark or { 1, 0 }

  -- The same path only once -- the newest close wins and jumps back to the
  -- front, same as a browser's own closed-tabs list.
  for i = #ring, 1, -1 do
    if ring[i].path == path then
      table.remove(ring, i)
    end
  end

  table.insert(ring, 1, {
    path = path,
    cursor = cursor,
    tabpage = api.nvim_get_current_tabpage(),
    slot = slot,
  })

  while #ring > MAX_ENTRIES do
    table.remove(ring)
  end
end

--- The ring, newest first. For the tab menu's "Reopen closed tab" submenu
--- and for tests; a copy, so a caller cannot mutate the ring by accident.
---@return Ui.Tabline.ClosedEntry[]
function M.list()
  return vim.deepcopy(ring)
end

---@return boolean
function M.has_any()
  return #ring > 0
end

--- Drop every remembered entry. For tests -- no shipped keymap/menu entry
--- clears the whole ring at once.
---@return nil
function M.clear()
  ring = {}
end

--- Reopen `entry` (the most recently closed file when nil): `:edit` its
--- path, restore the cursor, and place it back at its remembered slot in the
--- CURRENT tab -- or just switch to it if it is already open there. Removed
--- from the ring either way `entry` is found there.
---
--- Unsaved changes in the closed buffer do not come back -- only the file as
--- it sits on disk does; a file deleted since it closed reopens nothing and
--- notifies instead of raising.
---@param entry? Ui.Tabline.ClosedEntry
---@return boolean opened
function M.reopen(entry)
  entry = entry or ring[1]
  if not entry then
    return false
  end

  -- Matched by path, not table identity: `entry` is typically one of
  -- `M.list()`'s own results (the tab menu's submenu builds its entries
  -- from exactly that), and `M.list()` deep-copies -- an identity check
  -- would never find its match there. The ring only ever holds one entry
  -- per path (see `record`'s own dedup), so this is unambiguous.
  for i, e in ipairs(ring) do
    if e.path == entry.path then
      table.remove(ring, i)
      break
    end
  end

  local notify = require("lib.nvim.notify").create("[ui.tabline.reopen]")

  if vim.fn.filereadable(entry.path) ~= 1 then
    notify.warn("file no longer on disk: " .. entry.path)
    return false
  end

  local state = require("ui.bindings.keymaps.tabufline.state")

  -- Already open somewhere in this tab -- just switch to it rather than
  -- opening a second buffer for the same file.
  for _, b in ipairs(vim.t.bufs or {}) do
    if api.nvim_buf_is_valid(b) and api.nvim_buf_get_name(b) == entry.path then
      state.goto_buf(b)
      return true
    end
  end

  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(entry.path))
  if not ok then
    notify.warn("reopen failed: " .. tostring(err))
    return false
  end

  pcall(api.nvim_win_set_cursor, 0, {
    math.max(1, entry.cursor[1] or 1),
    entry.cursor[2] or 0,
  })

  state.move_buf_to(api.nvim_get_current_buf(), entry.slot)
  return true
end

return M
