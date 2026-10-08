---@module 'ui.slots.view.panel'
--- The slot panel: the working view of the slots. A themed float docked at the
--- edge you chose (`side`), a quarter of the editor wide (`width`), one row per
--- slot, the cursor is the selection. You enter it, work in it, and it closes
--- when you leave it -- unlike the bar (`view.chips`), which only shows.
---
---   <CR> / double click   run the slot
---   0 .. 9                type a slot's number to put the cursor on it: `1` goes to slot 1,
---                         then `2` to slot 12 if there is one (a count before <CR> cannot
---                         work, the digits are taken)
---   e                     edit the slot (`view.editor`)
---   a                     add a slot (the editor; the file you came from is the default)
---   dd                    clear the slot
---   y                     copy what the slot stands for
---   K                     a preview pane beside the panel (follows the cursor; see `view.preview`)
---   <C-j> / <C-k>         move the slot down / up (swap with its neighbour)
---   right click           a menu for the slot under the pointer
---   q / <Esc>             close
---
--- All slots are listed, however many: the window scrolls with the cursor like
--- any other. The list is rebuilt whenever a slot changes while the panel is
--- open, and what the cursor is on is looked up from the slot's number at the
--- moment a key is pressed -- never from a line that may have gone stale.

require("ui.slots.@types")

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local store = require("ui.slots.store")

local api = vim.api

local M = {}

local NS = api.nvim_create_namespace("ui_slots_panel")

---@class Ui.Slots.Panel.State
---@field surf Ui.Kit.Surface|nil
---@field numbers integer[]        # line -> slot number
---@field list Ui.Slots.Slot[]      # line -> the slot (a copy), for the rows that are looked at closely
---@field refined table<integer, boolean>  # lines that have their full render (stat, current file)
---@field hl table<integer, string>        # line -> highlight group of a refined row
---@field rev integer               # moves with every redraw: a scheduled one of an older state is dropped
---@field scrolled_id integer|nil   # the WinScrolled autocmd of this panel window
---@field from integer|nil         # the window the panel was opened from
---@field from_path string|nil     # its file, the default of `a`
---@field listener integer|nil
---@field suspended boolean        # another float (editor, menu) is open on the panel's behalf
---@field typed string              # the digits typed since the cursor last moved some other way
---@field typed_line integer|nil    # the line the typed number put the cursor on
---@field geom table|nil            # the panel's rectangle, for the preview pane
---@field preview_on boolean         # the preview is wanted
---@field deb table|nil              # debounces the preview of `auto`
local S = {
  surf = nil,
  numbers = {},
  list = {},
  refined = {},
  hl = {},
  rev = 0,
  from = nil,
  from_path = nil,
  listener = nil,
  suspended = false,
  typed = "",
  typed_line = nil,
  geom = nil,
  preview_on = false,
  deb = nil,
}

---@return boolean
function M.is_open()
  return S.surf ~= nil and S.surf:is_valid()
end

--- The slot number the cursor is on, or nil (an empty list).
---@return integer|nil
local function current()
  if not M.is_open() then
    return nil
  end
  local line = api.nvim_win_get_cursor(S.surf.winid)[1]
  return S.numbers[line]
end

--- The placeholders as the window the panel came from sees them: `{dir}` of its
--- buffer, `{word}` under its cursor -- what <CR> will run with, not what the
--- (unnamed) panel buffer would give.
---@return { resolve: Ui.Slots.Ctx }
local function origin_context()
  local base = require("ui.slots.resolve").context()
  local from = S.from
  if not (from and api.nvim_win_is_valid(from)) then
    return { resolve = base }
  end
  local wrapped = {}
  for name, fn in pairs(base) do
    wrapped[name] = function()
      local ok, res = pcall(api.nvim_win_call, from, fn)
      return ok and res or nil
    end
  end
  return { resolve = wrapped }
end

--- Show, move or close the preview pane to follow the cursor (defined below).
---@type fun()
local update_preview

--- The text of one row.
---@param slot Ui.Slots.Slot
---@param r { label: any, icon: any, missing: boolean|nil }
---@param current_file boolean  # the file you came from
---@return string
local function row_text(slot, r, current_file)
  local label = tostring(r.label):gsub("%c", " ")
  local icon = tostring(r.icon):gsub("%c", " ")
  local flags = (slot.fixed and " fixed" or "") .. (r.missing and " ✗" or "")
  return ("%s%3d %s %s%s"):format(current_file and "•" or " ", slot.n, icon, label, flags)
end

