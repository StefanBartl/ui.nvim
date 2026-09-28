---@module 'ui.windowpicker'
--- Pick a window by letter: a one-cell floating hint, centered over every
--- eligible window in the current tabpage, then one keypress jumps to (or
--- returns) the matching window. Replaces `s1n7ax/nvim-window-picker`'s
--- `pick_window()` for the config that consumes this (its one call site is
--- `config/neotree/keymaps/filesystem/files.lua`, via neo-tree's own
--- `open_with_window_picker` command) — see
--- docs/ROADMAP/reports/Externe-Plugins-Nachbau-Analyse.md.
---
--- Deliberately not nvim-window-picker's default "statusline-winbar" hint
--- style (the only style that config ever actually ran, since it overrode
--- `filter_rules` but never `hint`): that style writes into the statusline/
--- winbar for the duration of the pick, which is exactly the slot ui.nvim
--- owns everywhere else in this plugin. A floating overlay (built on
--- `lib.nvim.window.make_scratch`, the same primitive every other floating
--- overlay in this ecosystem uses) sidesteps that fight entirely.

local window = require("lib.nvim.window")
local notify = require("lib.nvim.notify").create("[ui.windowpicker]")

local M = {}

---@class Ui.WindowPicker.Opts
---@field chars? string                          Candidate letters, in on-screen order
---@field include_current_win? boolean            Offer the window the cursor is already in
---@field autoselect_one? boolean                 Skip the prompt when exactly one window qualifies
---@field include_unfocusable_windows? boolean    Offer windows `nvim_win_get_config` marks unfocusable
---@field filetype? string[]                      Buffer filetypes to exclude
---@field buftype? string[]                       Buffer buftypes to exclude
---@field debug? boolean                           Print the caller's traceback when a pick starts

---Same shipped defaults as this config's former nvim-window-picker spec
---(`plugins/ui.lua`): `include_current_win = false`, `autoselect_one = true`,
---and the neo-tree/notify filetypes plus terminal/quickfix buftypes hidden
---from the picker. `chars` and `include_unfocusable_windows` were never
---overridden there either, so they carry nvim-window-picker's own upstream
---defaults for continuity.
---@type Ui.WindowPicker.Opts
local cfg = {
  chars = "FJDKSLA;CMRUEIWOQP",
  include_current_win = false,
  autoselect_one = true,
  include_unfocusable_windows = false,
  filetype = { "neo-tree", "neo-tree-popup", "notify" },
  buftype = { "terminal", "quickfix" },
  debug = false,
}

---@class Ui.WindowPicker.Call
---@field time integer         `os.time()` of the call
---@field traceback string     Who called `pick()` (stack minus `pick` itself)
---@field candidates integer   Eligible windows found
---@field prompted boolean     Whether hints were actually shown

---What the most recent `M.pick()` call looked like. Kept unconditionally
---(one small table per call) so "who just opened the picker?" can be
---answered after the fact via `M.last_call()`, without `debug` having been on.
---@type Ui.WindowPicker.Call|nil
local last_call = nil

---@internal
---@param list string[]|nil
---@param value string
---@return boolean
local function contains(list, value)
  if not list then
    return false
  end
  for _, v in ipairs(list) do
    if v == value then
      return true
    end
  end
  return false
end

---@internal
---Highlight for the hint letter, registered once and re-applied on a
---colorscheme change when `lib.nvim.ui.hl.persist` is available.
---@return table<string, table>
local function groups_spec()
  return {
    UiWindowPickerHint = { link = "IncSearch", default = true },
  }
end

---@type Lib.UI.HL.PersistHandle|boolean|nil
local hl_handle = nil

---@internal
local function ensure_groups()
  if hl_handle then
    return
  end
  local ok, hl = pcall(require, "lib.nvim.ui.hl")
  if ok and type(hl.persist) == "function" then
    hl_handle = hl.persist(groups_spec, { name = "ui_windowpicker" })
  else
    -- No `ColorScheme` re-application without `lib.nvim.ui.hl.persist`, but
    -- still only ever done once: without a truthy sentinel here, the guard
    -- above never trips and this re-defines the group on every single
    -- `M.pick()` call instead of once.
    for group, opts in pairs(groups_spec()) do
      vim.api.nvim_set_hl(0, group, opts)
    end
    hl_handle = true
  end
end

