---@module 'ui.tabline.modules'
--- The four built-in tabline segments -- `tree_offset`, `buffers`, `tabs`,
--- `btns` -- each `fun(cfg: Ui.Tabline.Config): string`, ported from
--- `nvchad.tabufline.modules`. Kept in one file rather than one per segment
--- (unlike the statusline's `modules/` tree): all four share `cfg` and
--- `available_space()`, and NvChad's own upstream keeps them together too.

local utils = require("ui.tabline.utils")
local api = vim.api

local M = {}

-- Bounds for the auto-computed chip width (`M.buffers` below) -- the elastic
-- range that lets the bar fill itself instead of leaving a leftover strip
-- too narrow for one more fixed-width chip. Below MIN_BUFWIDTH, more buffers
-- simply overflow (dropped from the front) exactly like a fixed-width bar
-- always has; the shrinking only happens inside this range.
local MIN_BUFWIDTH = 12
local MAX_BUFWIDTH = 24

---@param ft string
---@return integer # 0 when no window in the current tab has this filetype
local function filetree_window_width(ft)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(win)].filetype == ft then
      return api.nvim_win_get_width(win)
    end
  end
  return 0
end

--- Columns left over for buffer chips once every other module in `cfg.order`
--- has rendered -- "buffers" itself is skipped so it does not measure its
--- own, not-yet-decided width. Resolves `cfg.modules` overrides the same way
--- `ui.tabline.render.generate()` does, so a custom module in `order`
--- affects the space `buffers()` sees too.
---@param cfg Ui.Tabline.Config
---@return integer
local function available_space(cfg)
  local str = {}
  for _, key in ipairs(cfg.order or {}) do
    if key ~= "buffers" then
      local mod = (cfg.modules and cfg.modules[key]) or M[key]
      if type(mod) == "function" then
        local ok, rendered = pcall(mod, cfg)
        str[#str + 1] = ok and rendered or ""
      end
    end
  end

  local width = api.nvim_eval_statusline(table.concat(str), { use_tabline = true }).width
  return vim.o.columns - width
end

--- A blank strip the width of the file-tree window, so the buffer chips
--- start after it instead of drawing underneath -- `filetree.nvim`'s own
--- window by default (`cfg.tree_offset_ft`), any filetype otherwise.
---@param cfg Ui.Tabline.Config
---@return string
function M.tree_offset(cfg)
  local ft = cfg.tree_offset_ft or "filetree"
  local width = filetree_window_width(ft)
  if width == 0 then
    return ""
  end
  return "%#UiTbTreeOffset#" .. string.rep(" ", width) .. "%#UiTbFill#"
end

---@type table<string, true>
local VALID_STYLES = { rounded = true, square = true, divider = true }

--- Decorate chip boundaries per `style`, mutating `chips` in place:
---   "rounded" (default) -- a cap on every internal boundary. The first
---     chip's left edge is always square -- it sits directly against the
---     bar's own left edge (or `tree_offset`'s fill), never with slack in
---     between. The last chip's right edge is square only when `flush_right`
---     says the visible run actually reaches the space budget (buffers had
---     to be dropped to fit, or the auto-computed width used every column) --
---     otherwise `"%="` alignment leaves genuine empty space before
---     `tabs`/`btns`, and squaring an edge that isn't touching anything
---     reads as a cut corner rather than a frame. A single-chip run follows
---     the same two rules independently -- square on the left always, square
---     on the right only if flush.
---   "square" -- nothing added; chips sit flush, the look before this style
---     switch existed.
---   "divider" -- one plain vertical bar per internal boundary, no rounding.
--- An unrecognized style name falls back to "rounded" rather than silently
--- rendering unstyled -- same degrade-not-crash contract `get_separators()`
--- already uses for the statusline's own `separator_style`.
---@param chips string[]
---@param chip_bufs integer[] # parallel to `chips`
---@param cur integer # current buffer, for the rounded style's per-chip cap color
---@param style string|nil
---@param flush_right boolean # whether the visible run actually reaches the right edge of its budget
---@return nil
local function apply_boundaries(chips, chip_bufs, cur, style, flush_right)
  style = VALID_STYLES[style] and style or "rounded"

  if style == "square" then
    return
  end

  if style == "divider" then
    local divider = "%#UiTbDivider#" .. utils.DIVIDER
    for i = 1, #chips - 1 do
      chips[i] = chips[i] .. divider
    end
    return
  end

  for i, bufnr in ipairs(chip_bufs) do
    local cap_hl = "%#" .. ((bufnr == cur) and "UiTbBufOnCap" or "UiTbBufOffCap") .. "#"
    local is_last = i == #chip_bufs
    if not (is_last and flush_right) then
      chips[i] = chips[i] .. cap_hl .. utils.RIGHT_CAP
    end
    if i > 1 then
      chips[i] = cap_hl .. utils.LEFT_CAP .. chips[i]
    end
  end