--- One line per slot, made without asking the file system anything: the list
--- may hold ten thousand slots, and building it is paid on every open and every
--- change. The rows in view are looked at closely afterwards (`refine`).
---@return string[] lines
---@return integer[] numbers
---@return Ui.Slots.Slot[] list
local function build()
  local lines, numbers = {}, {}
  local list = store.list()
  for i, slot in ipairs(list) do
    lines[i] = row_text(slot, registry.render(slot, { cheap = true }), false)
    numbers[i] = slot.n
  end
  if #lines == 0 then
    lines[1] = " no slots yet -- press a to add one"
  end
  return lines, numbers, list
end

--- Give the rows in and around the window their full render: whether the file
--- is there, which one is the file you came from, the colour. A row that was
--- done stays done until the list is built again.
local function refine()
  if not M.is_open() then
    return
  end
  local buf, win = S.surf.bufnr, S.surf.winid
  local total = #S.list
  if total == 0 then
    api.nvim_buf_clear_namespace(buf, NS, 0, -1)
    local text = api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
    api.nvim_buf_set_extmark(buf, NS, 0, 0, { end_row = 0, end_col = #text, hl_group = "KitMuted" })
    return
  end
  local height = api.nvim_win_get_height(win)
  local cursor = api.nvim_win_get_cursor(win)[1]
  local top = vim.fn.getwininfo(win)[1].topline
  local first = math.max(1, math.min(cursor, top) - height)
  local last = math.min(total, math.max(cursor, top + height) + height)

  local todo = false
  for i = first, last do
    if not S.refined[i] then
      todo = true
      break
    end
  end
  if not todo then
    return
  end

  local normkey = require("lib.nvim.fs.normkey")
  local here_key
  local from = S.from
  if from and api.nvim_win_is_valid(from) then
    local name = api.nvim_buf_get_name(api.nvim_win_get_buf(from))
    here_key = name ~= "" and normkey(name) or nil
  end

  local rows = api.nvim_buf_get_lines(buf, first - 1, last, false)
  for i = first, last do
    if not S.refined[i] then
      local slot = S.list[i]
      local r = registry.render(slot)
      local current_file = false
      if here_key and slot.kind == "file" then
        local text = registry.text(slot)
        current_file = text ~= nil and text ~= "" and normkey(text) == here_key
      end
      rows[i - first + 1] = row_text(slot, r, current_file)
      S.hl[i] = r.hl
      S.refined[i] = true
    end
  end

  local was = api.nvim_get_option_value("modifiable", { buf = buf })
  api.nvim_set_option_value("modifiable", true, { buf = buf })
  local ok, err = pcall(api.nvim_buf_set_lines, buf, first - 1, last, false, rows)
  api.nvim_set_option_value("modifiable", was, { buf = buf })
  if not ok then
    error(err, 0)
  end
  api.nvim_buf_clear_namespace(buf, NS, first - 1, last)
  for i = first, last do
    local group = S.hl[i]
    if group then
      api.nvim_buf_set_extmark(buf, NS, i - 1, 0, {
        end_row = i - 1,
        end_col = #rows[i - first + 1],
        hl_group = group,
      })
    end
  end
end

--- Put the cursor on slot `want`, or the nearest one before it.
---@param want integer|nil
local function place(want)
  local numbers = S.numbers
  local line = 1
  for i, n in ipairs(numbers) do
    if n == want then
      line = i
      break
    end
    if want and n < want then
      line = i
    end
  end
  pcall(api.nvim_win_set_cursor, S.surf.winid, { math.min(line, math.max(#numbers, 1)), 0 })
end

--- Up to this many slots, the slot of the file you came from is found by real
--- path as well (a link to it, a placeholder); with more, by the path as written.
local EXACT_MAX = 200

--- The number of the file slot that points at the file the panel came from.
---@return integer|nil
local function find_current_slot()
  if not S.from_path then
    return nil
  end
  -- The placeholders as the window the panel came from sees them, not the
  -- panel's own (unnamed) buffer.
  local hit = require("ui.slots.kinds.file").matching(S.from_path, S.list, {
    first_only = true,
    exact_max = EXACT_MAX,
    link_max = EXACT_MAX,
    ctx = origin_context().resolve,
  })[1]
  return hit and hit.n or nil
end

--- Redraw the list; the cursor stays on the same slot.
---@param keep integer|nil  # slot number to put the cursor on
local function redraw(keep)
  if not M.is_open() then
    return
  end
  S.rev = S.rev + 1
  local want = keep or current()
  local lines, numbers, list = build()
  S.numbers, S.list, S.refined, S.hl = numbers, list, {}, {}
  S.surf:set_lines(lines)
  api.nvim_buf_clear_namespace(S.surf.bufnr, NS, 0, -1)
  place(want)
  refine()
  update_preview()
end

--- Show, move or close the preview pane to follow the cursor.
update_preview = function()
  local preview = require("ui.slots.view.preview")
  if not (M.is_open() and S.preview_on) then
    preview.close()
    return
  end
  local n = current()
  if not n then
    preview.close()
    return
  end
  preview.show(n, S.geom, origin_context())
end

--- The cursor moved: the preview follows, but a move within the row it already
--- shows (`h`/`l`) must not cancel the page that is on its way, or load it again.
local function follow_preview()
  local n = current()
  if
    n
    and package.loaded["ui.slots.view.preview"]
    and package.loaded["ui.slots.view.preview"].shown() == n
  then
    return
  end
  update_preview()
end

function M.close()
  local surf = S.surf
  S.surf = nil
  if S.deb then
    S.deb.cancel()
    S.deb = nil
  end
  if package.loaded["ui.slots.view.preview"] then
    package.loaded["ui.slots.view.preview"].close()
  end
  if surf then
    surf:close()
  end
end

--- Run `fn` while another float is open on the panel's behalf: the panel does
--- not close because the focus left it, and comes back afterwards.
---@param fn fun(back: fun(n: integer|nil))
---@param keep integer|nil
local function away(fn, keep)
  local from = S.from
  local preview_wanted = S.preview_on
  S.suspended = true
  local surf = S.surf
  S.surf = nil
  if package.loaded["ui.slots.view.preview"] then
    package.loaded["ui.slots.view.preview"].close()
  end
  if surf then
    surf:close()
  end
  S.suspended = false
  fn(function(n)
    M.open({ from = from, focus = n or keep, preview = preview_wanted })
  end)
end

---@param n integer
local function run(n)
  local from = S.from
  M.close()
  if from and api.nvim_win_is_valid(from) then
    pcall(api.nvim_set_current_win, from)
  end
  require("ui.slots").apply(n)
end

local function with_slot(fn)
  local n = current()
  if n then
    fn(n)
  end
end

--- The actions of the context menu, for a slot. `back` says how an action ends:
---   * (nothing) -- done at once, the panel may come back (Copy, Clear);
---   * `"stay"`  -- it moved the focus to its result (Apply, Open in ...): the
---     panel stays closed;
---   * `"editor"` -- it opens the editor, which brings the panel back when it
---     closes; `run(on_close)` takes that callback.
---@param n integer
---@return { label: string, back?: "stay"|"editor", run: fun(on_close: fun()|nil) }[]
function M.actions(n)
  local slots = require("ui.slots")
  local slot = store.get(n)
  local list = {
    {
      label = "Apply",
      back = "stay",
      run = function()
        slots.apply(n)
      end,
    },
    {
      label = "Edit",
      back = "editor",
      run = function(on_close)
        require("ui.slots.view.editor").open({
          n = n,
          on_close = on_close and function()
            on_close()
          end or nil,
        })
      end,
    },
    {
      label = "Copy",
      run = function()
        slots.yank(n)
      end,
    },
  }
  if slot and slot.kind == "file" then
    for _, where in ipairs({ "split", "vsplit", "tab" }) do
      list[#list + 1] = {
        label = "Open in " .. (where == "tab" and "a new tab" or "a " .. where),
        back = "stay",
        run = function()
          local copy = vim.deepcopy(slot)
          copy.target = where
          local ok, err = registry.apply(copy, {})
          if not ok then
            require("ui.slots.util").notify(("slot %d: %s"):format(n, err))
          end
        end,
      }
    end
  end
  list[#list + 1] = {
    label = "Clear",
    run = function()
      slots.clear(n)
    end,
  }
  return list
end

--- The context menu of one slot. `on_done` (the panel coming back) runs when the
--- menu is cancelled and after an action that is over at once; an action that
--- opens the editor hands it to the editor, one that moves the focus to its
--- result (Apply, Open in ...) does not call it.
---@param n integer
---@param on_done fun()|nil
function M.menu(n, on_done)
  require("ui.kit.select").open({
    title = ("slot %d"):format(n),
    items = M.actions(n),
    format_item = function(a)
      return a.label
    end,
    on_select = function(a)
      if a.back == "editor" then
        a.run(on_done)
      elseif a.back == "stay" then
        a.run()
      else
        a.run()
        if on_done then
          on_done()
        end
      end
    end,
    on_cancel = on_done,
  })
end

---@param key string
---@param fn function
---@param desc string
local function map(key, fn, desc)
  vim.keymap.set(
    "n",
    key,
    fn,
    { buffer = S.surf.bufnr, nowait = true, silent = true, desc = "ui.slots panel: " .. desc }
  )
end

local function attach_keys()
  map("<CR>", function()
    local n = current()
    if n then
      run(n)
    end
  end, "run the slot")
  map("<2-LeftMouse>", function()
    with_slot(run)
  end, "run the slot")

  -- A number is typed, digit by digit: "1" goes to slot 1, a "2" after it to slot
  -- 12 when there is one. A digit that makes no slot starts the number afresh.
  local function jump_to(n)
    for i, num in ipairs(S.numbers) do
      if num == n then
        api.nvim_win_set_cursor(S.surf.winid, { i, 0 })
        S.typed_line = i
        return true
      end
    end
    return false
  end
  for digit = 0, 9 do
    map(tostring(digit), function()
      -- Moved by some other key since the last digit: a new number starts.
      if S.typed_line ~= api.nvim_win_get_cursor(S.surf.winid)[1] then
        S.typed = ""
      end
      local typed = S.typed .. digit
      local n = tonumber(typed)
      if n and n >= 1 and jump_to(n) then
        S.typed = typed
        return
      end
      -- not a slot: maybe the first digit of a new number
      S.typed = ""
      local first = tonumber(tostring(digit))
      if first and first >= 1 and jump_to(first) then
        S.typed = tostring(digit)
        return
      end
      require("ui.slots.util").notify(("slot %s is empty"):format(typed))
    end, "type a slot number")
  end

  map("e", function()
    with_slot(function(n)
      local why = require("ui.slots.view.editor").refusal(n)
      if why then
        require("ui.slots.util").notify(why)
        return
      end
      away(function(back)
        require("ui.slots.view.editor").open({ n = n, on_close = back })
      end, n)
    end)
  end, "edit the slot")

  map("a", function()
    local path = S.from_path
    away(function(back)
      require("ui.slots.view.editor").open({
        defaults = path and { path = path } or nil,
        on_close = back,
      })
    end)
  end, "add a slot")

  map("dd", function()
    with_slot(function(n)
      local ok = require("ui.slots").clear(n)
      if ok then
        redraw()
      end
    end)
  end, "clear the slot")

  map("y", function()
    with_slot(function(n)
      require("ui.slots").yank(n)
    end)
  end, "copy what the slot stands for")

  local function move(delta)
    with_slot(function(n)
      local line = api.nvim_win_get_cursor(S.surf.winid)[1]
      local other = S.numbers[line + delta]
      if not other then
        return
      end
      local ok, err = store.move(n, other)
      if not ok then
        require("ui.slots.util").notify(err)
        return
      end
      -- the two swapped numbers: the slot that was moved now sits at `other`
      redraw(other)
    end)
  end
  map("<C-j>", function()
    move(1)
  end, "move the slot down")
  map("<C-k>", function()
    move(-1)
  end, "move the slot up")

  map("<RightMouse>", function()
    local pos = vim.fn.getmousepos()
    if pos.winid ~= S.surf.winid then
      -- Outside the panel: it is left, as a left click would leave it.
      M.close()
      return
    end
    local n = S.numbers[pos.line]
    if not n then
      return
    end
    pcall(api.nvim_win_set_cursor, S.surf.winid, { pos.line, 0 })
    away(function(back)
      M.menu(n, function()
        back(n)
      end)
    end, n)
  end, "menu of the slot under the pointer")

  map("K", function()
    local mode = config.get().preview.mode
    if mode == "off" then
      require("ui.slots.util").notify('the preview is switched off (preview.mode = "off")')
      return
    end
    S.preview_on = not S.preview_on
    update_preview()
    if S.preview_on and current() and not require("ui.slots.view.preview").is_open() then
      S.preview_on = false
      require("ui.slots.util").notify("no room beside the panel for a preview")
    end
  end, "show / hide the preview")

  map("q", M.close, "close")
  map("<Esc>", M.close, "close")
end

--- Open the panel. The cursor goes to `opts.focus`, else to the slot of the file
--- you are in, else to the one run last, else to the first.
---@param opts { from?: integer, focus?: integer, preview?: boolean }|nil
function M.open(opts)
  opts = opts or {}
  if M.is_open() then
    M.close()
  end
  -- The window the panel came from may be gone (a float that closed, a window
  -- closed while the editor was open): then the current one is the origin.
  S.from = (opts.from and api.nvim_win_is_valid(opts.from)) and opts.from
    or api.nvim_get_current_win()
  local name = api.nvim_buf_get_name(api.nvim_win_get_buf(S.from))
  S.from_path = (name ~= "" and vim.bo[api.nvim_win_get_buf(S.from)].buftype == "")
      and vim.fs.normalize(name)
    or nil

  local cfg = config.get()
  local lines, numbers, list = build()
  local width = cfg.width
  if width <= 1 then
    width = math.floor(vim.o.columns * width)
  end
  width = math.max(28, math.min(math.floor(width), vim.o.columns - 6))
  local row0 = (
    vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1)
  )
      and 1
    or 0
  local avail = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - row0 - 2
  local height = math.max(3, math.min(avail, math.max(#lines, 8)))

  local surf = require("ui.kit.surface").open({
    lines = lines,
    title = " Slots ",
    relative = "editor",
    row = row0,
    col = cfg.side == "left" and 0 or math.max(0, vim.o.columns - width - 2),
    width = width,
    height = height,
    enter = true,
    modifiable = false,
    wo = { cursorline = true, wrap = false },
  })
  if not surf then
    return
  end
  S.surf = surf
  S.numbers, S.list, S.refined, S.hl = numbers, list, {}, {}
  S.typed = ""
  S.geom = {
    row = row0,
    col = cfg.side == "left" and 0 or math.max(0, vim.o.columns - width - 2),
    width = width + 2,
    height = height,
    side = cfg.side,
  }
  if opts.preview ~= nil then
    S.preview_on = opts.preview and cfg.preview.mode ~= "off"
  else
    S.preview_on = cfg.preview.mode == "auto"
  end
  surf:on_close(function()
    if S.deb then
      S.deb.cancel()
      S.deb = nil
    end
    if package.loaded["ui.slots.view.preview"] then
      package.loaded["ui.slots.view.preview"].close()
    end
    if S.surf == surf then
      S.surf = nil
    end
    if S.listener then
      store.off(S.listener)
      S.listener = nil
    end
    if S.scrolled_id then
      require("lib.nvim.bindings.autocmd").delete(S.scrolled_id)
      S.scrolled_id = nil
    end
  end)
  attach_keys()

  -- Where to start: asked for, else the file you are in, else the last run.
  local want = opts.focus or find_current_slot() or require("ui.slots").last_applied()
  place(want)
  refine()
  update_preview()

  -- A change is redrawn once, and not at all when the panel redrew itself after
  -- making it (`dd`, move): that redraw already shows the final state.
  S.listener = store.on_change(function()
    local rev = S.rev
    vim.schedule(function()
      if S.rev == rev then
        redraw()
      end
    end)
  end)

  -- The rows in view are looked at closely as they come into view.
  require("lib.nvim.bindings.autocmd").create("CursorMoved", refine, {
    buffer = surf.bufnr,
    record = false,
    desc = "ui.slots panel: full render of the rows in view",
  })
  S.scrolled_id = require("lib.nvim.bindings.autocmd").create("WinScrolled", refine, {
    pattern = tostring(surf.winid),
    record = false,
    desc = "ui.slots panel: full render of the rows in view",
  })

  -- The preview follows the cursor: at once with `K`, after `preview.delay` in
  -- `auto` mode (a cursor held down a list does not read a file per row).
  local pv = cfg.preview
  if pv.mode ~= "off" and pv.delay > 0 then
    S.deb = require("lib.nvim.debounce").new(follow_preview, pv.delay)
  end
  require("lib.nvim.bindings.autocmd").create("CursorMoved", function()
    if not S.preview_on then
      return
    end
    if S.deb then
      S.deb.call()
    else
      follow_preview()
    end
  end, {
    buffer = surf.bufnr,
    record = false,
    desc = "ui.slots panel: the preview follows the cursor",
  })

  -- Leaving the panel closes it (the editor and the menu it opens itself are
  -- the exception: they come back to it).
  require("lib.nvim.bindings.autocmd").create("WinLeave", function()
    vim.schedule(function()
      if S.surf == surf and not S.suspended and api.nvim_get_current_win() ~= surf.winid then
        M.close()
      end
    end)
  end, {
    buffer = surf.bufnr,
    once = true,
    record = false,
    desc = "ui.slots panel: close when the focus leaves",
  })
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

--- The lines the panel shows, for specs.
---@return string[]
function M.lines()
  if not M.is_open() then
    return {}
  end
  return api.nvim_buf_get_lines(S.surf.bufnr, 0, -1, false)
end

--- The slot number the cursor is on, for specs.
---@return integer|nil
function M.current()
  return current()
end

function M.reset()
  M.close()
  S.numbers, S.from, S.from_path, S.suspended, S.typed, S.typed_line = {}, nil, nil, false, "", nil
end

return M
