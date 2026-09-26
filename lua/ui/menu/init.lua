---@module 'ui.menu'
--- The right-click menu: what a sister plugin contributes, the general
--- sections (Code, Clipboard, File, Delete, Tools), rows of your own -- and the
--- two triggers that open it (`<RightMouse>` at the pointer, a key at the
--- cursor). Drawn by `ui.contextmenu`, so no third-party menu plugin is needed.
---
--- Off until asked for -- it binds a global `<RightMouse>`:
--- >lua
---   require("ui").setup({ menu = { integrations = { lsp = false } } })
---   -- or
---   require("ui.menu").setup({ extra = { ... } })
--- <
--- What is shown is decided per open, in three layers that each default to on:
--- the plugin is installed, ui.nvim's `integrations.<name>` is not `false`, and
--- the plugin itself has not opted out (see `ui.menu.contributors`). A section
--- with no entry left shows no heading.
---
--- The Visual selection is captured when the menu is built (`ui.menu.selection`):
--- a right click inside it keeps it, so "Copy/Delete Marked" act on what was
--- marked; a click elsewhere ends it and moves the cursor there.

local config = require("ui.menu.config")
local contributors = require("ui.menu.contributors")
local sections = require("ui.menu.sections")
local selection = require("ui.menu.selection")
local contextmenu = require("ui.contextmenu")

local M = {}

local BOUND = {}

--- Every item of the menu for `buf` (default: the current buffer): plugin
--- contributions and user rows first, the general sections beneath.
---@param buf? integer
---@param mouse? boolean  anchor a `lazy` contributor's own popup ("Debug",
---  "Git Actions") the same way this menu itself was, or will be, opened --
---  at the pointer (default) or at the cursor for a `key`-bound, mouse-less
---  open. Passed through to `ui.menu.contributors`/`ui.menu.sections`.
---@return Ui.ContextMenu.Item[]
function M.items(buf, mouse)
  buf = buf or vim.api.nvim_get_current_buf()
  local cfg = config.get()
  local out = contributors.build(buf, cfg, mouse)
  vim.list_extend(out, sections.build(cfg, mouse))
  return out
end

--- Build and open the menu.
---@param opts? { buf?: integer, mouse?: boolean }  `mouse`: anchor at the pointer (default false = at the cursor)
function M.open(opts)
  opts = opts or {}
  local mouse = opts.mouse == true
  local items = M.items(opts.buf, mouse)
  if #items > 0 then
    contextmenu.open(items, { mouse = mouse })
  end
end

