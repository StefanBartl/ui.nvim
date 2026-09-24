---@module 'ui.statusline.hover'
--- Follow-the-mouse tooltip for the statusline: hovering a module briefly
--- shows its `ui.statusline.catalog` summary in a small float, and
--- `ui.statusline.render` recolors that module's text (via
--- `ui.statusline.highlights.hover_variant`) for as long as it stays
--- hovered. Same `'mousemoveevent'` + `<MouseMove>` mechanism
--- `ui.kit.chooser`'s own `hover` option already uses for list rows -- see
--- that module's `enable_hover`/`on_hover_move` for the precedent -- except
--- bound globally rather than buffer-locally, since the statusline is not a
--- buffer any one window owns.
---
--- There is no native "hover region" in the `'statusline'` click protocol
--- (only click regions), so "which module is under the pointer" is answered
--- by `ui.statusline.layout.key_at()` instead -- the same column math a
--- right/double click on a module with no click region of its own would
--- need, reused here for the read-only case.

local layout = require("ui.statusline.layout")
local catalog = require("ui.statusline.catalog")

local api = vim.api

local M = {}

---@type table<string, string>|nil
local summaries = nil

---@param key string
---@return string|nil
local function summary_for(key)
  if not summaries then
    summaries = {}
    for _, entry in ipairs(catalog) do
      summaries[entry.key] = entry.summary
    end
  end
  return summaries[key]
end

local state = {
  enabled = false,
  saved_mousemoveevent = nil, ---@type boolean|nil
  current_key = nil, ---@type string|nil
  popup_winid = nil, ---@type integer|nil
}

--- The key `ui.statusline.render` should recolor on this redraw, or nil.
---@return string|nil
function M.current_key()
  return state.current_key
end

---@return nil
local function close_popup()
  if state.popup_winid and api.nvim_win_is_valid(state.popup_winid) then
    pcall(api.nvim_win_close, state.popup_winid, true)
  end
  state.popup_winid = nil
end

