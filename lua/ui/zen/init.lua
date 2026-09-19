---@module 'ui.zen'
--- Distraction-free writing: the current buffer alone, in a centred float
--- of a fixed width, over a dimmed backdrop, with the statusline, tabline,
--- ruler and showcmd gone and the gutter emptied. `:UI zen` toggles it;
--- closing the float any other way (`:q`, `<C-w>c`) restores everything
--- just the same, because the restore hangs off `WinClosed`, not off the
--- command.
---
--- The idea is folke/zen-mode.nvim's; the frame-side placement is this
--- plugin's, which is what makes the fiddly half cheap: ui.nvim owns the
--- statusline and tabline, so hiding them is `laststatus`/`showtabline`
--- being set and restored here rather than negotiated with a third party.
--- No terminal font tricks, no plugin bridges: the buffer, a box, and the
--- options that make the box the only thing on screen.
---
--- The float shows the same buffer, so edits are edits; the cursor and
--- scroll position travel in on open and back out on close. Only one zen
--- window at a time.

local api = vim.api

local M = {}

---@class Ui.Zen.Opts
---@field width? number             # columns when > 1, a fraction of the editor when <= 1
---@field height? number            # rows when > 1, a fraction of the editor when <= 1
---@field backdrop? number          # 0-1: how far the backdrop is dimmed towards the background (1 = not at all)
---@field wo? table<string, any>    # window options applied to the zen window
---@field hide_statusline? boolean
---@field hide_tabline? boolean
---@field hide_ruler? boolean       # `ruler` and `showcmd`
---@field on_open? fun(win: integer)
---@field on_close? fun()

---@class Ui.Zen.Config: Ui.Zen.Opts
local cfg = {
  width = 120,
  height = 1,
  backdrop = 0.6,
  wo = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    cursorline = false,
    cursorcolumn = false,
    colorcolumn = "",
    list = false,
    winbar = "",
  },
  hide_statusline = true,
  hide_tabline = true,
  hide_ruler = true,
}

---@class Ui.Zen.State
---@field win integer
---@field backdrop integer
---@field origin integer            # the window zen was opened from
---@field buf integer
---@field saved table<string, any>  # global options to restore
---@field augroup integer
---@field cursor integer[]|nil     # where the cursor was last seen inside the box

---@type Ui.Zen.State|nil
local state = nil

---@internal
---@param n number
---@param total integer
---@return integer
local function size(n, total)
  if n <= 1 then
    return math.max(1, math.floor(total * n + 0.5))
  end
  return math.min(total, math.floor(n))
end

---@internal
---The float geometry for the current editor size.
---@return { width: integer, height: integer, row: integer, col: integer }
local function geometry()
  local columns = vim.o.columns
  local lines = vim.o.lines - vim.o.cmdheight - 1
  local width = size(cfg.width, columns)
  local height = size(cfg.height, lines)
  return {
    width = width,
    height = height,
    row = math.max(0, math.floor((lines - height) / 2)),
    col = math.max(0, math.floor((columns - width) / 2)),
  }
end

---@internal
---Dim the backdrop: `Normal`'s background blended towards black by
---`1 - cfg.backdrop`, as one highlight group.
local function backdrop_group()
  local normal = api.nvim_get_hl(0, { name = "Normal", link = false })
  local bg = normal.bg
  if type(bg) ~= "number" then
    api.nvim_set_hl(0, "UiZenBackdrop", { bg = "#000000" })
    return "UiZenBackdrop"
  end
  local f = math.max(0, math.min(1, cfg.backdrop or 1))
  local r = math.floor(((bg / 65536) % 256) * f)
  local g = math.floor(((bg / 256) % 256) * f)
  local b = math.floor((bg % 256) * f)
  api.nvim_set_hl(0, "UiZenBackdrop", { bg = ("#%02x%02x%02x"):format(r, g, b) })
  return "UiZenBackdrop"
end

---@internal
---Restore the globals, close the backdrop, hand the cursor back. Idempotent.
local function teardown()
  local s = state
  if not s then
    return
  end
  state = nil
  pcall(api.nvim_del_augroup_by_id, s.augroup)
  for name, value in pairs(s.saved) do
    pcall(function()
      vim.o[name] = value
    end)
  end
  if api.nvim_win_is_valid(s.backdrop) then
    pcall(api.nvim_win_close, s.backdrop, true)
  end
  if api.nvim_win_is_valid(s.win) then
    pcall(api.nvim_win_close, s.win, true)
  end
  if api.nvim_win_is_valid(s.origin) then
    -- The buffer may have changed inside zen; follow it, and the cursor.
    if api.nvim_buf_is_valid(s.buf) and api.nvim_win_get_buf(s.origin) ~= s.buf then
      pcall(api.nvim_win_set_buf, s.origin, s.buf)
    end
    if s.cursor then
      pcall(api.nvim_win_set_cursor, s.origin, s.cursor)
    end
    pcall(api.nvim_set_current_win, s.origin)
  end
  if type(cfg.on_close) == "function" then
    pcall(cfg.on_close)
  end
end