--- Replay the native right click (a bar's own click handler needs it).
local function replay_right_click()
  vim.cmd.exec('"normal! \\<RightMouse>"')
end

--- The `<RightMouse>` handler.
function M.on_right_click()
  -- Bars first: a click on the tab bar or the statusline is answered by that
  -- bar's own click handler (a tab's menu, a module's own or generic one),
  -- which only the native right click fires. The general menu is about the
  -- buffer under the pointer, which a bar is not -- and two menus would open
  -- on top of each other. `getmousepos()` also reports `winid == 0` on the
  -- global statusline row and the command line, which the fallback below
  -- would read as "no window" and resolve to the CURRENT window's buffer.
  local ok_tb, tabline_menu = pcall(require, "ui.tabline.menu")
  local ok_sl, statusline_menu = pcall(require, "ui.statusline.menu")
  if
    (ok_tb and tabline_menu.pointer_on_tabline())
    or (ok_sl and statusline_menu.pointer_on_statusline())
  then
    replay_right_click()
    return
  end

  -- Not text either: a window's winbar reports `line == 0`. Its own click
  -- handler (a breadcrumb, say) answers the native right click, as it always
  -- did; a left click would run the handler's *navigate* action instead.
  local ok_pos, pos = pcall(vim.fn.getmousepos)
  local on_winbar = ok_pos and type(pos) == "table" and pos.winid ~= 0 and pos.line == 0
  if on_winbar then
    replay_right_click()
    local ok_wb, wbuf = pcall(vim.api.nvim_win_get_buf, pos.winid)
    if ok_wb then
      M.open({ buf = wbuf, mouse = true })
    end
    return
  end

  -- In the buffer: a right click INSIDE a live Visual selection leaves it
  -- alone. Anywhere else the selection ends and the cursor moves to the
  -- pointer -- with a left click, not a replayed right one: `'mousemodel'`
  -- "extend" makes a native right click start a Visual selection from the old
  -- cursor to the pointer, and the menu would then offer to copy/delete THAT.
  local mode = vim.fn.mode()
  local visual = mode == "v" or mode == "V" or mode == "\22"
  if not (visual and selection.pointer_inside()) then
    if visual then
      vim.cmd.exec('"normal! \\<Esc>"')
    end
    vim.cmd.exec('"normal! \\<LeftMouse>"')
  end

  local winid
  local ok_mouse, m = pcall(vim.fn.getmousepos)
  if ok_mouse and type(m) == "table" and m.winid and m.winid ~= 0 then
    winid = m.winid
  else
    winid = vim.api.nvim_get_current_win()
  end
  local ok_buf, buf = pcall(vim.api.nvim_win_get_buf, winid)
  if not ok_buf or not buf then
    buf = vim.api.nvim_get_current_buf()
  end
  M.open({ buf = buf, mouse = true })
end

--- Open and close the menu once, unseen, so the first real open does not pay
--- the one-time costs: the kit menu's modules, the first floating window
--- (autocmd-driven lazy plugins load on it), the first build of the entries.
--- Both calls happen in one tick, so nothing is painted in between.
---
--- Skipped unless it is certainly harmless: the kit renderer (the only one
--- whose `open` hands back a surface to close again), Normal mode, no
--- command-line window, and the current window an ordinary one.
---@return boolean warmed
function M.warm()
  local cfg = config.get()
  if cfg.renderer ~= "kit" or not contextmenu.is_enabled() then
    return false
  end
  if vim.fn.mode() ~= "n" or vim.fn.getcmdwintype() ~= "" then
    return false
  end
  -- `state()`: halfway through a mapping ("m"), an operator pending ("o"), a
  -- completion menu up ("a"), or blocked waiting for input ("w") -- all moments
  -- where an open/close would land in the middle of something the user started.
  if vim.fn.state("moaw") ~= "" then
    return false
  end
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(win).relative ~= "" then
    return false
  end
  local ok, surface = pcall(function()
    return contextmenu.open(M.items(vim.api.nvim_win_get_buf(win), false), { mouse = false })
  end)
  if type(surface) == "table" and type(surface.close) == "function" then
    pcall(surface.close, surface)
  end
  -- Whatever the open moved, focus goes back where the user left it.
  if vim.api.nvim_win_is_valid(win) and vim.api.nvim_get_current_win() ~= win then
    pcall(vim.api.nvim_set_current_win, win)
  end
  return ok and type(surface) == "table"
end

--- `gen` is bumped whenever a running preload must stop (`prewarm = false` in a
--- later `setup`); `started` keeps a repeated `setup` from starting a second chain.
---@type { gen: integer, started: boolean }
local prewarm_state = { gen = 0, started = false }

--- Start the idle-time preload of the contributors' modules. Idempotent: a
--- second `setup()` while the preload is running (or done) starts nothing, and
--- `prewarm = false` stops a chain that is still going.
---@param cfg Ui.Menu.Opts
local function start_prewarm(cfg)
  if not cfg.prewarm then
    prewarm_state.gen = prewarm_state.gen + 1
    prewarm_state.started = false
    return
  end
  if prewarm_state.started then
    return
  end
  prewarm_state.started = true
  local gen = prewarm_state.gen
  local function alive()
    return gen == prewarm_state.gen
  end
  local function go()
    if not alive() then
      return
    end
    contributors.prewarm(contributors.prewarm_modules(config.get()), function()
      vim.schedule(function()
        if alive() then
          pcall(M.warm)
        end
      end)
    end, nil, alive)
  end
  if vim.v.vim_did_enter == 1 then
    go()
  else
    vim.api.nvim_create_autocmd("VimEnter", {
      group = vim.api.nvim_create_augroup("UiMenuPrewarm", { clear = true }),
      once = true,
      callback = go,
    })
  end
end

---@return nil
local function unbind()
  for _, b in ipairs(BOUND) do
    pcall(vim.keymap.del, b.modes, b.lhs)
  end
  BOUND = {}
end

--- Configure the menu and bind its triggers. Safe to call again: it replaces
--- the previous configuration and bindings.
---@param opts? Ui.Menu.Opts
function M.setup(opts)
  local cfg = config.apply(opts)
  unbind()

  -- `native_popup` only matters for a bound mouse: `contextmenu.setup` sets
  -- 'mousemodel' to "extend" unless told to keep the native popup, and a
  -- key-only menu has no business changing how the mouse behaves.
  contextmenu.setup({
    renderer = cfg.renderer,
    native_popup = cfg.native_popup or not cfg.mouse,
  })

  if cfg.mouse then
    vim.keymap.set(
      { "n", "v" },
      "<RightMouse>",
      M.on_right_click,
      { desc = "ui.menu: context menu at the pointer" }
    )
    BOUND[#BOUND + 1] = { modes = { "n", "v" }, lhs = "<RightMouse>" }
  end
  if cfg.key then
    vim.keymap.set({ "n", "v" }, cfg.key, function()
      M.open({ mouse = false })
    end, { desc = "ui.menu: context menu at the cursor" })
    BOUND[#BOUND + 1] = { modes = { "n", "v" }, lhs = cfg.key }
  end
  start_prewarm(cfg)
end

--- Register another `<plugin>.integrations.menu`-style contributor at runtime.
---@param spec Ui.Menu.ContributorSpec
function M.register_contributor(spec)
  contributors.register(spec)
end

--- Add a row of your own at runtime (same shape as `setup({ extra = { ... } })`).
---@param entry Ui.Menu.Extra
function M.add(entry)
  contributors.add(entry)
end

--- The live configuration table -- a reference, not a copy: read it, do not
--- mutate it (change it through `setup`).
---@return Ui.Menu.Opts
function M.config()
  return config.get()
end

return M
