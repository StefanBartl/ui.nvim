---@module 'ui.slots.view.chips'
--- The slot bar: one float at the edge of the editor, a chip per slot -- number,
--- icon, label -- stacked from the top. Not a window anyone works in: it takes
--- clicks and the wheel, and hands the focus straight back.
---
--- **One window, many chips.** The chips are lines of a single scratch buffer
--- (borders drawn in the text), not one float each: one geometry to keep right,
--- one thing to hit-test, one thing to clean up.
---
--- **Accordion, no upper bound.** The bar shows as many slots as the editor has
--- rows. With more, it is a window over the sorted list that moves one slot at a
--- time -- the top one drops out, the next comes in at the bottom -- and follows
--- the *focus slot* (the one applied last, else the one of the current file) so
--- it is never out of sight. `▲ +n` / `▼ +n` rows say what is hidden; a click on
--- one of them, or the wheel over the bar, scrolls by one.
---
--- **Mouse without a mapping, without focus.** The bar is not focusable: it is
--- not in the window cycle (`<C-w>w`, `:windo`) and a click never enters it. A
--- buffer-local `<LeftMouse>` map would only be read for the CURRENT buffer and a
--- global one would take over every click, so `vim.on_key` is used instead: it
--- sees the mouse keys first, `getmousepos()` gives the screen cell (for a window
--- that is not focusable `winid` names the window UNDER it, so the cell is
--- compared with the bar's own rectangle), and a key that lands on the bar is
--- answered here and *discarded* (the listener returns `""`) -- it does not move
--- the cursor in the code below, does not open Neovim's own popup menu on a right
--- click, and is not seen by the general `<RightMouse>` menu (`ui.menu`), which
--- also asks `pointer_on_bar()` before it opens. A press that began on the bar
--- takes its drag and release with it.
---
--- Two limits, both on the user's side: Neovim before 0.11 ignores the "" (a click
--- on the bar then also reaches the code under it; a notice says so), and a mouse
--- key that the user mapped to SEVERAL keys (`<RightMouse>` -> `<LeftMouse><Cmd>popup
--- PopUp<CR>`) loses only its first key to the discard: the rest of the sequence
--- arrives as typed input and runs.
---
--- No timer: the bar redraws on events (buffer and tab changes, saves, a slot
--- changing, a resize), coalesced into one redraw per tick.

require("ui.slots.@types")

local autocmd = require("lib.nvim.bindings.autocmd")
local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local store = require("ui.slots.store")

local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

local NS = api.nvim_create_namespace("ui_slots_bar")
local KEY_NS = api.nvim_create_namespace("ui_slots_bar_keys")
local GROUP = "ui_slots_bar"

--- The look of a chip. `h` is how many rows one chip takes.
local SHAPES = {
  rounded = {
    h = 3,
    tl = "╭",
    t = "─",
    tr = "╮",
    l = "│",
    r = "│",
    bl = "╰",
    b = "─",
    br = "╯",
  },
  double = {
    h = 3,
    tl = "╔",
    t = "═",
    tr = "╗",
    l = "║",
    r = "║",
    bl = "╚",
    b = "═",
    br = "╝",
  },
  ascii = { h = 3, tl = "+", t = "-", tr = "+", l = "|", r = "|", bl = "+", b = "-", br = "+" },
  solid = { h = 1, solid = true },
  minimal = { h = 1 },
}

--- The vocabulary `ui.kit.presets` uses for chips, mapped onto the shapes above.
local ALIASES = { rounded_chip = "rounded", chip = "solid", classic = "minimal" }

local MIN_WIDTH = 10
local STAT_TTL_MS = 1000

