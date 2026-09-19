---@module 'ui.statusline.cursor_ctl'
--- Cursor-position statusline mode: classic/row/col/rows_cols/off, cycled by
--- `toggle_mode()` and read by whichever renderer the statusline module
--- picks per mode.

---@class ui.statusline.cursor_ctl : Ui.UI.Stl.CursorCtl.module
local cursor_ctl = {}

-- Module-internal, reached only through get_mode()/set_mode() -- a public
-- `cursor_ctl.mode` field sat right beside set_mode()'s five-name
-- whitelist, so a direct assignment bypassed validation entirely (PRIN-10).
---@type Ui.UI.Stl.CursorCtl.Progress.Mode
local mode = "row_progress"

--- Set mode explicitly (no-op on invalid input).
--- @param m Ui.UI.Stl.CursorCtl.Progress.Mode
--- @return nil
function cursor_ctl.set_mode(m)
  if
    m == "classic"
    or m == "row_progress"
    or m == "col_progress"
    or m == "rows_cols_progress"
    or m == "off"
  then
    mode = m
  end
end

--- Cycle through modes in a stable order.
--- @return Ui.UI.Stl.CursorCtl.Progress.Mode new_mode
function cursor_ctl.toggle_mode()
  local order = { "classic", "row_progress", "col_progress", "rows_cols_progress", "off" }
  local idx = 1
  for i, v in ipairs(order) do
    if v == mode then
      idx = i
      break
    end
  end
  idx = (idx % #order) + 1
  mode = order[idx]
  return mode
end

--- Get current mode.
--- @return Ui.UI.Stl.CursorCtl.Progress.Mode
function cursor_ctl.get_mode()
  return mode
end

return cursor_ctl
