---@module 'ui.colorpicker'
--- An interactive colour picker in a `ui.kit.surface` float: a hue row, a
--- saturation x lightness grid for the hue under the cursor, a row of
--- shades of the current pick, and the pick's `#hex` / `rgb()` / `hsl()`
--- readout. The window's own cursor is the selector -- `h`/`j`/`k`/`l`,
--- arrows, the mouse, all move it -- so the picker has three keys of its
--- own: `<CR>` takes the colour (replacing the `#hex` the picker was opened
--- on, or inserting after the cursor), `y` yanks it, `q`/`<Esc>` close.
---
--- The idea is nvzone/minty's (`:Huefy`, `:Shades`), the frame-side
--- placement is this plugin's: it already assembles palettes
--- (`ui.theme.palette`) and owns the themed float (`ui.kit.surface`), so a
--- colour picker is one more themed surface rather than a dependency on a
--- second UI toolkit (`nvzone/volt`). Cells are two-column highlight
--- groups created on demand and cached by hex, which is the one Neovim
--- primitive a terminal colour swatch can be.

local surface = require("ui.kit.surface")
local color = require("ui.colorpicker.color")

local api = vim.api

local M = {}

local NS = api.nvim_create_namespace("ui_colorpicker")

---@class Ui.Colorpicker.Opts
---@field hex? string          # start colour; default: the #hex under the cursor, else `default`
---@field on_pick? fun(hex: string)  # replaces the default replace/insert/yank behaviour
---@field title? string

---@class Ui.Colorpicker.Config
---@field default string       # start colour when nothing is under the cursor
---@field hues integer         # cells in the hue row
---@field rows integer         # lightness steps in the grid
---@field cols integer         # saturation steps in the grid
---@field shades integer       # cells in the shades row
---@field shade_step number    # lightness change per shade cell, in points
---@field yank_register string # register `y` and the default pick write to
local cfg = {
  default = "#61afef",
  hues = 24,
  rows = 7,
  cols = 12,
  shades = 12,
  shade_step = 8,
  yank_register = '"',
}

---@type table<string, string>  hex -> highlight group name
local hl_cache = {}

---@internal
---A highlight group whose background is `hex` (and whose foreground reads
---on it), created once per colour.
---@param hex string
---@return string group
local function hl_for(hex)
  local group = hl_cache[hex]
  if group then
    return group
  end
  group = "UiColorpicker_" .. hex:sub(2)
  api.nvim_set_hl(0, group, { bg = hex, fg = color.contrast(hex) })
  hl_cache[hex] = group
  return group
end

-- ---------------------------------------------------------------- model

---@class Ui.Colorpicker.Cell
---@field hex string
---@field col integer   # 0-based start column of the cell's two characters

---@class Ui.Colorpicker.State
---@field hue number           # hue the grid is built for
---@field pick string          # the colour under the cursor
---@field base string          # the colour the shades row is built from
---@field rows table<integer, Ui.Colorpicker.Cell[]>  # 0-based buffer row -> cells
---@field surf Ui.Kit.Surface|nil
---@field origin { buf: integer, win: integer, row: integer, col: integer, s: integer|nil, e: integer|nil }
---@field on_pick fun(hex: string)|nil

local CELL = "  "
local ROW_HUE = 0
local ROW_MARK = 1
local ROW_GRID = 2

---@internal
---@return integer
local function row_shades()
  return ROW_GRID + cfg.rows + 1
end

---@internal
---@return integer
local function row_info()
  return row_shades() + 2
end