---@class Ui.Slots.Chips.State
---@field want boolean              # the bar is switched on (toggle), whether or not there is anything to show
---@field win integer|nil
---@field buf integer|nil
---@field top_n integer|nil         # slot number of the first slot shown
---@field focus_n integer|nil       # the slot the bar keeps in sight
---@field rows table<integer, { kind: string, n?: integer }>  # buffer line -> what a click there means
---@field pending boolean
---@field attached boolean
---@field listener integer|nil
---@field width_floor integer|nil   # the widest the bar has been since the slots last changed
---@field render_cache table<integer, { sig: string, t: integer, r: table }>
---@field key_cache table<string, string|false>
---@field solid_groups table<string, string>
---@field bad_style table<string, boolean>
---@field pressed boolean            # a mouse press began on the bar and its release is still to come
---@field recolor boolean
---@field themed boolean            # the Kit* groups were defined for this colour scheme
---@field bad_draw boolean
---@field told_discard boolean
local S = {
  want = false,
  win = nil,
  buf = nil,
  top_n = nil,
  focus_n = nil,
  rows = {},
  pending = false,
  attached = false,
  listener = nil,
  render_cache = {},
  key_cache = {},
  solid_groups = {},
  bad_style = {},
  pressed = false,
  recolor = false,
  themed = false,
  bad_draw = false,
  told_discard = false,
}

-- Text helpers ----------------------------------------------------------

--- `text` cut to `w` display cells (with an ellipsis) and padded to exactly `w`.
---@param text string
---@param w integer
---@return string
local function fit(text, w)
  if w < 1 then
    return ""
  end
  local dw = vim.fn.strdisplaywidth(text)
  if dw > w then
    local chars = vim.fn.strchars(text)
    while chars > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, chars) .. "…") > w do
      chars = chars - 1
    end
    text = vim.fn.strcharpart(text, 0, chars) .. "…"
    dw = vim.fn.strdisplaywidth(text)
  end
  return text .. string.rep(" ", math.max(0, w - dw))
end

--- The shape a style name stands for; an unknown one falls back to `rounded`
--- and is said once.
---@param style any
---@return string name
---@return table shape
local function shape_of(style)
  if type(style) == "table" then
    style = style.shape or style.name
  end
  if type(style) ~= "string" then
    style = "rounded"
  end
  local name = ALIASES[style] or style
  if not SHAPES[name] then
    if not S.bad_style[style] then
      S.bad_style[style] = true
      vim.notify(
        ("[ui.slots] style '%s' is not one of rounded, double, ascii, solid, minimal"):format(style),
        vim.log.levels.WARN
      )
    end
    name = "rounded"
  end
  return name, SHAPES[name]
end

--- A group that shows `hl` as a filled block: its colour as the background.
---@param hl string
---@return string
local function solid_group(hl)
  local name = S.solid_groups[hl]
  -- (`:colorscheme` clears the groups; the handler for it is only attached while
  -- the bar is open)
  if name and next(api.nvim_get_hl(0, { name = name })) ~= nil then
    return name
  end
  local fg = api.nvim_get_hl(0, { name = hl, link = false }).fg
  if not fg then
    -- Not (yet) a colour: a group that is always there, and ask again next time.
    return "Visual"
  end
  local text = api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg
    or api.nvim_get_hl(0, { name = "Normal", link = false }).bg
  name = "UiSlotsSolid_" .. hl
  if fg and text then
    api.nvim_set_hl(0, name, { fg = text, bg = fg })
  else
    -- A transparent Normal has no background to use as the text colour: reverse
    -- video puts the text colour on the block and the terminal's own behind it.
    api.nvim_set_hl(0, name, { fg = fg, reverse = true })
  end
  S.solid_groups[hl] = name
  return name
end

-- What to draw ----------------------------------------------------------

---@param slot table
---@return string signature of what `render` depends on
local function signature(slot)
  return table.concat({
    tostring(slot.kind),
    tostring(slot.path or slot.index or slot.url or slot.cmd or slot.text or ""),
    tostring(slot.label or ""),
  }, "\0")
end

--- `registry.render`, with the answer for file and mark slots kept for a second:
--- it asks the filesystem, and a redraw happens on every buffer change.
---@param slot table
---@return table
local function render(slot)
  -- A path with a placeholder depends on the buffer you are in: not remembered.
  if type(slot.path) == "string" and slot.path:find("{", 1, true) then
    return registry.render(slot)
  end
  local cached = S.render_cache[slot.n]
  local now = uv.now()
  local sig = signature(slot)
  if cached and cached.sig == sig and now - cached.t < STAT_TTL_MS then
    return cached.r
  end
  local r = registry.render(slot)
  S.render_cache[slot.n] = { sig = sig, t = now, r = r }
  return r
end