---@internal
---Eligible windows in the current tabpage, in `nvim_tabpage_list_wins`
---order (stable across calls within one pick).
---@param opts Ui.WindowPicker.Opts
---@return integer[]
local function eligible_windows(opts)
  local current = vim.api.nvim_get_current_win()
  local out = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if opts.include_current_win or win ~= current then
      local focusable = vim.api.nvim_win_get_config(win).focusable
      if opts.include_unfocusable_windows or focusable then
        local buf = vim.api.nvim_win_get_buf(win)
        if
          not contains(opts.filetype, vim.bo[buf].filetype)
          and not contains(opts.buftype, vim.bo[buf].buftype)
        then
          out[#out + 1] = win
        end
      end
    end
  end
  return out
end

local HINT_WIDTH = 3

---@internal
---A three-cell floating hint (` F `), centered over `win`.
---
---Three cells, not one: `make_scratch` treats any resolved width <= 2 as
---"no size given" and falls back to 60 columns, so `width = 1` used to paint
---a 60-cell bar across the window with the letter at its left edge.
---@param win integer
---@param char string
---@return integer|nil overlay_win
local function show_hint(win, char)
  local w = vim.api.nvim_win_get_width(win)
  local h = vim.api.nvim_win_get_height(win)
  return window.make_scratch({
    relative = "win",
    win = win,
    row = math.max(0, math.floor((h - 1) / 2)),
    col = math.max(0, math.floor((w - HINT_WIDTH) / 2)),
    width = HINT_WIDTH,
    height = 1,
    lines = { " " .. char .. " " },
    border = "none",
    focusable = false,
    enter = false,
    wo = { winhighlight = "Normal:UiWindowPickerHint" },
  })
end

---Pick a window by letter.
---
---Returns the picked window id; `nil` when there was nothing to pick from,
---the pick was cancelled (`<C-c>`, or any key that isn't one of the hint
---letters), or exactly one window qualified and `autoselect_one` returned
---it without prompting.
---@param opts? Ui.WindowPicker.Opts
---@return integer|nil
function M.pick(opts)
  opts = vim.tbl_extend("force", cfg, opts or {})
  ensure_groups()

  local windows = eligible_windows(opts)
  last_call = {
    time = os.time(),
    traceback = debug.traceback("", 2),
    candidates = #windows,
    prompted = false,
  }
  if opts.debug then
    notify.info(("pick() called, %d candidate window(s)%s"):format(#windows, last_call.traceback))
  end
  if #windows == 0 then
    -- Not just an internal no-op: `:UI winpick` is a directly user-invoked
    -- command too, and a silent "nothing happened" there is indistinguishable
    -- from the command failing to run at all.
    notify.warn("no window to pick from")
    return nil
  end
  if opts.autoselect_one and #windows == 1 then
    if vim.api.nvim_win_is_valid(windows[1]) then
      return windows[1]
    end
    return nil
  end

  last_call.prompted = true

  ---@type string[]
  local chars = {}
  for i = 1, math.min(#windows, #opts.chars) do
    chars[i] = opts.chars:sub(i, i)
  end

  ---@type integer[]
  local overlays = {}
  for i, win in ipairs(windows) do
    if chars[i] then
      local overlay = show_hint(win, chars[i])
      if overlay then
        overlays[#overlays + 1] = overlay
      end
    end
  end
  vim.cmd.redraw()

  local ok, code = pcall(vim.fn.getchar)

  for _, overlay in ipairs(overlays) do
    if vim.api.nvim_win_is_valid(overlay) then
      pcall(vim.api.nvim_win_close, overlay, true)
    end
  end
  vim.cmd.redraw()

  if not ok or type(code) ~= "number" then
    return nil
  end
  local picked = vim.fn.nr2char(code):lower()
  for i, char in ipairs(chars) do
    if char:lower() == picked then
      -- getchar() yields to the event loop, so a timer/autocmd had the
      -- whole wait to close the window this letter was assigned to. Every
      -- caller (this config's neo-tree integration, and now :UI winpick)
      -- treats nil as "nothing happened" -- a stale id would instead reach
      -- an unguarded nvim_set_current_win and raise a raw API error.
      if vim.api.nvim_win_is_valid(windows[i]) then
        return windows[i]
      end
      return nil
    end
  end
  return nil
end

---Override the shipped defaults. Merged, not replaced.
---@param opts Ui.WindowPicker.Opts|nil
function M.setup(opts)
  cfg = vim.tbl_extend("force", cfg, opts or {})
end

---The most recent `pick()` call (caller traceback, candidate count, whether it
---prompted); nil before the first call. For diagnosing a picker that opened
---without being asked: `:lua =require("ui.windowpicker").last_call()`.
---@return Ui.WindowPicker.Call|nil
function M.last_call()
  return last_call
end

---@return Ui.WindowPicker.Opts
function M.config()
  return cfg
end

return M
