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
---@field from integer|nil         # the window the panel was opened from
---@field from_path string|nil     # its file, the default of `a`
---@field listener integer|nil
---@field suspended boolean        # another float (editor, menu) is open on the panel's behalf
---@field typed string              # the digits typed since the cursor last moved some other way
---@field typed_line integer|nil    # the line the typed number put the cursor on
local S = {
  surf = nil,
  numbers = {},
  from = nil,
  from_path = nil,
  listener = nil,
  suspended = false,
  typed = "",
  typed_line = nil,
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

--- One line per slot.
---@return string[] lines
---@return { row: integer, hl: string }[] marks
---@return integer[] numbers
local function build()
  local lines, marks, numbers = {}, {}, {}
  local here = vim.api.nvim_buf_get_name(
    S.from and api.nvim_win_is_valid(S.from) and api.nvim_win_get_buf(S.from) or 0
  )
  local normkey = require("lib.nvim.fs.normkey")
  local here_key = here ~= "" and normkey(here) or nil
  for _, slot in ipairs(store.list()) do
    local r = registry.render(slot)
    local text = registry.text(slot)
    local current_file = slot.kind == "file" and text and here_key and normkey(text) == here_key
    local label = tostring(r.label):gsub("%c", " ")
    local icon = tostring(r.icon):gsub("%c", " ")
    local flags = (slot.fixed and " fixed" or "") .. (r.missing and " ✗" or "")
    lines[#lines + 1] = ("%s%3d %s %s%s"):format(
      current_file and "•" or " ",
      slot.n,
      icon,
      label,
      flags
    )
    marks[#marks + 1] = { row = #lines - 1, hl = r.hl }
    numbers[#numbers + 1] = slot.n
  end
  if #lines == 0 then
    lines[1] = " no slots yet -- press a to add one"
    marks[1] = { row = 0, hl = "KitMuted" }
  end
  return lines, marks, numbers
end

--- Redraw the list; the cursor stays on the same slot.
---@param keep integer|nil  # slot number to put the cursor on
local function redraw(keep)
  if not M.is_open() then
    return
  end
  local want = keep or current()
  local lines, marks, numbers = build()
  S.numbers = numbers
  S.surf:set_lines(lines)
  api.nvim_buf_clear_namespace(S.surf.bufnr, NS, 0, -1)
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(S.surf.bufnr, NS, m.row, 0, {
      end_row = m.row,
      end_col = #lines[m.row + 1],
      hl_group = m.hl,
    })
  end
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
  pcall(api.nvim_win_set_cursor, S.surf.winid, { math.min(line, #lines), 0 })
end

function M.close()
  local surf = S.surf
  S.surf = nil
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
  S.suspended = true
  local surf = S.surf
  S.surf = nil
  if surf then
    surf:close()
  end
  S.suspended = false
  fn(function(n)
    M.open({ from = from, focus = n or keep })
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

--- The actions of the context menu, for a slot.
---@param n integer
---@return { label: string, run: fun() }[]
function M.actions(n)
  local slots = require("ui.slots")
  local slot = store.get(n)
  local list = {
    {
      label = "Apply",
      run = function()
        slots.apply(n)
      end,
    },
    {
      label = "Edit",
      run = function()
        require("ui.slots.view.editor").open({ n = n })
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

--- The context menu of one slot.
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
      a.run()
      if on_done then
        on_done()
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

  map("q", M.close, "close")
  map("<Esc>", M.close, "close")
end

--- Open the panel. The cursor goes to `opts.focus`, else to the slot of the file
--- you are in, else to the one run last, else to the first.
---@param opts { from?: integer, focus?: integer }|nil
function M.open(opts)
  opts = opts or {}
  if M.is_open() then
    M.close()
  end
  S.from = opts.from or api.nvim_get_current_win()
  local name = api.nvim_buf_get_name(api.nvim_win_get_buf(S.from))
  S.from_path = (name ~= "" and vim.bo[api.nvim_win_get_buf(S.from)].buftype == "")
      and vim.fs.normalize(name)
    or nil

  local cfg = config.get()
  local lines, marks, numbers = build()
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
  S.numbers = numbers
  S.typed = ""
  surf:on_close(function()
    if S.surf == surf then
      S.surf = nil
    end
    if S.listener then
      store.off(S.listener)
      S.listener = nil
    end
  end)
  attach_keys()

  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(surf.bufnr, NS, m.row, 0, {
      end_row = m.row,
      end_col = #lines[m.row + 1],
      hl_group = m.hl,
    })
  end

  -- Where to start: asked for, else the file you are in, else the last run.
  local want = opts.focus
  if not want then
    local here = S.from_path and require("lib.nvim.fs.normkey")(S.from_path)
    for _, slot in ipairs(store.list()) do
      if here and slot.kind == "file" then
        local text = registry.text(slot)
        if text and require("lib.nvim.fs.normkey")(text) == here then
          want = slot.n
          break
        end
      end
    end
  end
  want = want or require("ui.slots").last_applied()
  redraw(want)

  S.listener = store.on_change(function()
    vim.schedule(function()
      redraw()
    end)
  end)

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
