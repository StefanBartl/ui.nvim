---@module 'ui.context'
--- Sticky code context: the lines that *enclose* the top of the window,
--- pinned over its first rows while the body scrolls beneath them -- the
--- `function outer()` / `if cond then` / `for ...` you are inside, when the
--- line that says so has scrolled off. nvim-treesitter-context's job, on the
--- frame side of this plugin: one float per window, the same width, drawn
--- over the window's own first rows.
---
--- How the context is found: the first visible line's innermost Tree-sitter
--- node, walked up through its ancestors. Every ancestor that *starts above
--- the top line* and whose node type names a scope (`function`, `class`,
--- `if_statement`, `for`, ... -- `cfg.node_types`, matched by Lua pattern so
--- one list covers every grammar's spelling) contributes its first source
--- line, outermost first. That is a heuristic, not a per-language query
--- file, and it is the trade this module makes: no query to keep per
--- grammar, at the price of an occasional scope a query would have named
--- differently. `cfg.node_types` is the knob.
---
--- How it is drawn: a scratch buffer holding the context lines verbatim,
--- with the same parser started on it so keywords keep their colours, in a
--- non-focusable float at `row 0` of the window. The gutter is reproduced by
--- width (`textoff`) and, with `'number'` on, shows the source line number of
--- each context line in `LineNr`, which is also what makes the overlay read
--- as part of the window rather than a box on top of it.
---
--- Cost: one debounced refresh per scroll/edit/enter, each a parse of the
--- range above the top line (incremental after the first) and one ancestor
--- walk. Windows that cannot show a context -- floats, special buffers, a
--- filetype without a parser, a window too short to give up rows -- are
--- skipped before any of that runs. A window whose cursor sits on the rows
--- the overlay would cover shows none, so the cursor line is never hidden.
---
--- Off by default; `ui.setup({ context = true })` or `:UI context on`.

local M = {}

local NS = vim.api.nvim_create_namespace("ui_context")
local AUGROUP = "UiContext"

---@class Ui.Context.Opts
---@field max_lines? integer
---@field trim? "outer"|"inner"
---@field min_window_height? integer
---@field debounce_ms? integer
---@field line_numbers? boolean
---@field node_types? string[]
---@field exclude_node_types? string[]
---@field exclude_filetypes? string[]
---@field zindex? integer

---@class Ui.Context.Config
---@field max_lines integer            # rows the overlay may take; 0 = unlimited
---@field trim "outer"|"inner"         # which contexts to drop past `max_lines`: the outer (default) or the inner ones
---@field min_window_height integer    # a window shorter than this shows no context
---@field debounce_ms integer          # after a scroll/edit; 0 = refresh at once
---@field line_numbers boolean         # source line numbers in the gutter when 'number' is on
---@field node_types string[]          # Lua patterns; a node whose type matches one is a scope
---@field exclude_node_types string[]  # Lua patterns; a matching type is never a scope, checked first
---@field exclude_filetypes string[]
---@field zindex integer
local cfg = {
  max_lines = 3,
  trim = "outer",
  min_window_height = 6,
  debounce_ms = 30,
  line_numbers = true,
  node_types = {
    "function",
    "method",
    "^class",
    "struct",
    "impl",
    "^module",
    "namespace",
    "interface",
    "^enum",
    "trait",
    "^if_statement$",
    "^if_expression$",
    "^elseif",
    "^else_clause$",
    "^for",
    "^while",
    "^repeat",
    "^do_statement$",
    "switch",
    "^case",
    "^match",
    "^try",
    "catch",
    "^with_statement",
    "^section$", -- markdown: a heading's section starts on the heading line
  },
  exclude_node_types = {
    "call",
    "argument",
    "parameter",
    "_type$",
    "^type",
    "declarator",
    "_expression$",
    "^string",
  },
  exclude_filetypes = {
    "help",
    "qf",
    "neo-tree",
    "TelescopePrompt",
    "snacks_picker_input",
    "lazy",
    "mason",
  },
  zindex = 20,
}

---@type boolean
local enabled = false

--- Per window: the float and what it currently shows.
---@type table<integer, { win: integer, buf: integer, key: string }>
local floats = {}

---@type Lib.Debounce.Handle|nil
local refresher = nil

-- ---------------------------------------------------------------- highlights

---@internal
--- The three groups, as defaults a colorscheme or the host may override.
--- `hl.persist` re-applies them after every theme change; without lib.nvim
--- they are set once.
---@return table<string, table>
local function groups_spec()
  return {
    UiContext = { link = "NormalFloat", default = true },
    UiContextLineNr = { link = "LineNr", default = true },
    UiContextBottom = { underline = true, sp = "#555555", default = true },
  }
end

---@type Lib.UI.HL.PersistHandle|nil
local hl_handle = nil

---@internal
local function ensure_groups()
  if hl_handle then
    return
  end
  local ok, hl = pcall(require, "lib.nvim.ui.hl")
  if ok and type(hl.persist) == "function" then
    hl_handle = hl.persist(groups_spec, { name = "ui_context" })
  else
    for group, opts in pairs(groups_spec()) do
      vim.api.nvim_set_hl(0, group, opts)
    end
  end
end

-- ---------------------------------------------------------------- scope detection

---@internal
---@param typ string
---@return boolean
local function is_scope_type(typ)
  for _, pat in ipairs(cfg.exclude_node_types) do
    if typ:find(pat) then
      return false
    end
  end
  for _, pat in ipairs(cfg.node_types) do
    if typ:find(pat) then
      return true
    end
  end
  return false
end

---@internal
---@param buf integer
---@return vim.treesitter.LanguageTree|nil
local function parser_for(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if ok and parser then
    return parser
  end
  return nil
end

---@class Ui.Context.Entry
---@field row integer   0-based source row of the context line
---@field type string   node type that made it a scope

---The context of `top_row` (0-based): every enclosing scope that starts
---above it, outermost first, before `max_lines` trimming. `nil` when the
---buffer has no parser.
---@param buf integer
---@param top_row integer
---@return Ui.Context.Entry[]|nil
function M.contexts(buf, top_row)
  local parser = parser_for(buf)
  if not parser then
    return nil
  end
  local line_count = vim.api.nvim_buf_line_count(buf)
  if top_row <= 0 or top_row >= line_count then
    return {}
  end
  -- The tree above the top line is what the walk reads; parsing is
  -- incremental, so this is cheap on every scroll but the first.
  pcall(parser.parse, parser, { 0, 0, top_row + 1, 0 })

  local line = vim.api.nvim_buf_get_lines(buf, top_row, top_row + 1, false)[1] or ""
  local col = math.max((line:find("%S") or 1) - 1, 0)
  local ok, node = pcall(vim.treesitter.get_node, {
    bufnr = buf,
    pos = { top_row, col },
    ignore_injections = true,
  })
  if not ok or not node then
    return {}
  end

  ---@type Ui.Context.Entry[]
  local out = {}
  local seen_rows = {}
  while node do
    local srow = node:start()
    if srow < top_row and is_scope_type(node:type()) and not seen_rows[srow] then
      seen_rows[srow] = true
      table.insert(out, 1, { row = srow, type = node:type() })
    end
    node = node:parent()
  end
  return out
end

---@internal
---Apply `max_lines`/`trim` to a context list.
---@param entries Ui.Context.Entry[]
---@return Ui.Context.Entry[]
local function trimmed(entries)
  local max = cfg.max_lines
  if type(max) ~= "number" or max <= 0 or #entries <= max then
    return entries
  end
  local out = {}
  if cfg.trim == "inner" then
    for i = 1, max do
      out[i] = entries[i]
    end
  else
    for i = #entries - max + 1, #entries do
      out[#out + 1] = entries[i]
    end
  end
  return out
end

-- ---------------------------------------------------------------- windows

---@internal
---@param win integer
---@return boolean
local function eligible(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local wcfg = vim.api.nvim_win_get_config(win)
  if wcfg.relative and wcfg.relative ~= "" then
    return false
  end
  if vim.api.nvim_win_get_height(win) < cfg.min_window_height then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  local ft = vim.bo[buf].filetype
  for _, skip in ipairs(cfg.exclude_filetypes) do
    if ft == skip then
      return false
    end
  end
  return true
end

---@internal
---Close and forget the float of `win`.
---@param win integer
local function close_float(win)
  local f = floats[win]
  if not f then
    return
  end
  floats[win] = nil
  if vim.api.nvim_win_is_valid(f.win) then
    pcall(vim.api.nvim_win_close, f.win, true)
  end
  if vim.api.nvim_buf_is_valid(f.buf) then
    pcall(vim.api.nvim_buf_delete, f.buf, { force = true })
  end
end

---@internal
---The gutter prefix for one context line: the source line number padded to
---the window's own text offset, or that many spaces.
---@param win integer
---@param row integer  0-based
---@param textoff integer
---@return string
local function gutter(win, row, textoff)
  if textoff <= 0 then
    return ""
  end
  if cfg.line_numbers and vim.wo[win].number then
    local width = math.max(textoff - 1, 1)
    return ("%" .. width .. "d "):format(row + 1)
  end
  return string.rep(" ", textoff)
end

---@internal
---Draw (or redraw) the overlay of `win` for `entries`.
---@param win integer
---@param buf integer
---@param entries Ui.Context.Entry[]
local function draw(win, buf, entries)
  -- The row list alone is not enough: editing the enclosing declaration in
  -- place (e.g. renaming a function) does not change which row it starts
  -- on, so a key built only from row numbers would keep the old text
  -- cached. The buffer's changedtick makes any edit anywhere in it
  -- invalidate the cache -- broader than strictly necessary, but draw()
  -- is cheap and refresh() upstream is already debounced.
  local key = buf
    .. "@"
    .. vim.api.nvim_buf_get_changedtick(buf)
    .. "|"
    .. table.concat(
      vim.tbl_map(function(e)
        return tostring(e.row)
      end, entries),
      ","
    )
    .. "|"
    .. vim.api.nvim_win_get_width(win)
  local f = floats[win]
  if f and f.key == key and vim.api.nvim_win_is_valid(f.win) then
    return
  end

  local width = vim.api.nvim_win_get_width(win)
  local info = vim.fn.getwininfo(win)[1]
  local textoff = info and info.textoff or 0

  local lines, gutters = {}, {}
  for i, e in ipairs(entries) do
    local text = vim.api.nvim_buf_get_lines(buf, e.row, e.row + 1, false)[1] or ""
    text = text:gsub("%s+$", "")
    local g = gutter(win, e.row, textoff)
    gutters[i] = #g
    local full = g .. text
    lines[i] = vim.fn.strcharpart(full, 0, width)
  end

  local cbuf
  if f and vim.api.nvim_buf_is_valid(f.buf) then
    cbuf = f.buf
  else
    cbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[cbuf].buftype = "nofile"
    vim.bo[cbuf].bufhidden = "wipe"
    vim.bo[cbuf].swapfile = false
  end
  vim.bo[cbuf].modifiable = true
  vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, lines)
  vim.bo[cbuf].modifiable = false

  -- Same parser as the source, so keywords keep their colours. Started on
  -- a buffer that holds header lines only, which every grammar parses
  -- well enough to colour; a failure here just leaves the text plain.
  local parser = parser_for(buf)
  if parser then
    pcall(vim.treesitter.start, cbuf, parser:lang())
  end
  vim.api.nvim_buf_clear_namespace(cbuf, NS, 0, -1)
  for i = 1, #lines do
    if gutters[i] > 0 then
      pcall(vim.api.nvim_buf_set_extmark, cbuf, NS, i - 1, 0, {
        end_col = math.min(gutters[i], #lines[i]),
        hl_group = "UiContextLineNr",
        priority = 200,
      })
    end
  end
  pcall(vim.api.nvim_buf_set_extmark, cbuf, NS, #lines - 1, 0, {
    line_hl_group = "UiContextBottom",
    priority = 50,
  })

  local wconfig = {
    relative = "win",
    win = win,
    row = 0,
    col = 0,
    width = width,
    height = #lines,
    style = "minimal",
    focusable = false,
    zindex = cfg.zindex,
    noautocmd = true,
  }
  local fwin
  if f and vim.api.nvim_win_is_valid(f.win) then
    fwin = f.win
    pcall(vim.api.nvim_win_set_config, fwin, wconfig)
  else
    fwin = vim.api.nvim_open_win(cbuf, false, wconfig)
    vim.wo[fwin].winhighlight = "Normal:UiContext,NormalFloat:UiContext,NormalNC:UiContext"
    vim.wo[fwin].wrap = false
    vim.wo[fwin].number = false
    vim.wo[fwin].relativenumber = false
    vim.wo[fwin].signcolumn = "no"
    vim.wo[fwin].foldenable = false
  end
  floats[win] = { win = fwin, buf = cbuf, key = key }
end

---Recompute and redraw the context of one window (default: the current).
---@param win integer|nil
---@return integer shown  Number of context lines on screen for that window.
function M.refresh(win)
  win = win or vim.api.nvim_get_current_win()
  if not enabled or not eligible(win) then
    close_float(win)
    return 0
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local top = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end) - 1
  local entries = M.contexts(buf, top)
  if not entries or #entries == 0 then
    close_float(win)
    return 0
  end
  entries = trimmed(entries)

  -- Never over the cursor line: in the window that has focus, the rows the
  -- overlay would cover must not be where the cursor is.
  if win == vim.api.nvim_get_current_win() then
    local screen_row = vim.api.nvim_win_call(win, function()
      return vim.fn.winline()
    end)
    if screen_row <= #entries then
      close_float(win)
      return 0
    end
  end

  draw(win, buf, entries)
  return #entries
end

---Refresh every window of the current tabpage.
function M.refresh_all()
  local live = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    live[win] = true
    M.refresh(win)
  end
  for win in pairs(floats) do
    if not live[win] or not vim.api.nvim_win_is_valid(win) then
      close_float(win)
    end
  end
end

---@internal
local function schedule_refresh()
  if not enabled then
    return
  end
  if refresher then
    refresher.call()
  else
    M.refresh_all()
  end
end

---@internal
local function build_refresher()
  if type(cfg.debounce_ms) ~= "number" or cfg.debounce_ms <= 0 then
    refresher = nil
    return
  end
  local ok, debounce = pcall(require, "lib.nvim.debounce")
  if ok then
    refresher = debounce.new(function()
      vim.schedule(M.refresh_all)
    end, cfg.debounce_ms)
  else
    refresher = nil
  end
end

---Close every overlay.
function M.close_all()
  for win in pairs(floats) do
    close_float(win)
  end
end

---The overlay window of `win`, or nil when it shows none.
---@param win integer|nil
---@return integer|nil fwin
---@return integer|nil fbuf
function M.float(win)
  win = win or vim.api.nvim_get_current_win()
  local f = floats[win]
  if f and vim.api.nvim_win_is_valid(f.win) then
    return f.win, f.buf
  end
  return nil, nil
end

---Jump to the `n`-th enclosing context above the top of the window
---(1 = innermost). Works whether or not the overlay is drawn.
---@param n integer|nil
---@return boolean moved
function M.go_to_context(n)
  n = n or 1
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local top = vim.fn.line("w0") - 1
  local entries = M.contexts(buf, top) or {}
  if #entries == 0 then
    return false
  end
  local idx = math.max(#entries - n + 1, 1)
  local e = entries[idx]
  vim.api.nvim_win_set_cursor(win, { e.row + 1, 0 })
  vim.cmd("normal! ^")
  return true
end

-- ---------------------------------------------------------------- lifecycle

---Override the shipped tunables. Safe before or after `enable()`.
---@param opts Ui.Context.Opts|nil
function M.setup(opts)
  opts = opts or {}
  for _, k in ipairs({
    "max_lines",
    "trim",
    "min_window_height",
    "debounce_ms",
    "line_numbers",
    "zindex",
  }) do
    if opts[k] ~= nil then
      cfg[k] = opts[k]
    end
  end
  for _, k in ipairs({ "node_types", "exclude_node_types", "exclude_filetypes" }) do
    if type(opts[k]) == "table" then
      cfg[k] = vim.deepcopy(opts[k])
    end
  end
  if enabled then
    build_refresher()
    M.refresh_all()
  end
end

---Turn the overlay on: highlight groups, autocmds, a first refresh.
---Idempotent.
function M.enable()
  if enabled then
    return
  end
  enabled = true
  ensure_groups()
  build_refresher()

  local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
  vim.api.nvim_create_autocmd({
    "WinScrolled",
    "CursorMoved",
    "CursorMovedI",
    "BufEnter",
    "WinEnter",
    "BufWinEnter",
    "TextChanged",
    "TextChangedI",
    "VimResized",
    "WinResized",
  }, {
    group = group,
    callback = schedule_refresh,
    desc = "ui.context: refresh the sticky context overlays",
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      local win = tonumber(ev.match)
      if win then
        close_float(win)
      end
    end,
    desc = "ui.context: drop the overlay of a closed window",
  })
  M.refresh_all()
end

---Turn the overlay off: autocmds gone, every float closed. Idempotent.
function M.disable()
  if not enabled then
    return
  end
  enabled = false
  if refresher then
    refresher.cancel()
  end
  pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
  M.close_all()
end

---@return boolean now_enabled
function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
  return enabled
end

---@return boolean
function M.is_enabled()
  return enabled
end

---The active configuration (read-only by convention).
---@return Ui.Context.Config
function M.config()
  return cfg
end

return M