--- The canonical key of the file a file slot points at, or nil when that cannot
--- be known without running placeholders.
---@param slot table
---@return string|nil
local function file_key(slot)
  if slot.kind ~= "file" or type(slot.path) ~= "string" then
    return nil
  end
  local cached = S.key_cache[slot.path]
  if cached ~= nil then
    return cached or nil
  end
  local key = false
  if not require("ui.slots.resolve").has_placeholder(slot.path) then
    local text = registry.text(slot)
    if text and text ~= "" then
      key = require("lib.nvim.fs.normkey")(text)
    end
  end
  S.key_cache[slot.path] = key
  return key or nil
end

--- Keys of the files with unsaved changes.
---@return table<string, boolean>
local function modified_keys()
  local out = {}
  local normkey = require("lib.nvim.fs.normkey")
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified and vim.bo[buf].buftype == "" then
      local name = api.nvim_buf_get_name(buf)
      if name ~= "" then
        out[normkey(name)] = true
      end
    end
  end
  return out
end

--- Text that goes on one line of the bar: a string, with control characters
--- (a newline, a tab, a NUL) turned into spaces.
---@param v any
---@return string
local function one_line(v)
  if type(v) ~= "string" then
    v = v == nil and "" or tostring(v)
  end
  return (v:gsub("%c", " "))
end

