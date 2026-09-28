---@module 'ui.windowpicker'
--- Pick a window by letter: a small floating hint (the letter with a cell of
--- padding either side), centered over every eligible window in the current tabpage, then one keypress jumps to (or
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

local autocmd = require("lib.nvim.bindings.autocmd")
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
---@field debug? boolean                           Report the caller's traceback once a pick has finished

---Same shipped defaults as this config's former nvim-window-picker spec
---(`plugins/ui.lua`): `include_current_win = false`, `autoselect_one = true`,
---and the neo-tree/notify/progress filetypes plus terminal/quickfix buftypes
---hidden from the picker. `chars` and `include_unfocusable_windows` were never
---overridden there either, so they carry nvim-window-picker's own upstream
---defaults for continuity.
---@type Ui.WindowPicker.Opts
local cfg = {
  chars = "FJDKSLA;CMRUEIWOQP",
  include_current_win = false,
  autoselect_one = true,
  include_unfocusable_windows = false,
  -- "replacer-progress" is the filetype of lib.nvim.progress's float/kit
  -- styles: focusable by design, but a window the running operation closes
  -- again on its own -- a file opened into it would vanish with it.
  filetype = { "neo-tree", "neo-tree-popup", "notify", "replacer-progress" },
  buftype = { "terminal", "quickfix" },
  debug = false,
}

---Cells a hint spans. Three, not one: `make_scratch` used to read any
---resolved width <= 2 as "no size given" and fall back to 60 columns, so a
---`width = 1` hint was a 60-cell bar with the letter at its left edge. Kept
---at three (letter plus a padding cell each side) even with that fixed, so
---the picker also works against a lib.nvim that still has the fallback.
local HINT_WIDTH = 3

---@class Ui.WindowPicker.Call
---@field time integer            `os.time()` of the call
---@field traceback string        Who called `pick()` (stack minus `pick` itself)
---@field candidates integer      Eligible windows found (0 until they were counted)
---@field prompted boolean        Whether at least one hint was actually shown
---@field picked integer|nil      The window `pick()` returned, once it finished
---@field focus_lost boolean      The pick was cancelled because another window took focus

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

---@internal
---A `HINT_WIDTH`-cell floating hint, centered over `win`. In a window
---narrower than the hint it spills over the split border rather than getting
---narrower, since `make_scratch` can't be asked for less on older lib.nvim.
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

---@internal
---The pick itself. `call` is this pick's own record (see `M.pick`), filled in
---as the pick progresses so it stays accurate even if a later step raises.
---@param opts Ui.WindowPicker.Opts  Already merged with the shipped defaults
---@param call Ui.WindowPicker.Call
---@return integer|nil
local function run_pick(opts, call)
  local windows = eligible_windows(opts)
  call.candidates = #windows
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
  call.prompted = #overlays > 0
  vim.cmd.redraw()

  -- getchar() keeps the event loop running, so something async can open a
  -- window with `enter = true` while the hints are up (a dashboard whose scan
  -- just finished, say). The hints then describe a layout the user is no
  -- longer in, and the keystroke they type next would be swallowed by the
  -- picker instead of reaching the window they are looking at. Cancel the
  -- pick instead: `<Esc>` is what unblocks getchar() and reads as "no hint".
  --
  -- The `<Esc>` is queued exactly once (`focus_lost` guards it): getchar()
  -- consumes one key, and anything left over would reach the window that just
  -- took focus -- a `nice_quit` float such as the gitsuite dashboard closes
  -- on `<Esc>`, i.e. it would shut itself the moment it opened.
  local origin = vim.api.nvim_get_current_win()
  local focus_hook = autocmd.create(
    "WinEnter",
    function()
      if not call.focus_lost and vim.api.nvim_get_current_win() ~= origin then
        call.focus_lost = true
        vim.api.nvim_input("<Esc>")
      end
    end,
    { record = false, desc = "ui.windowpicker: cancel the pick when another window takes focus" }
  )

  local ok, code = pcall(vim.fn.getchar)
  autocmd.delete(focus_hook)

  -- The user's own key can win the race against the queued `<Esc>` (getchar()
  -- then returned that key and the `<Esc>` is still pending): swallow that one
  -- `<Esc>` so it doesn't leak, and treat the pick as cancelled either way --
  -- the hints described a layout the user is no longer in.
  if call.focus_lost and code ~= 27 and vim.fn.getchar(1) == 27 then
    pcall(vim.fn.getchar)
  end

  for _, overlay in ipairs(overlays) do
    if vim.api.nvim_win_is_valid(overlay) then
      pcall(vim.api.nvim_win_close, overlay, true)
    end
  end
  vim.cmd.redraw()

  if call.focus_lost or not ok or type(code) ~= "number" then
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

---Pick a window by letter.
---
---Returns the picked window id; `nil` when there was nothing to pick from,
---the pick was cancelled (`<C-c>`, or any key that isn't one of the hint
---letters), or exactly one window qualified and `autoselect_one` returned
---it without prompting.
---
---Every call is recorded first thing (`M.last_call()`), including its caller's
---traceback, so "who opened the picker?" can be answered afterwards. With
---`debug` the same record is also reported -- after the pick has finished,
---never while the hints are up: a multi-line message there would raise a
---hit-enter prompt that swallows the very key the picker is waiting for.
---@param opts? Ui.WindowPicker.Opts
---@return integer|nil
function M.pick(opts)
  opts = vim.tbl_extend("force", cfg, opts or {})
  ensure_groups()

  ---@type Ui.WindowPicker.Call
  local call = {
    time = os.time(),
    traceback = debug.traceback("", 2), -- level 1 is this function, 2 its caller
    candidates = 0,
    prompted = false,
    focus_lost = false,
  }
  last_call = call

  local picked = run_pick(opts, call)
  call.picked = picked

  if opts.debug then
    notify.info(
      ("pick(): %d candidate(s), prompted=%s, picked=%s, focus_lost=%s%s"):format(
        call.candidates,
        tostring(call.prompted),
        tostring(picked),
        tostring(call.focus_lost),
        call.traceback
      )
    )
  end
  return picked
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