---@internal
---Resize both floats after the editor changed size.
local function relayout()
  local s = state
  if not s or not api.nvim_win_is_valid(s.win) then
    return
  end
  local g = geometry()
  pcall(api.nvim_win_set_config, s.win, {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
  })
  if api.nvim_win_is_valid(s.backdrop) then
    pcall(api.nvim_win_set_config, s.backdrop, {
      relative = "editor",
      width = vim.o.columns,
      height = vim.o.lines,
      row = 0,
      col = 0,
    })
  end
end

---Open zen for the current window's buffer. No-op when already open.
---@return integer|nil win  The zen window.
function M.open()
  if state and api.nvim_win_is_valid(state.win) then
    return state.win
  end
  teardown()

  local origin = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(origin)
  local cursor = api.nvim_win_get_cursor(origin)
  local g = geometry()

  local saved = {}
  local function save(name, value)
    saved[name] = vim.o[name]
    vim.o[name] = value
  end
  if cfg.hide_statusline then
    save("laststatus", 0)
  end
  if cfg.hide_tabline then
    save("showtabline", 0)
  end
  if cfg.hide_ruler then
    save("ruler", false)
    save("showcmd", false)
  end

  local backdrop_buf = api.nvim_create_buf(false, true)
  vim.bo[backdrop_buf].bufhidden = "wipe"
  local backdrop = api.nvim_open_win(backdrop_buf, false, {
    relative = "editor",
    width = vim.o.columns,
    height = vim.o.lines,
    row = 0,
    col = 0,
    style = "minimal",
    focusable = false,
    zindex = 40,
    noautocmd = true,
  })
  vim.wo[backdrop].winhighlight = "Normal:" .. backdrop_group() .. ",NormalNC:" .. backdrop_group()
  vim.wo[backdrop].winblend = 0

  local win = api.nvim_open_win(buf, true, {
    relative = "editor",
    width = g.width,
    height = g.height,
    row = g.row,
    col = g.col,
    style = "minimal",
    border = "none",
    zindex = 45,
  })
  for name, value in pairs(cfg.wo or {}) do
    pcall(function()
      vim.wo[win][name] = value
    end)
  end
  vim.wo[win].winhighlight = "NormalFloat:Normal,FloatBorder:Normal"
  pcall(api.nvim_win_set_cursor, win, cursor)

  local augroup = api.nvim_create_augroup("UiZen", { clear = true })
  -- `session` is this specific M.open() call's own state table, captured
  -- by the WinClosed closure below. The restore it schedules must act on
  -- THIS session and no other: if the window is closed externally and
  -- M.open() is called again before the deferred teardown runs, the
  -- module-level `state` by then points at a newer session, and comparing
  -- against `session` (not re-reading `state`) is what stops the stale
  -- callback from tearing down a session it was never scheduled for.
  local session = {
    win = win,
    backdrop = backdrop,
    origin = origin,
    buf = buf,
    cursor = cursor,
    saved = saved,
    augroup = augroup,
  }
  state = session
  api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    pattern = tostring(win),
    once = true,
    callback = function()
      if state ~= session then
        -- Superseded by a newer session already; nothing here to close.
        return
      end
      state.cursor = pcall(api.nvim_win_get_cursor, win) and api.nvim_win_get_cursor(win)
        or state.cursor
      state.buf = api.nvim_win_get_buf(win)
      vim.schedule(function()
        if state == session then
          teardown()
        end
      end)
    end,
    desc = "ui.zen: restore everything when the zen window closes",
  })
  api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = relayout,
    desc = "ui.zen: keep the box centred",
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = augroup,
    callback = function()
      if state and api.nvim_get_current_win() == state.win then
        state.buf = api.nvim_win_get_buf(state.win)
      end
    end,
    desc = "ui.zen: follow a buffer switch inside the box",
  })

  if type(cfg.on_open) == "function" then
    pcall(cfg.on_open, win)
  end
  return win
end

---Close zen and restore the frame. No-op when closed.
function M.close()
  local s = state
  if not s then
    return
  end
  if api.nvim_win_is_valid(s.win) then
    s.cursor = api.nvim_win_get_cursor(s.win)
    s.buf = api.nvim_win_get_buf(s.win)
  end
  teardown()
end

---@return boolean now_open
function M.toggle()
  if M.is_open() then
    M.close()
    return false
  end
  M.open()
  return true
end

---@return boolean
function M.is_open()
  return state ~= nil and api.nvim_win_is_valid(state.win)
end

---The zen window, or nil.
---@return integer|nil
function M.win()
  if state and api.nvim_win_is_valid(state.win) then
    return state.win
  end
  return nil
end

---Override the shipped tunables. `wo` is merged, not replaced.
---@param opts Ui.Zen.Opts|nil
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    if k == "wo" and type(v) == "table" then
      cfg.wo = vim.tbl_extend("force", cfg.wo, v)
    elseif cfg[k] ~= nil or k == "on_open" or k == "on_close" then
      cfg[k] = v
    end
  end
  if M.is_open() then
    relayout()
  end
end

---@return Ui.Zen.Config
function M.config()
  return cfg
end

return M
