---@module 'ui.statusline.cursor_ctl.progress_calculators'
--- Row/column percentage for `cursor_ctl`'s progress modes -- current line vs.
--- buffer line count, current column vs. line width, both clamped to
--- 0-100 and nil on an unreadable buffer/window.

local M = {}

--- Compute row percentage based on cursor line and total buffer lines.
--- @return integer|nil
function M.compute_row_pct()
  local ok_cur, cursor = pcall(vim.api.nvim_win_get_cursor, 0)
  local ok_cnt, total = pcall(vim.api.nvim_buf_line_count, 0)
  if not ok_cur or not ok_cnt or not cursor or not total or total < 1 then
    return nil
  end
  local line = cursor[1]
  if total == 1 then
    return 100
  end
  local pct = math.floor(((line - 1) / (total - 1)) * 100 + 0.5)
  if pct < 0 then
    pct = 0
  elseif pct > 100 then
    pct = 100
  end
  return pct
end

--- Compute column percentage using visual screen columns (virtcol).
--- This reflects what the user sees (tabs, wide chars) and avoids encoding APIs.
--- @return integer|nil
function M.compute_col_pct()
  -- Safe cursor retrieval
  local ok_cur, _ = pcall(vim.api.nvim_win_get_cursor, 0)
  if not ok_cur then
    return nil
  end

  -- virtcol('.') is 1-based visual column at cursor; virtcol('$') is last visual col on the line
  local ok_curvc, cur_vc = pcall(vim.fn.virtcol, ".")
  local ok_endvc, end_vc = pcall(vim.fn.virtcol, "$")
  if not ok_curvc or not ok_endvc or type(cur_vc) ~= "number" or type(end_vc) ~= "number" then
    return nil
  end

  if end_vc <= 1 then
    -- Empty line or single visual cell: treat as 100% to avoid division by zero.
    return 100
  end

  -- Normalize to [0,100], using 0-based numerator (cur_vc - 1) vs (end_vc - 1)
  local pct = math.floor(((cur_vc - 1) / (end_vc - 1)) * 100 + 0.5)
  if pct < 0 then
    pct = 0
  elseif pct > 100 then
    pct = 100
  end
  return pct
end

return M