---@internal
---Rebuild every row's cells for `state.hue`/`state.base`.
---@param state Ui.Colorpicker.State
local function layout(state)
  local rows = {}
  local hue_cells = {}
  for i = 0, cfg.hues - 1 do
    hue_cells[#hue_cells + 1] = { hex = color.hsl_to_hex(i * 360 / cfg.hues, 100, 50), col = i * 2 }
  end
  rows[ROW_HUE] = hue_cells
  for r = 0, cfg.rows - 1 do
    local l = 90 - (r * (80 / math.max(cfg.rows - 1, 1)))
    local cells = {}
    for c = 0, cfg.cols - 1 do
      local s = 100 - (c * (90 / math.max(cfg.cols - 1, 1)))
      cells[#cells + 1] = { hex = color.hsl_to_hex(state.hue, s, l), col = c * 2 }
    end
    rows[ROW_GRID + r] = cells
  end
  local shades = {}
  local half = math.floor(cfg.shades / 2)
  for i = 0, cfg.shades - 1 do
    local delta = (i - half) * cfg.shade_step
    shades[#shades + 1] =
      { hex = color.shift_lightness(state.base, delta) or state.base, col = i * 2 }
  end
  rows[row_shades()] = shades
  state.rows = rows
end

---@internal
---@param state Ui.Colorpicker.State
---@return string[]
local function lines(state)
  local out = {}
  local width = math.max(cfg.hues, cfg.cols, cfg.shades) * 2
  local function blank_row(n)
    return string.rep(CELL, n) .. string.rep(" ", width - n * 2)
  end
  out[ROW_HUE + 1] = blank_row(cfg.hues)
  local hue_idx = math.floor((state.hue % 360) / 360 * cfg.hues + 0.5) % cfg.hues
  out[ROW_MARK + 1] = string.rep(" ", hue_idx * 2)
    .. "▀▀"
    .. string.rep(" ", width - hue_idx * 2 - 2)
  for r = 0, cfg.rows - 1 do
    out[ROW_GRID + r + 1] = blank_row(cfg.cols)
  end
  out[ROW_GRID + cfg.rows + 1] = string.rep(" ", width)
  out[row_shades() + 1] = blank_row(cfg.shades)
  out[row_shades() + 2] = string.rep(" ", width)
  local r, g, b = color.parse(state.pick)
  local h, s, l = color.hex_to_hsl(state.pick)
  out[row_info() + 1] = ("%s  rgb(%d, %d, %d)  hsl(%d, %d%%, %d%%)"):format(
    state.pick,
    r or 0,
    g or 0,
    b or 0,
    math.floor((h or 0) + 0.5),
    math.floor((s or 0) + 0.5),
    math.floor((l or 0) + 0.5)
  )
  out[row_info() + 2] = "<CR> pick   y yank   q close"
  return out
end

---@internal
---Paint every cell, and the pick's readout in its own colour.
---@param state Ui.Colorpicker.State
local function paint(state)
  local buf = state.surf.bufnr
  api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for row, cells in pairs(state.rows) do
    for _, cell in ipairs(cells) do
      api.nvim_buf_set_extmark(buf, NS, row, cell.col, {
        end_col = cell.col + #CELL,
        hl_group = hl_for(cell.hex),
      })
    end
  end
  api.nvim_buf_set_extmark(
    buf,
    NS,
    row_info(),
    0,
    { end_col = #state.pick, hl_group = hl_for(state.pick) }
  )
  api.nvim_buf_set_extmark(buf, NS, row_info() + 1, 0, { line_hl_group = "Comment" })
end

---@internal
---The cell under the window cursor, if the cursor is on one.
---@param state Ui.Colorpicker.State
---@return Ui.Colorpicker.Cell|nil
---@return integer row
local function cell_at_cursor(state)
  local cur = api.nvim_win_get_cursor(state.surf.winid)
  local row, col = cur[1] - 1, cur[2]
  local cells = state.rows[row]
  if not cells then
    return nil, row
  end
  local idx = math.floor(col / #CELL) + 1
  return cells[idx], row
end

---@internal
---Redraw after the cursor moved: the hue row re-keys the grid, the grid
---re-keys the shades, every cell sets the pick.
---@param state Ui.Colorpicker.State
local function on_cursor(state)
  if not state.surf or not state.surf:is_valid() then
    return
  end
  local cell, row = cell_at_cursor(state)
  if not cell then
    return
  end
  state.pick = cell.hex
  if row == ROW_HUE then
    state.hue = (color.hex_to_hsl(cell.hex))
    state.base = cell.hex
    layout(state)
  elseif row ~= row_shades() then
    state.base = cell.hex
    layout(state)
  end
  state.surf:set_lines(lines(state))
  paint(state)
end

---@internal
---Put the cursor on the grid cell nearest to `hex` (or the hue cell when
---the grid has nothing close).
---@param state Ui.Colorpicker.State
---@param hex string
local function cursor_to(state, hex)
  local h, s, l = color.hex_to_hsl(hex)
  if not h then
    return
  end
  local best, best_d, best_row, best_col = nil, math.huge, ROW_GRID, 0
  for r = ROW_GRID, ROW_GRID + cfg.rows - 1 do
    for _, cell in ipairs(state.rows[r] or {}) do
      local _, cs, cl = color.hex_to_hsl(cell.hex)
      local d = math.abs((cs or 0) - (s or 0)) + math.abs((cl or 0) - (l or 0))
      if d < best_d then
        best, best_d, best_row, best_col = cell, d, r, cell.col
      end
    end
  end
  if best then
    api.nvim_win_set_cursor(state.surf.winid, { best_row + 1, best_col })
  end
end

-- ---------------------------------------------------------------- actions

---@internal
---Write `hex` back: replace the literal the picker opened on, else insert
---at the origin cursor. Also yanks it, so a pick is never lost.
---@param state Ui.Colorpicker.State
---@param hex string
local function default_pick(state, hex)
  local o = state.origin
  pcall(vim.fn.setreg, cfg.yank_register, hex)
  if not api.nvim_buf_is_valid(o.buf) or not vim.bo[o.buf].modifiable then
    return
  end
  if o.s and o.e then
    api.nvim_buf_set_text(o.buf, o.row, o.s, o.row, o.e, { hex })
  else
    -- After the cursor character, like `p`: a normal-mode cursor sits ON the
    -- last character, and "bg = |" wants the colour after the space.
    local line = api.nvim_buf_get_lines(o.buf, o.row, o.row + 1, false)[1] or ""
    local col = #line == 0 and 0 or math.min((o.col or 0) + 1, #line)
    api.nvim_buf_set_text(o.buf, o.row, col, o.row, col, { hex })
  end
end

---@internal
---@param state Ui.Colorpicker.State
local function bind(state)
  local buf = state.surf.bufnr
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", function()
    local hex = state.pick
    state.surf:close()
    if state.on_pick then
      state.on_pick(hex)
    else
      default_pick(state, hex)
    end
  end, "ui.colorpicker: take this colour")
  map("y", function()
    pcall(vim.fn.setreg, cfg.yank_register, state.pick)
    pcall(vim.fn.setreg, "+", state.pick)
    vim.notify("yanked " .. state.pick)
  end, "ui.colorpicker: yank this colour")
  for _, lhs in ipairs({ "i", "a", "o", "O", "c", "d", "x", "p", "P", "r", "s", "u" }) do
    map(lhs, function() end, "ui.colorpicker: no editing here")
  end
end

-- ---------------------------------------------------------------- public

---@type Ui.Colorpicker.State|nil
local current = nil

---Open the picker. Returns the surface, or nil when the float could not
---open.
---@param opts Ui.Colorpicker.Opts|nil
---@return Ui.Kit.Surface|nil
function M.open(opts)
  opts = opts or {}
  if current and current.surf and current.surf:is_valid() then
    current.surf:close()
  end

  local obuf = api.nvim_get_current_buf()
  local owin = api.nvim_get_current_win()
  local cur = api.nvim_win_get_cursor(owin)
  local line = api.nvim_buf_get_lines(obuf, cur[1] - 1, cur[1], false)[1] or ""
  local under, s, e = color.hex_at(line, cur[2])

  local start = color.normalize(opts.hex or "") or color.normalize(under or "") or cfg.default
  local h = color.hex_to_hsl(start) or 0 --[[@as number]]

  ---@type Ui.Colorpicker.State
  local state = {
    hue = h,
    pick = start,
    base = start,
    rows = {},
    surf = nil,
    origin = {
      buf = obuf,
      win = owin,
      row = cur[1] - 1,
      col = cur[2],
      s = (opts.hex == nil) and s or nil,
      e = (opts.hex == nil) and e or nil,
    },
    on_pick = opts.on_pick,
  }
  layout(state)

  local content = lines(state)
  local surf = surface.open({
    lines = content,
    title = opts.title or "Colour",
    width = #content[1],
    height = #content,
    relative = "cursor",
    row = 1,
    col = 0,
    enter = true,
    nice_quit = true,
    filetype = "ui-colorpicker",
    wo = { cursorline = false, wrap = false, number = false, signcolumn = "no", list = false },
  })
  if not surf then
    return nil
  end
  state.surf = surf
  current = state
  paint(state)
  bind(state)
  -- The cursor lands on the nearest grid cell, but the pick stays the exact
  -- start colour until the cursor moves: opening on `#123456` and pressing
  -- `<CR>` must give `#123456` back, not the grid's quantised neighbour.
  cursor_to(state, start)
  state.pick = start
  state.base = start
  layout(state)
  surf:set_lines(lines(state))
  paint(state)

  api.nvim_create_autocmd("CursorMoved", {
    buffer = surf.bufnr,
    callback = function()
      on_cursor(state)
    end,
    desc = "ui.colorpicker: follow the cursor",
  })
  surf:on_close(function()
    if current == state then
      current = nil
    end
  end)
  return surf
end

---The colour currently under the picker's cursor, or nil when closed.
---@return string|nil
function M.current()
  if current and current.surf and current.surf:is_valid() then
    return current.pick
  end
  return nil
end

---Override the shipped tunables.
---@param opts table|nil
function M.setup(opts)
  for k, v in pairs(opts or {}) do
    if cfg[k] ~= nil then
      cfg[k] = v
    end
  end
  hl_cache = {}
end

---@return Ui.Colorpicker.Config
function M.config()
  return cfg
end

return M
