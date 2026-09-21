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
--- differently. `cfg.node_types` is the knob, `cfg.exclude_node_types` its
--- veto: a type is a scope when it matches the first and not the second, except
--- that a `node_types` entry anchored at both ends (`^if_expression$`) names one
--- exact type the excludes cannot veto -- how a single member of an excluded
--- family (`_expression$`) is taken back. docs/configuration.md lists what the
--- shipped patterns pin per language.
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
--- Markdown headings are drawn as headings rather than as raw source: each
--- line takes its level's `@markup.heading.N.markdown` colours (the same
--- groups the buffer's own headings use, so a colorscheme's per-level palette
--- carries over), a full-width band in that level's background, and the
--- leading `#` marker is overlaid with a level icon. The icon is exactly as
--- wide as the marker it covers, so the text keeps its source columns and
--- deeper levels indent by their level -- the hierarchy reads at a glance.
--- `cfg.headings` is the knob.
---
--- How deep a Markdown context reaches is two separate limits.
--- `headings.max_level` (1..6) leaves every heading deeper than that level out
--- of the pinned chain; `max_lines` caps how many rows the chain may take, as
--- one integer for every filetype or as a table keyed by filetype
--- (`{ default = 3, markdown = 6 }`). The level cap runs first: inside an H5
--- with `max_level = 4` the chain is H1..H4, and that is then trimmed to
--- `max_lines`.
---
--- `:UI sticky depth` / `lines` set those two at runtime. With `persist = true`
--- the values a command set are also written to a JSON file (`ui.context.state`)
--- and applied on top of the configured ones at the next `setup`; `reset` drops
--- them again and returns to what the configuration said.
---
--- Off by default; `ui.setup({ context = true })` or `:UI sticky on` (`:UI
--- context` is the older spelling of the same command).

local state = require("ui.context.state")

local M = {}

local NS = vim.api.nvim_create_namespace("ui_context")
local AUGROUP = "UiContext"

---@class Ui.Context.Opts
---@field max_lines? integer|table<string, integer>
---@field trim? "outer"|"inner"
---@field min_window_height? integer
---@field debounce_ms? integer
---@field line_numbers? boolean
---@field node_types? string[]
---@field exclude_node_types? string[]
---@field exclude_filetypes? string[]
---@field zindex? integer
---@field headings? boolean|Ui.Context.HeadingOpts
---@field persist? boolean  # keep what `:UI sticky depth`/`lines` set across restarts (default false)
---@field state_file? string  # where; default `stdpath("state")/ui.nvim/sticky.json`

---@class Ui.Context.HeadingOpts
---@field enable? boolean
---@field max_level? integer  # 1..6; a heading deeper than this is not pinned (6 = every level)
---@field icons? string[]|false  # one glyph per level 1..6, each drawn over the `#` marker; false = keep the `#`s

---@class Ui.Context.Headings
---@field enable boolean
---@field max_level integer
---@field icons string[]|false

local DEFAULT_MAX_LINES = 3
local MAX_HEADING_LEVEL = 6

