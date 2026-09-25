---@module 'ui.menu.selection'
--- The Visual selection a right-click menu acts on.
---
--- A menu entry runs AFTER the menu has closed, and by then Visual mode is
--- long over: `mode()` reports "n". Anything that asks "is there a selection?"
--- at click time therefore always answers no -- which is how "Copy Marked"
--- ended up copying the whole buffer. So the selection is snapshotted when the
--- menu is BUILT (while Visual mode is still live) and the entries act on the
--- snapshot.

local M = {}

---@class Ui.Menu.Selection
---@field buf integer
---@field mode string  "v", "V" or "\22" (blockwise)
---@field from integer[]  getpos()-style: the selection's fixed end
---@field to integer[]  getpos()-style: the cursor end

---@return boolean
local function in_visual()
  local mode = vim.fn.mode()
  return mode == "v" or mode == "V" or mode == "\22"
end

--- Snapshot the live Visual selection, or nil when there is none.
---@return Ui.Menu.Selection|nil
function M.snapshot()
  if not in_visual() then
    return nil
  end
  return {
    buf = vim.api.nvim_get_current_buf(),
    mode = vim.fn.mode(),
    from = vim.fn.getpos("v"),
    to = vim.fn.getpos("."),
  }
end

--- Whether `sel` can still be acted on: it exists and its buffer is current.
---@param sel Ui.Menu.Selection|nil
---@return boolean
function M.usable(sel)
  return sel ~= nil and vim.api.nvim_get_current_buf() == sel.buf
end

--- The selected text as `getregion` lines, plus the register type to store it as.
---@param sel Ui.Menu.Selection
---@return string[] lines
---@return string regtype
function M.text(sel)
  return vim.fn.getregion(sel.from, sel.to, { type = sel.mode }), sel.mode
end

--- Delete exactly the snapshotted region. `gv` reselects from the '< / '>
--- marks and the last Visual mode; both are restored from the snapshot first,
--- so a mark that moved in the meantime cannot change what is deleted.
---@param sel Ui.Menu.Selection
function M.delete(sel)
  local first, last = sel.from, sel.to
  if last[2] < first[2] or (last[2] == first[2] and last[3] < first[3]) then
    first, last = last, first
  end
  vim.fn.setpos("'<", first)
  vim.fn.setpos("'>", last)
  vim.cmd("normal! gvd")
end

--- Whether the mouse pointer sits inside the live Visual selection of the
--- current window (line range; for a single-line charwise selection also the
--- columns).
---@return boolean
function M.pointer_inside()
  if not in_visual() then
    return false
  end
  local ok, m = pcall(vim.fn.getmousepos)
  if not ok or type(m) ~= "table" or m.winid ~= vim.api.nvim_get_current_win() then
    return false
  end
  local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
  if a[2] > b[2] or (a[2] == b[2] and a[3] > b[3]) then
    a, b = b, a
  end
  if m.line < a[2] or m.line > b[2] then
    return false
  end
  if vim.fn.mode() == "v" and a[2] == b[2] then
    return m.column >= a[3] and m.column <= b[3]
  end
  return true
end

return M
