---@module 'ui.tabline.modules'
--- The four built-in tabline segments -- `tree_offset`, `buffers`, `tabs`,
--- `btns` -- each `fun(cfg: Ui.Tabline.Config): string`, ported from
--- `nvchad.tabufline.modules`. Kept in one file rather than one per segment
--- (unlike the statusline's `modules/` tree): all four share `cfg` and
--- `available_space()`, and NvChad's own upstream keeps them together too.

local notify = require("lib.nvim.notify").create("[ui.tabline.modules]")
local utils = require("ui.tabline.utils")
local state = require("ui.bindings.keymaps.tabufline.state")
local scroll = require("ui.tabline.scroll")
local api = vim.api

local M = {}

-- Which of `bufwidth`/`bufwidth_min`/`bufwidth_max` has already warned about
-- an invalid value this session -- `M.buffers()` runs on nearly every
-- tabline redraw, so this dedups the same way `ui.tabline.render`'s own
-- `warn_once` does for `order` keys.
---@type table<string, true>
local width_warned = {}

--- ERR-22: `bufwidth`/`bufwidth_min`/`bufwidth_max` are documented as
--- positive integers, but `M.buffers()` used to only guard `bufwidth` with
--- `if not bufwidth then` (catches an absent/`false` value, not a wrong
--- type) and read `bufwidth_min`/`bufwidth_max` with a bare `... or
--- MIN_BUFWIDTH` (same gap). A wrong-type value reached the chip-width
--- arithmetic below unguarded -- e.g. `cfg.bufwidth = "20"` (a realistic
--- typo: a string that reads like the column count it should have been).
---@param value any
---@param field "bufwidth"|"bufwidth_min"|"bufwidth_max"
---@return boolean # true when `value` is present but not a usable positive number
local function is_invalid_width(value, field)
  if value == nil then
    return false
  end
  if type(value) ~= "number" or value <= 0 then
    if not width_warned[field] then
      width_warned[field] = true
      notify.warn(
        ("ui.tabline.modules: cfg.%s must be a positive number, got %s (%s) -- ignoring it"):format(
          field,
          tostring(value),
          type(value)
        )
      )
    end
    return true
  end
  return false
end

-- Bounds for the auto-computed chip width (`M.buffers` below) -- the elastic
-- range that lets the bar fill itself instead of leaving a leftover strip
-- too narrow for one more fixed-width chip. Below MIN_BUFWIDTH, more buffers
-- simply overflow (dropped from the front) exactly like a fixed-width bar
-- always has; the shrinking only happens inside this range.
local MIN_BUFWIDTH = 12
local MAX_BUFWIDTH = 24

-- Nerd Font glyphs (the devicon and the close/modified icon inside every
-- chip) can render 1 display cell wider in a real terminal/GUI's actual
-- font than Neovim's own width tables believe -- ambiguous-width Private
-- Use Area codepoints, rendered inconsistently across terminals/fonts, and
-- `ui.tabline.utils.style_buf`'s own width accounting (however carefully
-- it measures via `strdisplaywidth`/`nvim_eval_statusline`) can only ever
-- report Neovim's OWN model, never the font actually drawing it. Found
-- live: the resulting overflow grew with the number of VISIBLE chips (each
-- one carries its own icon), which a flat margin would not scale with --
-- treating every chip as if it cost `ICON_WIDTH_SLACK` columns more than
-- its real `bufwidth` when deciding how many fit (while `style_buf` itself
-- still renders at the real, unpadded `bufwidth`) reserves exactly that
-- much headroom per chip, so a mismatch like this has room to be wrong in
-- before it can ever reach Neovim's own last-resort tabline truncation.
local ICON_WIDTH_SLACK = 2

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
---@return integer space
---@return string prefix # the modules that sit left of "buffers" in `order`, rendered -- `ui.tabline.layout` needs their width
local function available_space(cfg)
  local str = {}
  local before = {}
  local seen_buffers = false
  for _, key in ipairs(cfg.order or {}) do
    if key == "buffers" then
      seen_buffers = true
    else
      local mod = (cfg.modules and cfg.modules[key]) or M[key]
      if type(mod) == "function" then
        local ok, rendered = pcall(mod, cfg)
        rendered = ok and rendered or ""
        str[#str + 1] = rendered
        if not seen_buffers then
          before[#before + 1] = rendered
        end
      end
    end
  end

  local width = api.nvim_eval_statusline(table.concat(str), { use_tabline = true }).width
  return vim.o.columns - width, table.concat(before)
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

local styles = require("ui.tabline.styles")

--- Decorate chip boundaries per `cfg.style`, mutating `chips` in place --
--- resolved through `ui.tabline.styles`'s registry (the three shipped
--- looks -- "rounded" default, "square", "divider" -- plus whatever a host
--- registered under its own name). An unrecognized or unset name falls
--- back to "rounded" rather than silently rendering unstyled -- same
--- degrade-not-crash contract `get_separators()` already uses for the
--- statusline's own `separator_style`. See `ui.tabline.styles`'s own doc
--- comment for what each shipped look actually does.
---@param chips string[]
---@param chip_bufs integer[] # parallel to `chips`
---@param cur integer # current buffer, for the rounded style's per-chip cap color
---@param style string|nil
---@param flush_right boolean # whether the visible run actually reaches the right edge of its budget
---@return nil
local function apply_boundaries(chips, chip_bufs, cur, style, flush_right)
  local style_fn = styles.resolve(style) or styles.resolve("rounded")
  style_fn(chips, chip_bufs, cur, flush_right)
end

--- The buffer chip list. Pinned buffers render first and are never dropped;
--- past them, unpinned chips drop from the front once the list would
--- overflow the columns left by the other modules, keeping the current
--- buffer visible -- ported from `nvchad.tabufline.modules.buffers`'s own
--- overflow handling, split into a pinned pass and an unpinned pass (see
--- "Zu beachten" in the pins roadmap entry: pins must stay visible, which
--- the original single sliding window could not promise since pinned
--- buffers -- kept first in `vim.t.bufs` by `state.set_pinned`'s own
--- invariant -- are exactly the ones a front-dropping window drops first).
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
--- range only covers the middle, not an unbounded shrink. Every chip (pinned
--- or not) uses the same `bufwidth`, computed over the full buffer count --
--- pins are exempted from being DROPPED, not given a width budget of their
--- own; a mixed pinned/unpinned bar still reads as one uniform row of chips.
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
  local space, prefix = available_space(cfg)

  local bufwidth = cfg.bufwidth
  if is_invalid_width(bufwidth, "bufwidth") then
    bufwidth = nil
  end
  if not bufwidth then
    local min_w = cfg.bufwidth_min
    if is_invalid_width(min_w, "bufwidth_min") then
      min_w = nil
    end
    min_w = min_w or MIN_BUFWIDTH

    local max_w = cfg.bufwidth_max
    if is_invalid_width(max_w, "bufwidth_max") then
      max_w = nil
    end
    max_w = max_w or MAX_BUFWIDTH

    local per_buf = math.floor(space / math.max(1, #bufs))
    bufwidth = math.max(min_w, math.min(max_w, per_buf))
  end

  local cur = api.nvim_get_current_buf()
  -- Whether the visible run ever bumped against the space budget -- true the
  -- moment one more chip wouldn't fit, whether that meant dropping one from
  -- the front or simply stopping early. Feeds `apply_boundaries`'s decision
  -- on whether the last chip's right edge is actually touching anything.
  local flush_right = false

  -- Pinned buffers first, always rendered -- see the doc comment above for
  -- why this cannot share the unpinned loop's front-dropping window.
  local pinned_bufs, other_bufs = {}, {}
  for i, bufnr in ipairs(bufs) do
    if state.is_pinned(bufnr) then
      pinned_bufs[#pinned_bufs + 1] = { bufnr = bufnr, index = i }
    else
      other_bufs[#other_bufs + 1] = { bufnr = bufnr, index = i }
    end
  end

  local chips, chip_bufs = {}, {}
  for _, entry in ipairs(pinned_bufs) do
    chips[#chips + 1] = utils.style_buf(entry.bufnr, entry.index, bufwidth)
    chip_bufs[#chip_bufs + 1] = entry.bufnr
  end
  if #chips * (bufwidth + ICON_WIDTH_SLACK) >= space then
    flush_right = true
  end

  local remaining = space - #chips * (bufwidth + ICON_WIDTH_SLACK)

  -- The unpinned window: `scroll.offset()` (set while a tabline drag holds
  -- the pointer at either edge -- see ui.tabline.scroll) overrides the
  -- default "keep the current buffer visible" sliding logic with a fixed
  -- starting point instead. The two cannot coexist: during a drag the
  -- dragged chip IS the current buffer, so the sliding logic below would
  -- keep snapping the window back to it every redraw, fighting the very
  -- scroll a held edge asks for.
  local offset = scroll.offset()
  if offset then
    local start = math.min(offset, math.max(0, #other_bufs - 1)) + 1
    for i = start, #other_bufs do
      local entry = other_bufs[i]
      if (#chips - #pinned_bufs + 1) * (bufwidth + ICON_WIDTH_SLACK) > remaining then
        flush_right = true
        break
      end
      chips[#chips + 1] = utils.style_buf(entry.bufnr, entry.index, bufwidth)
      chip_bufs[#chip_bufs + 1] = entry.bufnr
    end
  else
    local seen_current = false
    local unpinned_chips, unpinned_bufs = {}, {}
    for _, entry in ipairs(other_bufs) do
      if (#unpinned_chips + 1) * (bufwidth + ICON_WIDTH_SLACK) > remaining then
        flush_right = true
        if seen_current then
          break
        end
        table.remove(unpinned_chips, 1)
        table.remove(unpinned_bufs, 1)
      end

      seen_current = seen_current or (cur == entry.bufnr)
      unpinned_chips[#unpinned_chips + 1] = utils.style_buf(entry.bufnr, entry.index, bufwidth)
      unpinned_bufs[#unpinned_bufs + 1] = entry.bufnr
    end
    vim.list_extend(chips, unpinned_chips)
    vim.list_extend(chip_bufs, unpinned_bufs)
  end

  apply_boundaries(chips, chip_bufs, cur, cfg.style, flush_right)

  -- After the boundary decoration, which rewrites chip strings in place --
  -- a drag hit-tests against what is actually on screen.
  require("ui.tabline.layout").record(prefix, chip_bufs, chips)

  return table.concat(chips) .. "%#UiTbFill#%="
end

--- Tab-page buttons: one per tab plus a "new tab" and a "collapse" button --
--- rendered only when there is more than one tab, same as NvChad's own.
--- Takes the config to match the `fun(cfg: Ui.Tabline.Config): string`
--- shape every tabline module has, and ignores it -- tab buttons are not
--- configurable through `Ui.Tabline.Config`.
---@param _cfg Ui.Tabline.Config
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
--- Same as `M.tabs`: takes the config for signature parity, ignores it.
---@param _cfg Ui.Tabline.Config
---@return string
function M.btns(_cfg)
  utils.register_click_handlers()
  return utils.btn("  ", "ThemeToggleBtn", "ToggleTheme")
    .. utils.btn(" 󰅖 ", "CloseAllBufsBtn", "CloseAllBufs")
end

return M