---@class Ui.Context.Config
---@field max_lines integer|table<string, integer> # rows the overlay may take; 0 = unlimited; a table maps filetype -> rows, `default` for the rest
---@field trim "outer"|"inner"         # which contexts to drop past `max_lines`: the outer (default) or the inner ones
---@field min_window_height integer    # a window shorter than this shows no context
---@field debounce_ms integer          # after a scroll/edit; 0 = refresh at once
---@field line_numbers boolean         # source line numbers in the gutter when 'number' is on
---@field node_types string[]          # Lua patterns; a node whose type matches one is a scope. Anchored both ends (`^name$`) = that exact type, which the excludes cannot veto
---@field exclude_node_types string[]  # Lua patterns; a matching type is not a scope, checked before `node_types` (except for an exact `^name$` entry there)
---@field exclude_filetypes string[]
---@field zindex integer
---@field headings Ui.Context.Headings # how a Markdown heading context line is drawn
---@field persist boolean              # `:UI sticky depth`/`lines` are written to `state_file` and read back at the next `setup`
---@field state_file string|nil        # nil = `ui.context.state.default_path()`
local cfg = {
  persist = false,
  max_lines = DEFAULT_MAX_LINES,
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
    "^mod_item$", -- rust
    "namespace",
    "interface",
    "^enum",
    "trait",
    "^if_statement$",
    "^elseif",
    "^elif", -- python, bash
    "^else_clause$",
    "^for",
    "_for_statement$", -- java: enhanced_for_statement; bash: c_style_for_statement
    "^while",
    "^repeat",
    "^do_statement$",
    "switch",
    "^case",
    "^match",
    "^try",
    "catch",
    "^finally",
    "^with_statement",
    "^section$", -- markdown: a heading's section starts on the heading line
    -- Exact names: the excludes below would swallow every one of them
    -- (`_expression$`, `^type`), and none of these is a bare expression.
    "^if_expression$", -- rust, kotlin
    "^for_expression$", -- rust
    "^while_expression$", -- rust
    "^loop_expression$", -- rust
    "^match_expression$", -- rust
    "^when_expression$", -- kotlin
    "^function_expression$", -- javascript, typescript: `describe("x", function () {`
    "^func_literal$", -- go: `t.Run("x", func(t *testing.T) {`
    "^type_declaration$", -- go: `type T struct {`
    "^expression_case$", -- go: `case 1:`
    "^type_case$", -- go: `case int:` in a type switch
    "^default_case$", -- go
    "^communication_case$", -- go: `case <-ch:` in a select
    "^except_clause$", -- python
    "^except_group_clause$", -- python: `except*`
    "^switch_expression$", -- java (a `switch` statement is one too), c#
    "^do_while_statement$", -- kotlin
    "^record_declaration$", -- java, c#
    "^internal_module$", -- typescript: `namespace Foo {`
    "^block_mapping_pair$", -- yaml: the parent keys of a deeply nested key (`jobs:` > `build:` > `steps:`)
  },
  exclude_node_types = {
    "call",
    "invocation", -- java: method_invocation (`method` in node_types would take it for a method)
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
  headings = {
    enable = true,
    max_level = MAX_HEADING_LEVEL,
    -- nf-md-numeric_N_box_outline, N = 1..6. `nr2char`, not a literal: an
    -- editor pass has dropped private-use glyphs from source files before.
    icons = (function()
      local out = {}
      for level = 1, 6 do
        out[level] = vim.fn.nr2char(0xF0CA1 + (level - 1) * 2)
      end
      return out
    end)(),
  },
}

---@type boolean
local enabled = false

--- What the host's configuration set for the two values `:UI sticky depth` and
--- `lines` change, so `reset` can go back to it.
---@type { max_level: integer, max_lines: integer|table<string, integer> }
local configured = { max_level = MAX_HEADING_LEVEL, max_lines = DEFAULT_MAX_LINES }

--- What commands changed on top of `configured`; this is what `persist` writes out.
---@type Ui.Context.Saved
local overrides = {}

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
  local spec = {
    UiContext = { link = "NormalFloat", default = true },
    UiContextLineNr = { link = "LineNr", default = true },
    UiContextBottom = { underline = true, sp = "#555555", default = true },
  }
  -- One text group and one row band per heading level. The text group links
  -- to the colorscheme's own heading group, so the palette carries over; the
  -- band is that group's background alone, drawn across the whole row (a
  -- colorscheme that gives headings no background gets no band).
  for level = 1, 6 do
    local src = "@markup.heading." .. level .. ".markdown"
    spec["UiContextH" .. level] = { link = src, default = true }
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = src, link = false })
    if ok and hl and hl.bg then
      spec["UiContextH" .. level .. "Row"] = { bg = hl.bg, default = true }
    end
  end
  return spec
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

---@type table<string, boolean>
local scope_cache = {}