--- Break `text` into lines no wider than `max_width` display cells, on word
--- boundaries -- a catalog summary is one long sentence, and a tooltip as
--- wide as the sentence would frequently run off the edge of the screen.
---@param text string
---@param max_width integer
---@return string[]
local function wrap_text(text, max_width)
  local lines = {}
  local line = ""
  for word in text:gmatch("%S+") do
    local candidate = (line == "") and word or (line .. " " .. word)
    if vim.fn.strdisplaywidth(candidate) > max_width and line ~= "" then
      lines[#lines + 1] = line
      line = word
    else
      line = candidate
    end
  end
  if line ~= "" then
    lines[#lines + 1] = line
  end
  return lines
end

--- Open a small float showing `text`, its bottom edge just above
--- `screenrow` (the statusline row) and its left edge roughly under
--- `screencol` (the pointer) -- clamped so it never runs off the top or
--- either side of the screen.
---@param text string
---@param screenrow integer
---@param screencol integer
---@return nil
local function show_popup(text, screenrow, screencol)
  close_popup()

  local max_width = math.max(20, math.min(50, vim.o.columns - 4))
  local lines = wrap_text(text, max_width)
  if #lines == 0 then
    return
  end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end

  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local row = math.max(0, screenrow - 1 - (#lines + 2))
  local col = math.max(0, math.min(screencol - 1, vim.o.columns - width - 2))

  local ok, winid = pcall(api.nvim_open_win, buf, false, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = #lines,
    style = "minimal",
    border = "rounded",
    focusable = false,
    noautocmd = true,
    -- Below every `ui.kit` surface (`base`/`popup` 50, `menu` 60, `toast`
    -- 70 -- see ui.kit.theme's own BASE.zindex) on purpose: a right-click
    -- opens the "manage this module" menu at the exact spot this tooltip is
    -- already showing (the pointer has not moved between hover and click),
    -- and an ambient hint has no business rendering on top of something the
    -- user just asked for. It stays open underneath, harmlessly invisible,
    -- until the next real mouse move clears or replaces it.
    zindex = 40,
  })
  if not ok then
    pcall(api.nvim_buf_delete, buf, { force = true })
    return
  end

  vim.wo[winid].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder"
  state.popup_winid = winid
end

---@return nil
local function clear_hover()
  if state.current_key == nil then
    return
  end
  state.current_key = nil
  close_popup()
  pcall(vim.cmd, "redrawstatus!")
end

--- The statusline row (1-based, editor-relative) a global (`laststatus=3`)
--- statusline draws on -- the row directly above the command line, which
--- `getmousepos()` alone cannot distinguish from the command line itself
--- (both report `winid == 0`; see `M.enable`'s own note on this).
---@return integer
local function global_statusline_row()
  return vim.o.lines - vim.o.cmdheight
end

---@class Ui.Statusline.PointerTarget
---@field winid integer # layout bucket to hit-test against
---@field col integer # 1-based column within that row
---@field maxwidth integer|nil # the row's real width; see `layout.key_at`
---@field screenrow integer # for popup placement
---@field screencol integer # for popup placement

--- Resolve the current mouse position to a statusline hit, if any. A single
--- table rather than several parallel returns so "hit, every field present"
--- and "no hit, nothing to read" are the only two shapes -- the multi-return
--- version of this had `nil`-checked `winid` while still passing its
--- (statically `integer|nil`) siblings straight into `integer`-typed
--- parameters below.
---@return Ui.Statusline.PointerTarget|nil
local function pointer_target()
  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or type(pos) ~= "table" then
    return nil
  end

  -- A per-window statusline (`laststatus` 0/1/2): `winid` is the window it
  -- belongs to, `line == 0` (no text under the pointer -- the statusline
  -- isn't buffer text) and `winrow` is exactly one past that window's own
  -- height (confirmed empirically against a real headless Neovim, `getmousepos()`'s
  -- own docs don't spell this out).
  if pos.winid ~= 0 and pos.line == 0 then
    local h_ok, height = pcall(api.nvim_win_get_height, pos.winid)
    if h_ok and pos.winrow == height + 1 then
      return {
        winid = pos.winid,
        col = pos.wincol,
        maxwidth = nil,
        screenrow = pos.screenrow,
        screencol = pos.screencol,
      }
    end
    return nil
  end

  -- A global statusline (`laststatus == 3`) always draws on exactly one row,
  -- `global_statusline_row()`, and under `laststatus == 3` no window's own
  -- content can ever reach that row -- the row alone is therefore sufficient,
  -- with no need to also check `pos.winid`/`pos.line` the way the per-window
  -- branch above does.
  --
  -- That used to read `pos.winid == 0 and ...`, on the assumption (written
  -- down as "confirmed empirically against a real headless Neovim") that
  -- `getmousepos()` reports `winid == 0` for both the global statusline row
  -- and the command line below it. Real-world regression: with `cmdheight =
  -- 0` (one real user's actual setup -- a single window, no splits), that
  -- never happened -- `getmousepos()` kept reporting the one real window's
  -- `winid` and a real (end-of-buffer-clamped) `line`, for every row
  -- including the very last one, so the old check never once matched and
  -- hover/the click menu never fired. Rather than chase exactly which
  -- combination of options reproduces the old assumption, the row match
  -- here no longer looks at `winid`/`line` at all, except to rule out a
  -- FLOATING window that happens to overlap this row (a transient
  -- notification popup, say) -- that genuinely is not the statusline.
  --
  -- `render.lua` bucketed its `layout.record()` call under
  -- `vim.g.statusline_winid` -- for a global statusline that is documented
  -- as, and confirmed empirically to equal, the current window AT
  -- EVALUATION TIME, but Neovim resets the variable back to unset once the
  -- evaluation finishes, so reading it again here (well after that redraw)
  -- would not reproduce the same bucket. `nvim_get_current_win()` does: it
  -- names the same window `record()` saw, on the same "focus has not
  -- silently changed since the last redraw" assumption `record()`'s own doc
  -- comment already makes.
  if vim.o.laststatus == 3 and pos.screenrow == global_statusline_row() then
    local is_float = false
    if pos.winid ~= 0 then
      local cfg_ok, cfg = pcall(api.nvim_win_get_config, pos.winid)
      is_float = cfg_ok and cfg.relative ~= ""
    end
    if not is_float then
      return {
        winid = api.nvim_get_current_win(),
        col = pos.screencol,
        maxwidth = vim.o.columns,
        screenrow = pos.screenrow,
        screencol = pos.screencol,
      }
    end
  end

  return nil
end

---@return nil
local function on_mouse_move()
  local target = pointer_target()
  if not target then
    clear_hover()
    return
  end

  local key = layout.key_at(target.winid, target.col, target.maxwidth)
  if key == state.current_key then
    return
  end

  if not key then
    clear_hover()
    return
  end

  state.current_key = key
  local summary = summary_for(key)
  if summary then
    show_popup(summary, target.screenrow, target.screencol)
  else
    -- A host's own custom module (not in the catalog): still recolored by
    -- `render.lua` for consistency, but there is no summary to show.
    close_popup()
  end
  pcall(vim.cmd, "redrawstatus!")
end

--- Turn on `<MouseMove>` tracking. Safe to call more than once. Degrades
--- silently to "no hover" on a Neovim without `'mousemoveevent'` (added
--- after this plugin's 0.10 floor) -- same guard `ui.kit.chooser`'s
--- `enable_hover` uses, for the same reason.
---@return nil
function M.enable()
  if state.enabled then
    return
  end

  local ok_read, prev = pcall(function()
    return vim.o.mousemoveevent
  end)
  if not ok_read then
    return
  end
  local ok_write = pcall(function()
    vim.o.mousemoveevent = true
  end)
  if not ok_write then
    return
  end
  state.saved_mousemoveevent = prev
  state.enabled = true

  -- Global, not buffer-local: unlike a chooser's own float, the statusline
  -- is not "owned" by whatever buffer happens to be current when the mouse
  -- crosses it. Bound in every mode a user is plausibly typing or navigating
  -- in -- `<MouseMove>` only ever fires on real mouse movement, never from a
  -- keystroke, so this cannot shadow anything these modes already bind.
  local opts = { desc = "ui.statusline: hover tooltip", silent = true }
  vim.keymap.set({ "n", "i", "v" }, "<MouseMove>", on_mouse_move, opts)
end

--- Undo `enable()`: drop the keymap, restore `'mousemoveevent'`, and close
--- whatever tooltip happens to be open.
---@return nil
function M.disable()
  if not state.enabled then
    return
  end
  state.enabled = false

  for _, mode in ipairs({ "n", "i", "v" }) do
    pcall(vim.keymap.del, mode, "<MouseMove>")
  end
  clear_hover()

  if state.saved_mousemoveevent ~= nil then
    local saved = state.saved_mousemoveevent
    state.saved_mousemoveevent = nil
    pcall(function()
      vim.o.mousemoveevent = saved
    end)
  end
end

--- Whether the mouse is currently over the statusline (either shape:
--- global or per-window). Exposed for `ui.statusline.menu
--- .pointer_on_statusline()` -- a host's own `<RightMouse>` dispatcher can
--- use that to step aside once it has replayed a click onto the statusline,
--- the same way it already does for `ui.tabline.menu.pointer_on_tabline()`.
---@return Ui.Statusline.PointerTarget|nil
M.pointer_target = pointer_target

return M