end

--- The buffer chip list. Drops chips from the front once the list would
--- overflow the columns left by the other modules, keeping the current
--- buffer visible -- ported from `nvchad.tabufline.modules.buffers`'s own
--- overflow handling.
---
--- `cfg.style` picks the boundary look between chips -- "rounded" (default),
--- "square", or "divider". See `apply_boundaries`'s own doc comment.
---
--- `cfg.bufwidth` pins an exact width (the old fixed-21 behaviour) when set.
--- Left unset, the width is computed instead: `space / #bufs`, clamped to
--- `[cfg.bufwidth_min or MIN_BUFWIDTH, cfg.bufwidth_max or MAX_BUFWIDTH]` --
--- few buffers get wide chips up to the max, many buffers get progressively
--- narrower ones down to the min, and the whole bar fills itself instead of
--- leaving an unused strip too narrow for one more fixed-width chip. Past
--- the min, additional buffers overflow exactly as before -- the elastic
--- range only covers the middle, not an unbounded shrink.
---@param cfg Ui.Tabline.Config
---@return string
function M.buffers(cfg)
  local bufs = vim.tbl_filter(api.nvim_buf_is_valid, vim.t.bufs or {})
  vim.t.bufs = bufs

  -- Computed once, not once per buffer: nothing tree_offset/tabs/btns render
  -- depends on how many chips this loop has produced so far, so calling this
  -- inside the loop (as NvChad's own `available_space()` call site does) pays
  -- for a `nvim_eval_statusline` plus a full re-render of every other module
  -- again for every single open buffer -- on every tabline redraw.
  local space = available_space(cfg)

  local bufwidth = cfg.bufwidth
  if not bufwidth then
    local min_w = cfg.bufwidth_min or MIN_BUFWIDTH
    local max_w = cfg.bufwidth_max or MAX_BUFWIDTH
    local per_buf = math.floor(space / math.max(1, #bufs))
    bufwidth = math.max(min_w, math.min(max_w, per_buf))
  end

  local chips = {}
  local chip_bufs = {} -- parallel to `chips`, kept in sync across the drop below
  local seen_current = false
  local cur = api.nvim_get_current_buf()
  -- Whether the visible run ever bumped against the space budget -- true the
  -- moment one more chip wouldn't fit, whether that meant dropping one from
  -- the front or simply stopping early. Feeds `apply_boundaries`'s decision
  -- on whether the last chip's right edge is actually touching anything.
  local flush_right = false

  for i, bufnr in ipairs(bufs) do
    if (#chips + 1) * bufwidth > space then
      flush_right = true
      if seen_current then
        break
      end
      table.remove(chips, 1)
      table.remove(chip_bufs, 1)
    end

    seen_current = seen_current or (cur == bufnr)
    chips[#chips + 1] = utils.style_buf(bufnr, i, bufwidth)
    chip_bufs[#chip_bufs + 1] = bufnr
  end

  apply_boundaries(chips, chip_bufs, cur, cfg.style, flush_right)

  return table.concat(chips) .. "%#UiTbFill#%="
end

--- Tab-page buttons: one per tab plus a "new tab" and a "collapse" button --
--- rendered only when there is more than one tab, same as NvChad's own.
---@param cfg Ui.Tabline.Config
---@return string
function M.tabs(_cfg)
  local total = vim.fn.tabpagenr("$")
  if total <= 1 then
    return ""
  end

  utils.register_click_handlers()

  if vim.g.ui_tb_tabs_toggled == 1 then
    return utils.btn(" 󰅁 ", "Title", "ToggleTabs")
  end

  local current = vim.fn.tabpagenr()
  local buttons = {}
  for nr = 1, total do
    local hl = (nr == current) and "TabOn" or "TabOff"
    buttons[#buttons + 1] = utils.btn(" " .. nr .. " ", hl, "GotoTab", nr)
  end

  return utils.btn(" 󰐕 ", "TabNewBtn", "NewTab")
    .. utils.btn(" TABS ", "Title", "ToggleTabs")
    .. table.concat(buttons)
end

--- The two right-aligned buttons: theme toggle, close all buffers.
---@param cfg Ui.Tabline.Config
---@return string
function M.btns(_cfg)
  utils.register_click_handlers()
  return utils.btn("  ", "ThemeToggleBtn", "ToggleTheme")
    .. utils.btn(" 󰅖 ", "CloseAllBufsBtn", "CloseAllBufs")
end

return M