---@internal
---A `node_types` entry that is anchored at both ends (`^if_expression$`) names
---exactly one node type instead of a family of them. A `$` behind an odd run of
---`%` is a literal dollar sign, not the anchor.
---@param pat any
---@return boolean
local function is_exact_pattern(pat)
  if type(pat) ~= "string" or pat:sub(1, 1) ~= "^" or pat:sub(-1) ~= "$" then
    return false
  end
  local escapes = pat:sub(1, -2):match("%%*$")
  return #escapes % 2 == 0
end

---@internal
---Whether `typ` matches the Lua pattern `pat`. An entry that is not a valid
---pattern -- a typo in a user's list -- counts as no match and is reported
---once, rather than raising on every refresh (one per cursor move).
---@param typ string
---@param pat any
---@return boolean
local function matches(typ, pat)
  local ok, hit = pcall(string.find, typ, pat)
  if not ok then
    vim.notify_once(
      ("ui.context: ignoring node type pattern %s (%s)"):format(vim.inspect(pat), hit),
      vim.log.levels.WARN
    )
    return false
  end
  return hit ~= nil
end

---@internal
---The uncached answer of `is_scope_type`.
---@param typ string
---@return boolean
local function classify(typ)
  for _, pat in ipairs(cfg.node_types) do
    if is_exact_pattern(pat) and matches(typ, pat) then
      return true
    end
  end
  for _, pat in ipairs(cfg.exclude_node_types) do
    if matches(typ, pat) then
      return false
    end
  end
  for _, pat in ipairs(cfg.node_types) do
    if matches(typ, pat) then
      return true
    end
  end
  return false
end

---Whether a node of type `typ` counts as a scope: it matches `cfg.node_types`
---and is not vetoed by `cfg.exclude_node_types`. An exactly named type
---(`^if_expression$`) is not vetoed: the excludes are broad on purpose
---(`_expression$` keeps `call_expression`, `try_expression`'s `?` and struct
---literals out), and a name spelled out in full is the way to take one member
---of such a family back.
---
---The answer is remembered per type name -- a grammar has a few hundred at
---most, and the ancestor walk asks for a dozen on every refresh -- until
---`setup` changes either list.
---@param typ string
---@return boolean
function M.is_scope_type(typ)
  if type(typ) ~= "string" then
    return false
  end
  local hit = scope_cache[typ]
  if hit == nil then
    hit = classify(typ)
    scope_cache[typ] = hit
  end
  return hit
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
    if srow < top_row and M.is_scope_type(node:type()) and not seen_rows[srow] then
      seen_rows[srow] = true
      table.insert(out, 1, { row = srow, type = node:type() })
    end
    node = node:parent()
  end
  return out
end

---@internal
---The `max_lines` that applies to `buf`: the number itself, or -- for the
---per-filetype table -- the buffer's filetype entry, else `default`, else the
---shipped 3.
---@param buf integer
---@return integer|nil
local function max_lines_for(buf)
  local max = cfg.max_lines
  if type(max) ~= "table" then
    return max
  end
  local by_ft = max[vim.bo[buf].filetype]
  if by_ft ~= nil then
    return by_ft
  end
  if max.default ~= nil then
    return max.default
  end
  return DEFAULT_MAX_LINES
end

---@internal
---The ATX heading on `line`: up to three spaces of indent, then 1..6 `#` and
---a blank or the end of the line, as CommonMark has it. Both the level cap and
---the drawing read a heading through this, so they cannot disagree on what one
---is.
---@param line string
---@return integer|nil level
---@return integer|nil indent  columns before the first `#`
local function atx_heading(line)
  local indent, marker = line:match("^( ? ? ?)(#+)[ \t]")
  if not marker then
    indent, marker = line:match("^( ? ? ?)(#+)$")
  end
  if marker and #marker <= MAX_HEADING_LEVEL then
    return #marker, #indent
  end
  return nil, nil
end

