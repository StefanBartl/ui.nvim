---@module 'ui.tabline.layout'
--- Where the buffer chips sit on the tabline row, for the one thing that
--- cannot be answered from a click handler: "which chip is under this screen
--- column?" during a drag, where Neovim only reports mouse positions (a
--- `%N@Func@` click region fires on the press, never on drag or release).
---
--- `ui.tabline.modules.buffers` calls `record()` on every render with what it
--- just drew -- the final, style-decorated chip strings and the tabline text
--- to their left. Nothing is measured at record time: a redraw happens far more
--- often than a drag, so widths are only computed when `slot_at()` is asked,
--- via `nvim_eval_statusline` (the `%#Group#`/`%N@Func@...%X` markup counts as
--- the zero-width directives it is, which `strdisplaywidth` would get wrong).

local api = vim.api

local M = {}

---@class Ui.Tabline.Layout
---@field prefix string     # rendered tabline text left of the first chip (the tree offset)
---@field bufs integer[]    # buffer of each visible chip, left to right
---@field chips string[]    # the chip strings, parallel to `bufs`
---@field bounds? integer[] # {left, right} from `chip_run_bounds()`, memoized lazily -- see that function's own comment

---@type Ui.Tabline.Layout|nil
local last = nil

--- Remember what `ui.tabline.modules.buffers` just rendered.
---@param prefix string
---@param bufs integer[]
---@param chips string[]
---@return nil
function M.record(prefix, bufs, chips)
  last = { prefix = prefix, bufs = bufs, chips = chips }
end

--- The layout `record()` last stored, or nil before the first render.
---@return Ui.Tabline.Layout|nil
function M.current()
  return last
end

---@param str string
---@return integer
local function width_of(str)
  if str == "" then
    return 0
  end
  return api.nvim_eval_statusline(str, { use_tabline = true }).width
end

--- The chip a 1-based screen column falls on. A column left of the first chip
--- resolves to the first, right of the last to the last: a drag that overshoots
--- either end of the bar should mean "all the way there", not "nowhere".
---@param col integer # 1-based screen column, as `getmousepos().screencol`
---@return integer|nil bufnr # nil when no chip has been rendered yet
---@return integer|nil slot  # 1-based position among the visible chips
function M.slot_at(col)
  if not last or #last.bufs == 0 then
    return nil, nil
  end

  local right_edge = width_of(last.prefix)
  if col <= right_edge then
    return last.bufs[1], 1
  end

  for slot, chip in ipairs(last.chips) do
    right_edge = right_edge + width_of(chip)
    if col <= right_edge then
      return last.bufs[slot], slot
    end
  end

  return last.bufs[#last.bufs], #last.bufs
end

--- The screen-column bounds of the rendered chip run: `left` is the first
--- column of the first chip, `right` the last column of the last one. `nil`
--- before the first render, or once every chip has been dropped (an empty
--- `vim.t.bufs`). `ui.tabline.scroll` uses this to tell "the pointer is
--- resting against this edge, during a drag" from "it is still well inside
--- the bar".
---
--- Memoized on `last` itself, computed at most once per `record()` (i.e.
--- once per actual tabline redraw): `ui.tabline.scroll.on_drag` calls this
--- on every single `<LeftDrag>` mouse event, which during a real drag fires
--- many times a second, and `record()` is NOT called again just because the
--- pointer moved without crossing into a new chip slot -- summing every
--- chip's `nvim_eval_statusline` width from scratch on every one of those
--- events would repeat the exact same work for as long as the hold lasts.
---@return integer|nil left
---@return integer|nil right
function M.chip_run_bounds()
  if not last or #last.bufs == 0 then
    return nil, nil
  end

  if not last.bounds then
    local left = width_of(last.prefix) + 1
    local right = left - 1
    for _, chip in ipairs(last.chips) do
      right = right + width_of(chip)
    end
    last.bounds = { left, right }
  end

  return last.bounds[1], last.bounds[2]
end

return M
