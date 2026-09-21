---@module 'ui.tabline.menu'
--- The right-click context menu of a buffer chip: actions that act on THAT
--- tab -- close it (or its neighbours), move it, save it, copy its path,
--- open it elsewhere -- and nothing else. The tab-bar sibling of the file
--- tree's own right-click menu, drawn through the same `ui.contextmenu`.
---
--- Reached from `ui.tabline.utils.on_chip_click` (the tabline click protocol
--- reports the button, and hands over which buffer the chip belongs to), so
--- nothing here needs to hit-test the pointer. A host that binds its own global
--- `<RightMouse>` dispatcher still gets there, provided that dispatcher replays
--- the native click (`normal! <RightMouse>`) -- which is also what makes the
--- click handler fire -- and then steps aside when `pointer_on_tabline()` says
--- the click was on the tab bar, so two menus do not open on top of each other.
---
--- Every entry gates itself (`ui.contextmenu.entry`'s `available`): "close to
--- the left" is not offered on the first tab, "save" only on a modified one.
--- The whole menu is a function of the live `vim.t.bufs`, rebuilt per click.

local contextmenu = require("ui.contextmenu")
local nerd = require("lib.nvim.ui.nerd_font")
local notify = require("lib.nvim.notify").create("[ui.tabline.menu]")
local state = require("ui.bindings.keymaps.tabufline.state")
local utils = require("ui.tabline.utils")
local reopen = require("ui.tabline.reopen")

local api = vim.api

local M = {}

---@param hex string
---@param fallback string
---@return { icon: string }
local function icon(hex, fallback)
  return { icon = nerd.glyph(hex, fallback) }
end

--- Whether the last mouse event landed on the tab bar (row 1, with a
--- tabline showing at all). For a host's own `<RightMouse>` dispatcher: after
--- it replays the native click it should return without opening its general
--- menu when this is true, since the chip's own menu is already on its way.
---@return boolean
function M.pointer_on_tabline()
  if vim.o.showtabline == 0 then
    return false
  end
  local ok, pos = pcall(vim.fn.getmousepos)
  return ok and type(pos) == "table" and pos.screenrow == 1
end

---@param bufnr integer
---@return string
local function display_name(bufnr)
  local path = api.nvim_buf_get_name(bufnr)
  return path == "" and "[No Name]" or vim.fn.fnamemodify(path, ":t")
end

--- The buffers of the current tab, in tab order, that are still valid.
---@return integer[]
local function tab_bufs()
  return vim.tbl_filter(api.nvim_buf_is_valid, vim.t.bufs or {})
end

--- Close `set`, keeping `keep` on screen: when the buffer the user is looking
--- at is about to go, land on `keep` first, so the close ends where the click
--- was instead of on whichever neighbour the first close happened to pick.
---@param set integer[]
---@param keep integer
local function close_set(set, keep)
  if #set == 0 then
    return
  end
  if vim.tbl_contains(set, api.nvim_get_current_buf()) then
    state.goto_buf(keep)
  end
  utils.close_bufs(set)
end

--- Ask for a slot and move `bufnr` there. A bare number is an absolute slot;
--- a leading `+`/`-` moves relative to where the tab is now -- `+2` is two to
--- the right. Out-of-range numbers clamp to the ends (see `move_buf_to`).
---@param bufnr integer
local function prompt_move(bufnr)
  local total = #tab_bufs()
  local here = state.index_of(bufnr) or 1

  require("ui.kit").input({
    title = ("Move to position (1-%d, +N/-N relative)"):format(total),
    default = tostring(here),
    width = 40,
    on_submit = function(line)
      line = vim.trim(line or "")
      local n = tonumber(line)
      if not n or n ~= math.floor(n) then
        notify.warn(("not a whole number: %q"):format(line))
        return
      end
      local relative = line:sub(1, 1) == "+" or line:sub(1, 1) == "-"
      local current = state.index_of(bufnr)
      if not current then
        return
      end
      state.move_buf_to(bufnr, relative and current + n or n)
    end,
  })
end

--- Run `cmd` (an Ex command taking a buffer number) for `bufnr`, surfacing a
--- failure as a notification instead of a raised error out of a menu callback.
---@param cmd string
---@param bufnr integer
local function buffer_cmd(cmd, bufnr)
  local ok, err = pcall(vim.cmd, ("%s %d"):format(cmd, bufnr))
  if not ok then
    notify.warn(("%s failed: %s"):format(cmd, tostring(err)))
  end
end

---@param bufnr integer
local function save(bufnr)
  local ok, err = pcall(api.nvim_buf_call, bufnr, function()
    vim.cmd("silent write")
  end)
  if not ok then
    notify.warn("save failed: " .. tostring(err))
    return
  end
  pcall(vim.cmd.redrawtabline)
end

---@param text string
local function copy(text)
  -- `+` raises on a machine with no clipboard provider; the unnamed register
  -- always works, so the copy is never a total loss.
  pcall(vim.fn.setreg, "+", text)
  vim.fn.setreg('"', text)
  notify.info("Copied: " .. text)
end

--- The "Reopen closed tab" submenu's items, newest close first -- one entry
--- per `ui.tabline.reopen` ring slot, each reopening exactly that entry (not
--- always the newest: `contextmenu.entry` is built with `entry.path` bound
--- into its own closure, so picking the third one down still reopens that
--- file, not whatever became newest by the time the menu was clicked).
--- Empty when nothing has been closed yet -- `contextmenu.submenu` then
--- drops the whole entry rather than showing a fly-out with nothing in it.
---@return Ui.ContextMenu.Item[]
local function reopen_items()
  local items = {}
  for _, entry in ipairs(reopen.list()) do
    -- ":~:." -- relative to cwd, falling back to "~/..." outside it: the
    -- same short, readable form the tab menu's own "Relative path" copy
    -- uses, so two files that share a bare name (already a real case: see
    -- `gen_unique_name` in ui.tabline.utils) still read as different entries.
    local label = vim.fn.fnamemodify(entry.path, ":~:.")
    items[#items + 1] = contextmenu.entry(true, label, function()
      reopen.reopen(entry)
    end)
  end
  return items
end

--- Send `bufnr` to a new tab page and drop it from this one's list.
---@param bufnr integer
local function move_to_new_tab(bufnr)
  state.goto_buf(bufnr)
  -- Captured before the move, for the same reason the `move_to_tab` keymap
  -- does: the move switches tabs, so the source cannot be read off the
  -- current state afterwards.
  local source_tab = api.nvim_get_current_tabpage()
  local ok, err = pcall(require("lib.nvim.buf_win_tab.move_buffer_to_tab"))
  if not ok then
    notify.warn("move to tab failed: " .. tostring(err))
    return
  end
  state.forget_buffer(bufnr, source_tab)
end

--- The menu for one chip, as a `ui.contextmenu` item list.
---@param bufnr integer
---@return Ui.ContextMenu.Item[]
function M.items(bufnr)
  local bufs = tab_bufs()
  local idx = state.index_of(bufnr)
  local total = #bufs
  local name = display_name(bufnr)
  local path = api.nvim_buf_get_name(bufnr)
  local has_file = path ~= ""

  local modified = vim.bo[bufnr].modified
  local has_saved, has_unsaved = false, false
  for _, b in ipairs(bufs) do
    if vim.bo[b].modified then
      has_unsaved = true
    else
      has_saved = true
    end
  end

  local function slice(from, to)
    local out = {}
    for i = from, to do
      out[#out + 1] = bufs[i]
    end
    return out
  end

  local items = {}

  local pinned = state.is_pinned(bufnr)

  contextmenu.group(
    items,
    contextmenu.heading(name),
    contextmenu.entry(modified and has_file and vim.bo[bufnr].buftype == "", "Save", function()
      save(bufnr)
    end, nil, icon("F0193", "S")),
    contextmenu.entry(true, pinned and "Unpin" or "Pin", function()
      state.toggle_pinned(bufnr)
    end, nil, icon("F0403", "P")),
    contextmenu.entry(true, "Close", function()
      utils.close_buffer(bufnr)
    end, nil, icon("F0156", "x"))
  )

  -- Every close SET below excludes pinned tabs (the roadmap's own
  -- recommendation: a pin should survive a bulk close, not just a stray
  -- click) -- `bufnr` itself is still offered plainly above via the
  -- unfiltered "Close" entry, pinned or not, since clicking that on a
  -- pinned tab's own menu is exactly the deliberate action `guard_pinned_close`
  -- (ui.tabline.utils) lets through.
  local others = vim.tbl_filter(function(b)
    return b ~= bufnr and not state.is_pinned(b)
  end, bufs)
  local left = idx
      and vim.tbl_filter(function(b)
        return not state.is_pinned(b)
      end, slice(1, idx - 1))
    or {}
  local right = idx
      and vim.tbl_filter(function(b)
        return not state.is_pinned(b)
      end, slice(idx + 1, total))
    or {}
  local saved = vim.tbl_filter(function(b)
    return not vim.bo[b].modified and not state.is_pinned(b)
  end, bufs)

  contextmenu.group(
    items,
    contextmenu.heading("Close"),
    contextmenu.entry(#others > 0, "Close others", function()
      close_set(others, bufnr)
    end),
    contextmenu.entry(#left > 0, "Close to the left", function()
      close_set(left, bufnr)
    end),
    contextmenu.entry(#right > 0, "Close to the right", function()
      close_set(right, bufnr)
    end),
    contextmenu.entry(has_saved and has_unsaved and #saved > 0, "Close saved", function()
      close_set(saved, bufnr)
    end)
  )

  contextmenu.group(
    items,
    contextmenu.heading("Move"),
    contextmenu.entry(total > 1, "Move to position…", function()
      prompt_move(bufnr)
    end, nil, icon("F04E1", "#")),
    contextmenu.entry(idx ~= nil and idx > 1, "Move left", function()
      state.move_buf_to(bufnr, idx - 1)
    end, nil, icon("F004D", "<")),
    contextmenu.entry(idx ~= nil and idx < total, "Move right", function()
      state.move_buf_to(bufnr, idx + 1)
    end, nil, icon("F0054", ">")),
    contextmenu.entry(idx ~= nil and idx > 1, "Move to start", function()
      state.move_buf_to(bufnr, 1)
    end),
    contextmenu.entry(idx ~= nil and idx < total, "Move to end", function()
      state.move_buf_to(bufnr, total)
    end)
  )

  local copy_items = {}
  contextmenu.group(
    copy_items,
    contextmenu.entry(has_file, "Absolute path", function()
      copy(vim.fn.fnamemodify(path, ":p"))
    end),
    contextmenu.entry(has_file, "Relative path", function()
      copy(vim.fn.fnamemodify(path, ":."))
    end),
    contextmenu.entry(has_file, "File name", function()
      copy(name)
    end)
  )

  contextmenu.group(
    items,
    contextmenu.heading("Buffer"),
    contextmenu.submenu("Copy path", copy_items, icon("F018F", "c")),
    contextmenu.entry(true, "Open in split", function()
      buffer_cmd("sbuffer", bufnr)
    end),
    contextmenu.entry(true, "Open in vertical split", function()
      buffer_cmd("vertical sbuffer", bufnr)
    end),
    contextmenu.entry(total > 1, "Move to new tab page", function()
      move_to_new_tab(bufnr)
    end),
    -- Not really about `bufnr` -- reopening a closed file lands wherever the
    -- CURRENT tab is, same as the `<leader>bu` keymap -- but it needs
    -- SOME chip's menu to hang off, and every chip's menu is otherwise
    -- already a function of the live `vim.t.bufs` regardless of which one
    -- was clicked.
    contextmenu.submenu("Reopen closed tab", reopen_items(), icon("F0713", "R"))
  )

  return items
end

--- Open the context menu for `bufnr`'s chip at the pointer. The chip stays lit
--- for as long as the menu is up, so it is never ambiguous which tab an entry
--- would act on.
---@param bufnr integer
---@return nil
function M.open(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ok, items = pcall(M.items, bufnr)
  if not ok then
    notify.error("building the tab menu failed: " .. tostring(items))
    return
  end
  if #items == 0 then
    return
  end

  local release = utils.hold(bufnr)
  local surf = contextmenu.open(items, { mouse = true })
  if surf and surf.on_close then
    surf:on_close(release)
  else
    -- nvzone/menu (or a disabled menu) hands back no close hook, so there is
    -- no telling when the menu goes away. A bounded highlight beats one that
    -- can stay lit on a chip for the rest of the session.
    vim.defer_fn(release, 1500)
  end
end

return M
