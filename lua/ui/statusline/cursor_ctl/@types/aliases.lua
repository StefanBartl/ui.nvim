---@meta
---@module 'ui.statusline.cursor_ctl.@types'

-- Available modes:
--   "classic"            → show "Ln %l, Col %v", no extra progress
--   "row_progress"       → classic cursor + row progress percentage+bar
--   "col_progress"       → classic cursor + column progress percentage+bar
--   "rows_cols_progress" → classic cursor + both row and column progress
--   "off"                → hide cursor+progress segment entirely
---@alias Ui.UI.Stl.CursorCtl.Progress.Mode '"classic"'|'"row_progress"'|'"col_progress"'|'"rows_cols_progress"'|'"off"'

return {}