---@internal
---Heading level of the Markdown section that starts on `row`: an ATX heading
---(`atx_heading`), or a Setext underline on the next row (`===` is 1, `---`
---is 2). nil when neither is there.
---@param buf integer
---@param row integer  0-based
---@return integer|nil
local function section_level(buf, row)
  local lines = vim.api.nvim_buf_get_lines(buf, row, row + 2, false)
  local level = atx_heading(lines[1] or "")
  if level then
    return level
  end
  local underline = lines[2] or ""
  if underline:match("^=+%s*$") then
    return 1
  end
  if underline:match("^%-+%s*$") then
    return 2
  end
  return nil
end

---@internal
---Drop the Markdown sections deeper than `headings.max_level`. Other
---filetypes, and a level of 6, pass through untouched. A section whose level
---cannot be read is kept: better one line too many than a hole in the chain.
---@param buf integer
---@param entries Ui.Context.Entry[]
---@return Ui.Context.Entry[]
local function within_max_level(buf, entries)
  local max = cfg.headings.max_level
  if vim.bo[buf].filetype ~= "markdown" or max >= MAX_HEADING_LEVEL then
    return entries
  end
  local out = {}
  for _, e in ipairs(entries) do
    local level = e.type == "section" and section_level(buf, e.row) or nil
    if not level or level <= max then
      out[#out + 1] = e
    end
  end
  return out
end

---@internal
---Apply `max_lines`/`trim` to a context list.
---@param buf integer
---@param entries Ui.Context.Entry[]
---@return Ui.Context.Entry[]
local function trimmed(buf, entries)
  local max = max_lines_for(buf)
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
---Heading level of a Markdown context line, or nil when it is not an ATX
---heading (a Setext one has no marker to overlay) or headings are off.
---@param buf integer
---@param text string
---@return integer|nil level
---@return integer|nil indent  columns before the first `#`
local function heading_level(buf, text)
  if not cfg.headings.enable or vim.bo[buf].filetype ~= "markdown" then
    return nil, nil
  end
  return atx_heading(text)
end

---@internal
---Style one heading row: level colours on the text, a full-width band, and the
---level icon over the `#` marker.
---@param cbuf integer
---@param row integer   0-based row in the overlay buffer
---@param level integer
---@param from integer  byte column where the source text starts (after the gutter)
---@param indent integer  columns between `from` and the first `#`
---@param line_len integer
local function style_heading(cbuf, row, level, from, indent, line_len)
  local group = "UiContextH" .. level
  pcall(vim.api.nvim_buf_set_extmark, cbuf, NS, row, from, {
    end_col = line_len,
    hl_group = group,
    priority = 300,
  })
  -- Below the bottom rule's priority (50), so the two combine instead of the
  -- band replacing the underline on the last row.
  pcall(vim.api.nvim_buf_set_extmark, cbuf, NS, row, 0, {
    line_hl_group = group .. "Row",
    priority = 40,
  })
  local icons = cfg.headings.icons
  if icons and icons[level] then
    -- Exactly `level` cells, the width of the marker it covers: the icon and
    -- padding, so the text keeps its source columns.
    pcall(vim.api.nvim_buf_set_extmark, cbuf, NS, row, from + indent, {
      virt_text = { { icons[level] .. string.rep(" ", level - 1), group } },
      virt_text_pos = "overlay",
      priority = 310,
    })
  end
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

  local lines, gutters, levels, indents = {}, {}, {}, {}
  for i, e in ipairs(entries) do
    local text = vim.api.nvim_buf_get_lines(buf, e.row, e.row + 1, false)[1] or ""
    text = text:gsub("%s+$", "")
    levels[i], indents[i] = heading_level(buf, text)
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
  for i = 1, #lines do
    if levels[i] then
      style_heading(cbuf, i - 1, levels[i], gutters[i], indents[i], #lines[i])
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
  if entries then
    entries = within_max_level(buf, entries)
  end
  if not entries or #entries == 0 then
    close_float(win)
    return 0
  end
  entries = trimmed(buf, entries)

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

---@internal
---A `max_lines` value if it is a non-negative number, else nil.
---@param v any
---@return integer|nil
local function as_line_count(v)
  if type(v) == "number" and v >= 0 then
    return math.floor(v)
  end
  return nil
end

---@internal
---A heading level clamped into 1..6, or nil for anything that is not a number.
---@param v any
---@return integer|nil
local function as_heading_level(v)
  if type(v) ~= "number" then
    return nil
  end
  return math.min(math.max(math.floor(v), 1), MAX_HEADING_LEVEL)
end

---@internal
---Write `overrides` to the state file, or delete the file once nothing is
---overridden. Does nothing unless `persist` is on. A failure is a warning, never
---an error: the value is set for this session either way.
---@return nil
local function persist_overrides()
  if not cfg.persist then
    return
  end
  local path = cfg.state_file or state.default_path()
  local ok, err
  if next(overrides) == nil then
    ok, err = state.remove(path)
  else
    ok, err = state.write(path, overrides)
  end
  if not ok then
    vim.notify("ui.context: could not save sticky settings: " .. tostring(err), vim.log.levels.WARN)
  end
end

---@internal
---Apply the tunables in `opts` to `cfg`. A value of the wrong type is ignored,
---the previous one stays.
---@param opts Ui.Context.Opts
---@return boolean lines_set, boolean level_set # whether `max_lines` / `headings.max_level` were taken from `opts`
local function apply(opts)
  local lines_set, level_set = false, false
  if type(opts.max_lines) == "table" then
    local map = {}
    for ft, n in pairs(opts.max_lines) do
      local count = type(ft) == "string" and as_line_count(n) or nil
      if count then
        map[ft] = count
      end
    end
    cfg.max_lines = map
    lines_set = true
  elseif as_line_count(opts.max_lines) then
    cfg.max_lines = as_line_count(opts.max_lines)
    lines_set = true
  end
  for _, k in ipairs({
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
  if opts.headings ~= nil then
    local h = opts.headings
    if type(h) == "boolean" then
      cfg.headings.enable = h
    elseif type(h) == "table" then
      if h.enable ~= nil then
        cfg.headings.enable = h.enable
      end
      local level = as_heading_level(h.max_level)
      if level then
        cfg.headings.max_level = level
        level_set = true
      end
      if h.icons ~= nil then
        cfg.headings.icons = h.icons
      end
    end
  end
  for _, k in ipairs({ "node_types", "exclude_node_types", "exclude_filetypes" }) do
    if type(opts[k]) == "table" then
      cfg[k] = vim.deepcopy(opts[k])
    end
  end
  scope_cache = {}
  if enabled then
    build_refresher()
    -- A drawn overlay is cached by what it shows, not by how it is styled: a
    -- changed option (headings, say) would otherwise wait for the next scroll.
    M.close_all()
    M.refresh_all()
  end
  return lines_set, level_set
end

---@internal
---Set the row cap for `ft`, or for every filetype without an entry when `ft`
---is nil. Refuses what is not a non-negative number, since `apply` would drop it
---and, with it, the entry it was meant to replace.
---@param n any
---@param ft string|nil
---@return integer|nil applied
local function assign_max_lines(n, ft)
  local count = as_line_count(n)
  if not count then
    return nil
  end
  local cur = cfg.max_lines
  if ft then
    local map = type(cur) == "table" and vim.deepcopy(cur) or { default = cur }
    map[ft] = count
    apply({ max_lines = map })
  elseif type(cur) == "table" then
    local map = vim.deepcopy(cur)
    map.default = count
    apply({ max_lines = map })
  else
    apply({ max_lines = count })
  end
  return count
end

---@internal
---Put `overrides` on top of the current values.
---@return nil
local function reapply_overrides()
  if overrides.max_level then
    apply({ headings = { max_level = overrides.max_level } })
  end
  for ft, n in pairs(overrides.lines or {}) do
    assign_max_lines(n, ft ~= "default" and ft or nil)
  end
end

---Override the shipped tunables. Safe before or after `enable()`. A value of
---the wrong type is ignored, the previous one stays.
---
---Stating `max_lines` or `headings.max_level` here is stating the host's
---configuration: it becomes what `reset()` returns to, and replaces an override a
---command made earlier for that value. With `persist = true` (or a `state_file`)
---in `opts`, the saved overrides are read from the state file and applied on top.
---@param opts Ui.Context.Opts|nil
function M.setup(opts)
  opts = opts or {}
  local lines_set, level_set = apply(opts)
  if lines_set then
    configured.max_lines = vim.deepcopy(cfg.max_lines)
    overrides.lines = nil
  end
  if level_set then
    configured.max_level = cfg.headings.max_level
    overrides.max_level = nil
  end
  if opts.persist ~= nil then
    cfg.persist = opts.persist == true
  end
  if type(opts.state_file) == "string" then
    cfg.state_file = opts.state_file
  end
  if cfg.persist and (opts.persist ~= nil or opts.state_file ~= nil) then
    local saved = state.read(cfg.state_file or state.default_path())
    if saved then
      overrides = saved
    end
  end
  reapply_overrides()
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

---Cap the Markdown heading level that gets pinned (`:UI sticky depth N`).
---@param level integer  clamped into 1..6
---@return integer applied
function M.set_max_level(level)
  local _, level_set = apply({ headings = { max_level = level } })
  if level_set then
    overrides.max_level = cfg.headings.max_level
    persist_overrides()
  end
  return cfg.headings.max_level
end

---Set the row cap. With `ft` it sets that filetype's entry and leaves the
---rest alone; without, it sets the number every filetype falls back to
---(`default`, or the plain number when no table is in use). A value that is
---not a non-negative number changes nothing -- `apply` would drop it and, with
---it, the entry it was meant to replace.
---@param n integer
---@param ft string|nil
---@return boolean applied
function M.set_max_lines(n, ft)
  local count = assign_max_lines(n, ft)
  if not count then
    return false
  end
  overrides.lines = overrides.lines or {}
  overrides.lines[ft or "default"] = count
  persist_overrides()
  return true
end

---Drop what `:UI sticky depth` / `lines` changed and go back to the values the
---configuration set. Deletes the state file when `persist` is on.
---@return boolean had_overrides
function M.reset()
  local had = next(overrides) ~= nil
  overrides = {}
  apply({ max_lines = configured.max_lines, headings = { max_level = configured.max_level } })
  persist_overrides()
  return had
end

---What commands changed, as one readable string (`depth 3, lines markdown 2`), or
---nil when nothing is overridden.
---@return string|nil
function M.describe_overrides()
  local parts = {}
  if overrides.max_level then
    parts[#parts + 1] = "depth " .. overrides.max_level
  end
  local fts = vim.tbl_keys(overrides.lines or {})
  table.sort(fts)
  for _, ft in ipairs(fts) do
    parts[#parts + 1] = "lines " .. (ft == "default" and "" or ft .. " ") .. overrides.lines[ft]
  end
  if #parts == 0 then
    return nil
  end
  return table.concat(parts, ", ")
end

---Whether `depth` / `lines` changes are written to the state file.
---@return boolean
function M.is_persisting()
  return cfg.persist
end

---`max_lines` as one readable string: `3`, or `3 (markdown 6, text 1)` when
---per-filetype entries exist.
---@return string
function M.describe_max_lines()
  local max = cfg.max_lines
  if type(max) ~= "table" then
    return tostring(max)
  end
  local fts = vim.tbl_filter(function(ft)
    return ft ~= "default"
  end, vim.tbl_keys(max))
  table.sort(fts)
  local parts = {}
  for _, ft in ipairs(fts) do
    parts[#parts + 1] = ft .. " " .. max[ft]
  end
  local base = tostring(max.default or DEFAULT_MAX_LINES)
  if #parts == 0 then
    return base
  end
  return base .. " (" .. table.concat(parts, ", ") .. ")"
end

---The active configuration (read-only by convention).
---@return Ui.Context.Config
function M.config()
  return cfg
end

return M