--- The text of one chip.
---@param slot table
---@param r table  # `registry.render`
---@param current boolean
---@param dirty boolean  # the file has unsaved changes
---@return string
local function chip_text(slot, r, current, dirty)
  local icon = one_line(r.icon)
  local parts = { current and "• " or "  ", tostring(slot.n) }
  if icon ~= "" then
    parts[#parts + 1] = " " .. icon
  end
  parts[#parts + 1] = " " .. one_line(r.label)
  if dirty then
    parts[#parts + 1] = " +"
  end
  if r.missing then
    parts[#parts + 1] = " ✗"
  end
  return table.concat(parts)
end

--- One entry per slot, ascending, made without asking the file system anything:
--- what a chip would say as written, and how tall it is. A list may hold ten
--- thousand slots and this runs on every redraw; the chips that are drawn get
--- their real text (is the file there, is it the current one, is it modified)
--- from `materialize`.
---@param flat boolean|nil  # one row per slot whatever the style says (no room for borders)
---@return { n: integer, slot: table, full: boolean, text: string, hl: string, current: boolean, missing: boolean, shape: table, shape_name: string, h: integer }[]
local function describe(flat)
  local cfg = config.get()
  local out = {}
  for _, slot in ipairs(store.list()) do
    local r = registry.render(slot, { cheap = true })
    local shape_name, shape = shape_of(slot.style or cfg.style)
    if flat then
      shape_name, shape = "minimal", SHAPES.minimal
    end
    out[#out + 1] = {
      n = slot.n,
      slot = slot,
      full = false,
      text = chip_text(slot, r, false, false),
      hl = type(r.hl) == "string" and r.hl or "KitMuted",
      current = false,
      missing = false,
      shape = shape,
      shape_name = shape_name,
      h = shape.h,
    }
  end
  return out
end

--- Give the entries `first` to `last` their real text.
---@param descs table[]
---@param first integer
---@param last integer
local function materialize(descs, first, last)
  local todo = {}
  for i = first, math.min(last, #descs) do
    if not descs[i].full then
      todo[#todo + 1] = descs[i]
    end
  end
  if #todo == 0 then
    return
  end
  local normkey = require("lib.nvim.fs.normkey")
  local name = api.nvim_buf_get_name(0)
  local here = (name ~= "" and vim.bo.buftype == "") and normkey(name) or nil
  local dirty = modified_keys()
  for _, d in ipairs(todo) do
    local slot = d.slot
    local r = render(slot)
    local key = file_key(slot)
    d.current = here ~= nil and key == here
    d.missing = r.missing == true
    d.hl = type(r.hl) == "string" and r.hl or "KitMuted"
    d.text = chip_text(slot, r, d.current, key ~= nil and dirty[key] == true)
    d.full = true
  end
end

-- Geometry --------------------------------------------------------------

--- Row of the first line and the rows that are free, from the editor's chrome.
---@return integer row0
---@return integer avail
local function room()
  local row0 = 0
  if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #api.nvim_list_tabpages() > 1) then
    row0 = 1
  end
  local avail = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - row0
  return row0, math.max(1, avail)
end

--- How wide the chips are: the widest text, within the configured cap.
---@param descs table[]
---@return integer
local function chip_width(descs)
  local cfg = config.get()
  local cap = cfg.width
  if cap <= 1 then
    cap = math.floor(vim.o.columns * cap)
  end
  cap = math.max(MIN_WIDTH, math.min(math.floor(cap), vim.o.columns - 2))
  local want = MIN_WIDTH
  local side_width = {}
  for _, d in ipairs(descs) do
    local sides = side_width[d.shape]
    if sides == nil then
      sides = d.shape.l and (vim.fn.strdisplaywidth(d.shape.l) + vim.fn.strdisplaywidth(d.shape.r))
        or 0
      side_width[d.shape] = sides
    end
    -- Plain ASCII (the control characters are gone) is as wide as it is long;
    -- only a text with other bytes is measured, and only if it could be widest
    -- (anything shown as <xxxx> is wider than its bytes, so no byte bound holds).
    local text = d.text
    if not text:find("[\128-\255]") then
      want = math.max(want, #text + 2 + sides)
    else
      want = math.max(want, vim.fn.strdisplaywidth(text) + 2 + sides)
    end
  end
  -- A border glyph two cells wide (ambiwidth = "double") must divide the width
  -- between the corners, or the right edge sits one cell off: up when the text
  -- needs the cell, down when the cap does not allow it.
  local gw, corners = 1, 0
  for _, d in ipairs(descs) do
    if d.h == 3 then
      gw = math.max(1, vim.fn.strdisplaywidth(d.shape.t))
      corners = vim.fn.strdisplaywidth(d.shape.tl) + vim.fn.strdisplaywidth(d.shape.tr)
      break
    end
  end
  local function aligned(width, up)
    local rest = (width - corners) % gw
    if rest == 0 then
      return width
    end
    return up and width + (gw - rest) or width - rest
  end
  cap = math.max(cap, MIN_WIDTH)
  local up = aligned(want, true)
  if up <= cap then
    return up
  end
  return math.max(aligned(cap, false), 1)
end

--- Which slots fit from `top` on, with a row kept for the counters that are
--- needed. Always at least the first one.
---@param descs table[]
---@param top integer
---@param avail integer
---@return integer first
---@return integer last
function M._range(descs, top, avail)
  local n = #descs
  local used = top > 1 and 1 or 0
  local last = top - 1
  while last < n do
    local h = descs[last + 1].h
    local more_after = last + 1 < n
    if used + h + (more_after and 1 or 0) > avail then
      break
    end
    used = used + h
    last = last + 1
  end
  if last < top then
    last = top
  end
  return top, last
end

--- Index of the first slot whose number is `n` or higher.
---@param descs table[]
---@param n integer|nil
---@return integer
local function index_from(descs, n)
  if not n then
    return 1
  end
  for i, d in ipairs(descs) do
    if d.n >= n then
      return i
    end
  end
  return math.max(1, #descs)
end

--- Pull the window up while the end of the list leaves room below it: no empty
--- space at the bottom with slots hidden above.
---@param descs table[]
---@param top integer
---@param avail integer
---@return integer
local function settle(descs, top, avail)
  top = math.max(1, math.min(top, math.max(1, #descs)))
  while top > 1 do
    local _, last = M._range(descs, top - 1, avail)
    if last >= #descs then
      top = top - 1
    else
      break
    end
  end
  return top
end

--- Move the window as little as possible so slot index `target` is shown.
---@param descs table[]
---@param top integer
---@param avail integer
---@param target integer
---@return integer
local function reveal(descs, top, avail, target)
  if target < top then
    return target
  end
  local _, last = M._range(descs, top, avail)
  while last < target and top < target do
    top = top + 1
    _, last = M._range(descs, top, avail)
  end
  return top
end

-- Drawing ---------------------------------------------------------------

--- A line of exactly `width` cells: `line` and spaces.
---@param line string
---@param width integer
---@return string
local function pad(line, width)
  return line .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(line)))
end

---@param descs table[]
---@param top integer
---@param last integer
---@param width integer
---@param counters boolean  # draw the "▲ +n" / "▼ +n" rows
---@return string[] lines
---@return { row: integer, hl: string }[] marks
---@return table<integer, { kind: string, n?: integer }> rows
local function build(descs, top, last, width, counters)
  local lines, marks, rows = {}, {}, {}
  local w = vim.fn.strdisplaywidth
  local function add(line, hl, row)
    lines[#lines + 1] = line
    marks[#marks + 1] = { row = #lines - 1, hl = hl }
    rows[#lines] = row
  end

  if counters and top > 1 then
    add(fit(("▲ +%d"):format(top - 1), width), "KitMuted", { kind = "up" })
  end
  for i = top, last do
    local d = descs[i]
    local sh = d.shape
    local row = { kind = "slot", n = d.n }
    if d.h == 3 then
      -- Glyph widths, not "one cell": with 'ambiwidth' = "double" a box character
      -- is two cells wide.
      local across = math.max(0, math.floor((width - w(sh.tl) - w(sh.tr)) / math.max(1, w(sh.t))))
      local across_b = math.max(0, math.floor((width - w(sh.bl) - w(sh.br)) / math.max(1, w(sh.b))))
      local body_hl = d.current and "KitSelection" or d.hl
      add(pad(sh.tl .. string.rep(sh.t, across) .. sh.tr, width), d.hl, row)
      add(sh.l .. " " .. fit(d.text, width - w(sh.l) - w(sh.r) - 2) .. " " .. sh.r, body_hl, row)
      add(pad(sh.bl .. string.rep(sh.b, across_b) .. sh.br, width), d.hl, row)
    else
      local hl = d.current and "KitSelection" or d.hl
      if sh.solid and not d.current then
        hl = solid_group(d.hl)
      end
      add(" " .. fit(d.text, width - 2) .. " ", hl, row)
    end
  end
  if counters and last < #descs then
    add(fit(("▼ +%d"):format(#descs - last), width), "KitMuted", { kind = "down" })
  end
  return lines, marks, rows
end

---@return boolean
local function win_alive()
  return S.win ~= nil and api.nvim_win_is_valid(S.win)
end

local function close_window()
  if win_alive() then
    pcall(api.nvim_win_close, S.win, true)
  end
  S.win, S.buf, S.rows, S.pressed = nil, nil, {}, false
end

--- Make sure the float exists, on the current tab page.
---@param cfg table  # nvim_open_win config
local function ensure_window(cfg)
  if win_alive() and api.nvim_win_get_tabpage(S.win) ~= api.nvim_get_current_tabpage() then
    -- A float belongs to the tab page it was opened in.
    close_window()
  end
  if win_alive() then
    api.nvim_win_set_config(S.win, cfg)
    return
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  S.buf = buf
  S.win = api.nvim_open_win(
    buf,
    false,
    vim.tbl_extend("force", cfg, {
      focusable = false,
      style = "minimal",
      border = "none",
      zindex = 40,
      noautocmd = true,
    })
  )
  vim.wo[S.win].wrap = false
  vim.wo[S.win].cursorline = false
  M._theme()
end

--- (Re)define the `Kit*` groups the chips use and point the float at them.
function M._theme()
  if win_alive() then
    local theme = require("ui.kit.theme")
    pcall(theme.apply, S.win, theme.resolve(nil))
  end
end

--- Draw the bar now.
---@param delta integer|nil  # move the window by this many slots first
function M.refresh(delta)
  if not S.want then
    return
  end
  if not S.themed then
    -- The `Kit*` groups the chips are drawn with exist from here on, before the first
    -- chip is built (a solid chip reads their colours).
    local theme = require("ui.kit.theme")
    pcall(function()
      theme.materialize(theme.resolve(nil))
    end)
    S.themed = true
  end
  local row0, avail = room()
  -- Under three free rows a bordered chip does not fit: one row per slot then.
  local descs = describe(avail < 3)
  if #descs == 0 then
    close_window()
    return
  end

  local top = index_from(descs, S.top_n)
  top = settle(descs, top + (delta or 0), avail)
  if S.focus_n then
    top = reveal(descs, top, avail, index_from(descs, S.focus_n))
  end
  local first, last = M._range(descs, top, avail)
  S.top_n = descs[first].n
  materialize(descs, first, last)
  -- The width does not shrink while the list is only scrolled with the wheel: a
  -- chip with a flag (a missing file, unsaved changes) is wider than its text as
  -- written, and the bar would jump by a cell or two as such chips come into view
  -- and leave.
  local width = chip_width(descs)
  if delta then
    width = math.max(width, S.width_floor or 0)
  end
  S.width_floor = width

  local lines, marks, rows = build(descs, first, last, width, true)
  if #lines > avail then
    -- Only the counters made it too tall (an editor a few rows high): the slot
    -- itself matters more than saying what is hidden.
    lines, marks, rows = build(descs, first, last, width, false)
  end
  local side = config.get().side
  ensure_window({
    relative = "editor",
    row = row0,
    col = side == "left" and 0 or math.max(0, vim.o.columns - width),
    width = width,
    height = math.max(1, math.min(#lines, avail)),
  })

  S.rows = rows
  if S.recolor then
    S.recolor = false
    M._theme()
  end
  local buf = S.buf
  vim.bo[buf].modifiable = true
  local ok, err = pcall(api.nvim_buf_set_lines, buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if not ok then
    -- A line the buffer refuses must not leave the bar half drawn and the
    -- buffer writable; say it once and try again on the next change.
    if not S.bad_draw then
      S.bad_draw = true
      vim.notify("[ui.slots] the bar could not be drawn: " .. tostring(err), vim.log.levels.WARN)
    end
    return
  end
  S.bad_draw = false
  api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for _, m in ipairs(marks) do
    api.nvim_buf_set_extmark(buf, NS, m.row, 0, {
      end_row = m.row,
      end_col = #lines[m.row + 1],
      hl_group = m.hl,
    })
  end
end

--- One redraw for any number of requests in a tick.
local function schedule()
  if S.pending then
    return
  end
  S.pending = true
  vim.schedule(function()
    S.pending = false
    M.refresh()
  end)
end

-- Focus and scrolling ---------------------------------------------------

--- Keep slot `n` in sight (the one just applied, or the current file's).
---@param n integer|nil
function M.set_focus(n)
  S.focus_n = n
  if S.want then
    schedule()
  end
end

--- Move the window over the list by `delta` slots.
---@param delta integer
function M.scroll(delta)
  -- A wheel turn is a request to look elsewhere: the focus must not pull the
  -- window straight back.
  S.focus_n = nil
  M.refresh(delta)
end

-- Mouse -----------------------------------------------------------------

--- The z-index of the bar's float: a float above it takes the click.
local BAR_ZINDEX = 40

--- Which line of the bar the pointer is on, or nil when it is not on the bar.
--- The bar is not focusable, so `getmousepos().winid` is the window under it;
--- the screen cell is compared with the bar's own rectangle. A focusable float
--- stacked above the bar (a menu, a popup) is reported as the window under the
--- pointer and takes the click.
---@return integer|nil
local function bar_line()
  if not win_alive() then
    return nil
  end
  local ok, pos = pcall(vim.fn.getmousepos)
  if not ok or type(pos) ~= "table" or not pos.screenrow or not pos.screencol then
    return nil
  end
  local at = api.nvim_win_get_position(S.win)
  local line, col = pos.screenrow - at[1], pos.screencol - at[2]
  if
    line < 1
    or line > api.nvim_win_get_height(S.win)
    or col < 1
    or col > api.nvim_win_get_width(S.win)
  then
    return nil
  end
  local under = pos.winid
  if under and under ~= 0 and api.nvim_win_is_valid(under) then
    local cfg = api.nvim_win_get_config(under)
    if cfg.relative ~= "" and (cfg.zindex or 50) >= BAR_ZINDEX then
      return nil
    end
  end
  return line
end

---@return boolean
function M.pointer_on_bar()
  return bar_line() ~= nil
end

--- What a right click on a chip offers: the menu the panel has, too.
---@param n integer
local function slot_menu(n)
  require("ui.slots.view.panel").menu(n)
end

--- Answer a click, a right click or a wheel turn on the bar.
---@param base string  # "LeftMouse", "RightMouse", "ScrollWheelUp", ...
---@param item { kind: string, n?: integer }|nil
local function on_pointer(base, item)
  if base == "ScrollWheelUp" then
    return M.scroll(-1)
  elseif base == "ScrollWheelDown" then
    return M.scroll(1)
  end
  if not item then
    return
  end
  if base == "LeftMouse" then
    if item.kind == "up" then
      return M.scroll(-1)
    elseif item.kind == "down" then
      return M.scroll(1)
    elseif item.kind == "slot" and item.n then
      require("ui.slots").apply(item.n)
    end
  elseif base == "RightMouse" and item.kind == "slot" and item.n then
    slot_menu(item.n)
  end
end

local PRESS =
  { LeftMouse = true, RightMouse = true, MiddleMouse = true, X1Mouse = true, X2Mouse = true }
local FOLLOW = {
  LeftDrag = true,
  RightDrag = true,
  MiddleDrag = true,
  LeftRelease = true,
  RightRelease = true,
  MiddleRelease = true,
  X1Drag = true,
  X2Drag = true,
  X1Release = true,
  X2Release = true,
}
local WHEEL = {
  ScrollWheelUp = true,
  ScrollWheelDown = true,
  ScrollWheelLeft = true,
  ScrollWheelRight = true,
}

--- Split a key name into its mouse key and whether it is a plain (or multi-)
--- click: `<2-LeftMouse>` is a fast second click and counts as a click again;
--- `<C-LeftMouse>` is something else and is only kept away from the code below.
---@param name string
---@return string|nil base
---@return boolean plain
local function classify(name)
  local inner = name:match("^<(.*)>$")
  if not inner then
    return nil, false
  end
  for _, set in ipairs({ PRESS, FOLLOW, WHEEL }) do
    for base in pairs(set) do
      if inner:sub(-#base) == base then
        local mods = inner:sub(1, #inner - #base)
        return base, mods == "" or mods:match("^%d%-$") ~= nil
      end
    end
  end
  return nil, false
end

--- `vim.on_key` listener. A key that lands on the bar is answered and discarded.
---@param key string
---@param typed string
---@return string|nil
local function on_key(key, typed)
  if not win_alive() then
    S.pressed = false
    return nil
  end
  local base, plain = classify(vim.fn.keytrans(typed ~= "" and typed or key))
  if not base then
    return nil
  end

  if FOLLOW[base] then
    -- The drag and the release of a press that began on the bar belong to it.
    if S.pressed then
      if base:find("Release", 1, true) then
        S.pressed = false
      end
      return ""
    end
    return nil
  end

  local line = bar_line()
  if not line then
    if PRESS[base] then
      -- A new press elsewhere: the release of an earlier one is not coming.
      S.pressed = false
    end
    return nil
  end
  if PRESS[base] then
    S.pressed = true
  end
  if plain then
    local item = S.rows[line]
    vim.schedule(function()
      on_pointer(base, item)
    end)
  end
  return ""
end

-- Exposed for the specs: a real click cannot be sent in a suite without a UI.
M._on_key = on_key

--- Is a redraw waiting for its tick? (specs wait for it to be gone)
---@return boolean
function M._pending()
  return S.pending
end

-- Lifecycle -------------------------------------------------------------

local function attach()
  if S.attached then
    return
  end
  S.attached = true
  -- A colour scheme set while the bar was off was not seen (the handler for it
  -- is attached only while it is on): the colours are made again.
  S.themed, S.solid_groups, S.recolor = false, {}, true
  local group = autocmd.group(GROUP, true)
  local function on(events, fn, desc, pattern)
    autocmd.create(
      events,
      fn,
      { group = group, pattern = pattern, desc = "ui.slots bar: " .. desc }
    )
  end

  on({
    "BufEnter",
    "BufWritePost",
    "BufModifiedSet",
    "TabEnter",
    "TabNew",
    "TabClosed",
    "VimResized",
    "BufFilePost",
  }, function()
    schedule()
  end, "redraw")

  -- A file that was written may be there now (or gone): what the last render
  -- found out about it is no longer true.
  on({ "BufWritePost", "BufFilePost" }, function()
    S.render_cache = {}
    schedule()
  end, "forget what was learned about files")

  -- What the room depends on besides the size of the editor.
  on("OptionSet", function()
    schedule()
  end, "room", { "cmdheight", "laststatus", "showtabline", "ambiwidth" })

  -- The slot of the file you are in is the one the bar keeps in sight.
  on("BufEnter", function()
    local name = api.nvim_buf_get_name(0)
    if name == "" or vim.bo.buftype ~= "" then
      return
    end
    local hit =
      require("ui.slots.kinds.file").matching(name, store.list(), { first_only = true })[1]
    if hit then
      S.focus_n = hit.n
    end
  end, "follow the current file")

  -- Paths are read relative to the working directory, so what was learned about
  -- them is no longer true after a :cd.
  on("DirChanged", function()
    S.render_cache, S.key_cache = {}, {}
    schedule()
  end, "forget what was learned about paths")

  on("ColorScheme", function()
    S.solid_groups = {}
    S.themed = false
    S.recolor = true
    schedule()
  end, "colours")

  -- Closed from outside (`:only`, <C-w>o, a plugin tidying floats): the bar is
  -- still wanted, so it comes back with the next redraw.
  on("WinClosed", function(args)
    if S.win and tonumber(args.match) == S.win then
      S.win, S.buf, S.rows = nil, nil, {}
      if S.want then
        schedule()
      end
    end
  end, "come back when the window was closed from outside")

  S.listener = store.on_change(function(event, n)
    S.width_floor = nil
    if event == "reload" or event == "clear_all" then
      S.render_cache, S.key_cache = {}, {}
      -- The numbers are those of the list that is gone.
      S.top_n, S.focus_n = nil, nil
    elseif (event == "set" or event == "move") and n then
      S.render_cache[n] = nil
      S.focus_n = n
    end
    schedule()
  end)

  vim.on_key(on_key, KEY_NS)
end

local function detach()
  if not S.attached then
    return
  end
  S.attached = false
  vim.on_key(nil, KEY_NS)
  if S.listener then
    store.off(S.listener)
    S.listener = nil
  end
  autocmd.group(GROUP, true)
end

--- Can a key be taken away from Neovim by returning "" from `vim.on_key`? Since
--- 0.11; on 0.10 the return value is ignored (replaceable for the specs).
---@return boolean
function M._discard_supported()
  return vim.fn.has("nvim-0.11") == 1
end

--- Show the bar (and keep it up to date) until `close()`.
function M.open()
  if not S.told_discard and not M._discard_supported() then
    S.told_discard = true
    vim.notify(
      "[ui.slots] Neovim 0.10 cannot take a click away from the editor: a click on the bar also "
        .. "moves the cursor under it, and a right click also opens the native menu. 0.11+ does not.",
      vim.log.levels.WARN
    )
  end
  S.want = true
  attach()
  M.refresh()
end

--- Hide the bar and stop watching anything.
function M.close()
  S.want = false
  detach()
  close_window()
end

---@return boolean now_open
function M.toggle()
  if S.want then
    M.close()
  else
    M.open()
  end
  return S.want
end

--- Is the bar switched on (it may have nothing to show yet)?
---@return boolean
function M.wanted()
  return S.want
end

--- Is the window on screen right now?
---@return boolean
function M.is_open()
  return win_alive()
end

--- What the bar shows right now, for tests and the health check.
---@return { win: integer|nil, buf: integer|nil, top_n: integer|nil, focus_n: integer|nil, rows: table, lines: string[] }
function M.state()
  return {
    win = win_alive() and S.win or nil,
    buf = S.buf,
    top_n = S.top_n,
    focus_n = S.focus_n,
    rows = S.rows,
    lines = (S.buf and api.nvim_buf_is_valid(S.buf))
        and api.nvim_buf_get_lines(S.buf, 0, -1, false)
      or {},
  }
end

--- Forget everything (tests, `disable()`).
function M.reset()
  M.close()
  S.top_n, S.focus_n = nil, nil
  S.render_cache, S.key_cache, S.solid_groups, S.bad_style = {}, {}, {}, {}
  S.pending, S.pressed, S.recolor, S.bad_draw, S.themed, S.told_discard =
    false, false, false, false, false, false
end

return M
