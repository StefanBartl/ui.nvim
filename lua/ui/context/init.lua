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
---
--- `cfg.position` (`Ui.Context.Position`) says where the overlay sits.
--- `anchor = "top"` (the default) and `"bottom"` keep the look above --
--- full window width, at the top or the bottom. The six corner/centre
--- values (`"top-right"`, `"bottom-center"`, ...) switch to a compact box
--- sized to its own content instead of the window; `position.row`/`col`
--- override the anchor's row/column outright, for exact placement.
---
--- `cfg.style` picks how that content is drawn. `"mimic"` (the default) is
--- everything above: gutter reproduced, Tree-sitter colours, per-heading
--- bands. `"chips"` collapses the same entries into one row of rounded,
--- coloured chips -- lsp.nvim's winbar breadcrumb, redrawn into a real
--- buffer line instead of a `'winbar'` string -- which is the style a
--- compact anchor is meant to be paired with (a `"mimic"` box narrower than
--- the window still works, it just carries less of the "looks like the
--- buffer" illusion once it is not flush with the window's own gutter).

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
---@field state_file? string  # where; `~`/`$VAR` expanded, relative to the cwd at `setup`; default `stdpath("state")/ui.nvim/sticky.json`
---@field position? Ui.Context.Position
---@field style? "mimic"|"chips"  # `"mimic"` (default): full window width, reproduces the gutter, reads as real buffer rows. `"chips"` : one row of rounded, coloured chips (like lsp.nvim's winbar breadcrumb), sized to its content -- meant for a `position.anchor` off the default `"top"`.

---@class Ui.Context.Position
---@field anchor? "top"|"bottom"|"top-left"|"top-right"|"top-center"|"bottom-left"|"bottom-right"|"bottom-center"
--- Default `"top"`. `"top"`/`"bottom"` span the full window width, at the top
--- (as before) or the bottom. Any of the six corner/centre values switch the
--- overlay to a compact box sized to its own content, anchored there.
---@field row? integer  # explicit row (0-based, within the window); overrides the anchor's vertical placement
---@field col? integer  # explicit col (0-based, within the window); overrides the anchor's horizontal placement
--- `setup({ position = {...} })` replaces the whole table, not just the keys
--- given: an anchor-only call also drops a `row`/`col` an earlier call set.

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
---@field state_file string|nil        # absolute, already resolved; nil = `ui.context.state.default_path()`
---@field style "mimic"|"chips"        # how the pinned entries are drawn
---@field position Ui.Context.Position # where the overlay sits
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
  style = "mimic",
  position = { anchor = "top" },
}

--- Which edge(s) an anchor pins to. `h = "full"` means the overlay spans the
--- whole window width (the `"top"`/`"bottom"` values); any other `h` switches
--- `draw()` into the compact, content-sized box.
---@type table<string, { v: "top"|"bottom", h: "full"|"left"|"right"|"center" }>
local ANCHORS = {
  ["top"] = { v = "top", h = "full" },
  ["bottom"] = { v = "bottom", h = "full" },
  ["top-left"] = { v = "top", h = "left" },
  ["top-right"] = { v = "top", h = "right" },
  ["top-center"] = { v = "top", h = "center" },
  ["bottom-left"] = { v = "bottom", h = "left" },
  ["bottom-right"] = { v = "bottom", h = "right" },
  ["bottom-center"] = { v = "bottom", h = "center" },
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

--- Whether the last write to (or delete of) the state file failed, so a
--- confirmation does not claim a save that did not happen.
---@type boolean
local save_failed = false

--- Per window: the float and what it currently shows.
---@type table<integer, { win: integer, buf: integer, key: string }>
local floats = {}

---@type Lib.Debounce.Handle|nil
local refresher = nil

-- ---------------------------------------------------------------- highlights

-- How far a chip's background is pulled from the window background towards
-- its role colour. 0 is invisible, 1 is the role colour itself. Same value
-- and formula as lsp.nvim's winbar chips, so the two read as one family.
---@type number
local CHIP_TINT = 0.2

---@internal
---@param name string
---@return { fg?: integer, bg?: integer, bold?: boolean, italic?: boolean }
local function resolve(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and hl or {}
end

---@internal
---@param fg integer
---@param bg integer
---@param amount number
---@return integer
local function mix(fg, bg, amount)
  local out = 0
  for _, unit in ipairs({ 65536, 256, 1 }) do
    local f = math.floor(fg / unit) % 256
    local b = math.floor(bg / unit) % 256
    out = out * 256 + math.floor(b + (f - b) * amount + 0.5)
  end
  return out
end

---@internal
---The background a chip is tinted against: the overlay's own (`UiContext`,
---which by default links to `NormalFloat`), falling back the same way the
---overlay's own colours do.
---@return integer
local function window_bg()
  for _, name in ipairs({ "UiContext", "NormalFloat", "Normal" }) do
    local bg = resolve(name).bg
    if bg then
      return bg
    end
  end
  return vim.o.background == "light" and 0xeff1f5 or 0x1f2335
end

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
    -- `style = "chips"`: the separator between chips, and the generic role
    -- for a non-heading (code) scope -- every node type gets the same one, a
    -- deliberately simple v1 rather than a per-kind palette.
    UiContextChipSep = { link = "Operator", default = true },
  }
  local bg = window_bg()
  local scope_fg = resolve("Title").fg or resolve("Function").fg or resolve("Normal").fg or 0xc0caf5
  spec.UiContextChipScope =
    { fg = scope_fg, bg = mix(scope_fg, bg, CHIP_TINT), bold = true, default = true }
  spec.UiContextChipScopeCap = { fg = mix(scope_fg, bg, CHIP_TINT), bg = bg, default = true }
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
    -- `style = "chips"` counterpart: same text colour, tinted into a chip
    -- background instead of a full-row band, so a heading's colour carries
    -- over into either drawing style.
    local heading_fg = ok and hl and hl.fg
    if heading_fg then
      spec["UiContextChipH" .. level] =
        { fg = heading_fg, bg = mix(heading_fg, bg, CHIP_TINT), default = true }
      spec["UiContextChipH" .. level .. "Cap"] =
        { fg = mix(heading_fg, bg, CHIP_TINT), bg = bg, default = true }
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

---@internal
---Whether the source line at `row` is nothing but an opening bracket. A body
---node (`switch_body`, `class_body`, `function_body`, Kotlin's
---`control_structure_body`, ...) starts at its `{`; with the brace on a line of
---its own (Allman style) that line would be pinned as a context row saying
---nothing. The scope it belongs to starts on the line above and is pinned by the
---node that owns it, so the lone bracket is skipped.
---@param buf integer
---@param row integer  0-based
---@return boolean
local function opens_alone(buf, row)
  local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  return text:match("^%s*[{(%[]%s*$") ~= nil
end

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
    if
      srow < top_row
      and not seen_rows[srow]
      and M.is_scope_type(node:type())
      and not opens_alone(buf, srow)
    then
      seen_rows[srow] = true
      table.insert(out, 1, { row = srow, type = node:type() })
    end
    node = node:parent()
  end
  return out
end

---@internal
---The Tree-sitter language `buf`'s filetype resolves to, when it differs from
---the filetype itself: `markdown.mdx` -> `markdown` in stock Neovim, and whatever
---was registered with `vim.treesitter.language.register` -- nvim-treesitter
---registers `jsonc` -> `json` and `sh` -> `bash`, a host can add `rmd` ->
---`markdown`.
---@param buf integer
---@return string|nil lang
local function parser_language(buf)
  local ft = vim.bo[buf].filetype
  if ft == "" then
    return nil
  end
  local lang = vim.treesitter.language.get_lang(ft)
  if lang == nil or lang == ft then
    return nil
  end
  return lang
end

---@internal
---Whether `buf` holds Markdown: the filetype is `markdown`, or it parses as
---Markdown. The second case is what `markdown.mdx`, `markdown.pandoc` and
---`markdown.gfm` are, and `rmd`/`quarto` once the host has registered them for
---the `markdown` parser -- there the heading chain is a `section` chain too, so
---the level cap and the heading drawing apply to it as well.
---@param buf integer
---@return boolean
local function is_markdown(buf)
  return vim.bo[buf].filetype == "markdown" or parser_language(buf) == "markdown"
end

---@internal
---The `max_lines` that applies to `buf`: the number itself, or -- for the
---per-filetype table -- the entry named after the buffer's filetype, else the one
---named after its parser language, else `default`, else the shipped 3.
---@param buf integer
---@return integer|nil
local function max_lines_for(buf)
  local max = cfg.max_lines
  if type(max) ~= "table" then
    return max
  end
  ---@type integer|nil
  local by_ft = max[vim.bo[buf].filetype]
  if by_ft == nil then
    -- Only when the filetype has no entry of its own: `get_lang` is not free.
    local lang = parser_language(buf)
    by_ft = lang and max[lang] or nil
  end
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
  if max >= MAX_HEADING_LEVEL or not is_markdown(buf) then
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
  if not cfg.headings.enable or not is_markdown(buf) then
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
---`s` clipped to at most `max_width` *display cells* (not characters):
---`vim.fn.strcharpart`'s length argument counts characters, so a run of
---double-width cells (CJK, most emoji) would let through fewer or more
---cells than `max_width` and desync the float's content from its
---configured `width`. One display-width query per character is fine here --
---these are single breadcrumb/heading lines, not buffer-sized text.
---@param s string
---@param max_width integer
---@return string
local function trunc_to_width(s, max_width)
  if vim.fn.strdisplaywidth(s) <= max_width then
    return s
  end
  local out, w = {}, 0
  for i = 0, vim.fn.strchars(s) - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local cw = vim.fn.strdisplaywidth(ch)
    if w + cw > max_width then
      break
    end
    out[#out + 1] = ch
    w = w + cw
  end
  return table.concat(out)
end

---@internal
---0-based row where the overlay's top-left corner sits, given how many rows
---it is about to draw. `cfg.position.row` overrides the anchor's vertical
---part when set.
---@param win integer
---@param num_lines integer
---@return integer
local function resolve_row(win, num_lines)
  if type(cfg.position.row) == "number" then
    return math.max(math.floor(cfg.position.row), 0)
  end
  local anchor = ANCHORS[cfg.position.anchor] or ANCHORS.top
  if anchor.v == "bottom" then
    return math.max(vim.api.nvim_win_get_height(win) - num_lines, 0)
  end
  return 0
end

---@internal
---0-based column and width for the overlay. `natural_width` is the
---content's own display width (already window-capped by the caller for a
---`"full"` anchor, since those ignore it); `cfg.position.col` overrides the
---anchor's horizontal part when set.
---@param win integer
---@param natural_width integer
---@return integer col, integer width
local function resolve_col_width(win, natural_width)
  local win_width = vim.api.nvim_win_get_width(win)
  local anchor = ANCHORS[cfg.position.anchor] or ANCHORS.top
  local width = anchor.h ~= "full" and math.min(natural_width, win_width) or win_width
  local col
  if type(cfg.position.col) == "number" then
    col = math.min(math.max(math.floor(cfg.position.col), 0), win_width - 1)
    -- An explicit col is a placement inside the window, not a promise to
    -- keep a "full" anchor's width: without this, `{ anchor = "top", col =
    -- 5 }` kept width = win_width and spilled `col` columns past the
    -- window's right edge instead of shrinking to fit there.
    width = math.max(math.min(width, win_width - col), 1)
  elseif anchor.h == "right" then
    col = math.max(win_width - width, 0)
  elseif anchor.h == "center" then
    col = math.max(math.floor((win_width - width) / 2), 0)
  else
    col = 0
  end
  return col, width
end

---@internal
---Reuse `f`'s scratch buffer if it is still valid, else create one.
---@param f { buf: integer }|nil
---@return integer cbuf
local function scratch_buf(f)
  if f and vim.api.nvim_buf_is_valid(f.buf) then
    return f.buf
  end
  local cbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[cbuf].buftype = "nofile"
  vim.bo[cbuf].bufhidden = "wipe"
  vim.bo[cbuf].swapfile = false
  return cbuf
end

---@internal
---Open `win`'s overlay float at `wconfig`, or move an existing one there.
---@param f { win: integer }|nil
---@param cbuf integer
---@param wconfig table
---@return integer fwin
local function place_float(f, cbuf, wconfig)
  if f and vim.api.nvim_win_is_valid(f.win) then
    pcall(vim.api.nvim_win_set_config, f.win, wconfig)
    return f.win
  end
  local fwin = vim.api.nvim_open_win(cbuf, false, wconfig)
  vim.wo[fwin].winhighlight = "Normal:UiContext,NormalFloat:UiContext,NormalNC:UiContext"
  vim.wo[fwin].wrap = false
  vim.wo[fwin].number = false
  vim.wo[fwin].relativenumber = false
  vim.wo[fwin].signcolumn = "no"
  vim.wo[fwin].foldenable = false
  return fwin
end

---@internal
---Draw (or redraw) the full-width overlay of `win` for `entries`: the
---`style = "mimic"` look, source text and gutter reproduced verbatim.
---@param win integer
---@param buf integer
---@param entries Ui.Context.Entry[]
local function draw_mimic(win, buf, entries)
  -- The row list alone is not enough: editing the enclosing declaration in
  -- place (e.g. renaming a function) does not change which row it starts
  -- on, so a key built only from row numbers would keep the old text
  -- cached. The buffer's changedtick makes any edit anywhere in it
  -- invalidate the cache -- broader than strictly necessary, but draw()
  -- is cheap and refresh() upstream is already debounced. Height is in the
  -- key too: a `"bottom"` anchor's row depends on it, not just on width.
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
    .. "x"
    .. vim.api.nvim_win_get_height(win)
  local f = floats[win]
  if f and f.key == key and vim.api.nvim_win_is_valid(f.win) then
    return
  end

  local info = vim.fn.getwininfo(win)[1]
  local textoff = info and info.textoff or 0

  -- Built at natural length first (not yet clipped to any window/box
  -- width): a compact anchor needs to know how wide the content actually
  -- is before it can size the box around it.
  local raw, gutters, levels, indents = {}, {}, {}, {}
  for i, e in ipairs(entries) do
    local text = vim.api.nvim_buf_get_lines(buf, e.row, e.row + 1, false)[1] or ""
    text = text:gsub("%s+$", "")
    levels[i], indents[i] = heading_level(buf, text)
    local g = gutter(win, e.row, textoff)
    gutters[i] = #g
    raw[i] = g .. text
  end
  local natural_width = 0
  for _, l in ipairs(raw) do
    natural_width = math.max(natural_width, vim.fn.strdisplaywidth(l))
  end
  local col, width = resolve_col_width(win, natural_width)

  local lines = {}
  for i, full in ipairs(raw) do
    lines[i] = trunc_to_width(full, width)
  end

  local cbuf = scratch_buf(f)
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
    row = resolve_row(win, #lines),
    col = col,
    width = width,
    height = #lines,
    style = "minimal",
    focusable = false,
    zindex = cfg.zindex,
    noautocmd = true,
  }
  local fwin = place_float(f, cbuf, wconfig)
  floats[win] = { win = fwin, buf = cbuf, key = key }
end

-- Explicit codepoints, not literal glyphs -- same reason as the heading
-- icons above: a private-use-area glyph written into a source file is one
-- editor/encoding pass away from silently becoming nothing. Same two
-- codepoints as lsp.nvim's winbar chips, so the two read as one family when
-- both are on screen.
local CHIP_LEFT_CAP = vim.fn.nr2char(0xE0B6)
local CHIP_RIGHT_CAP = vim.fn.nr2char(0xE0B4)
local CHIP_SEP = " " .. vim.fn.nr2char(0x203A) .. " "

---@internal
---Chip label for one context entry: a Markdown heading without its `#`
---marker and indent, or the trimmed source line otherwise.
---@param buf integer
---@param e Ui.Context.Entry
---@return string text, integer|nil level
local function chip_entry(buf, e)
  local text = vim.api.nvim_buf_get_lines(buf, e.row, e.row + 1, false)[1] or ""
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  local level = heading_level(buf, text)
  if level then
    text = text:gsub("^#+%s*", "")
  end
  return text, level
end

---@internal
---One line of rounded chips for `entries`: lsp.nvim's winbar look, adapted
---to a real buffer line (byte-range highlight marks instead of `%#Group#`
---statusline tags).
---@param buf integer
---@param entries Ui.Context.Entry[]
---@param squared_left boolean  -- the leftmost chip is squared off, not rounded: it sits at the box's own left edge
---@return string text
---@return { [1]: integer, [2]: integer, [3]: string }[] marks  -- byte ranges, 0-based, end exclusive
local function chip_line(buf, entries, squared_left)
  local parts, marks = {}, {}
  local pos = 0
  local function push(s, hl)
    parts[#parts + 1] = s
    if hl then
      marks[#marks + 1] = { pos, pos + #s, hl }
    end
    pos = pos + #s
  end

  for i, e in ipairs(entries) do
    if i > 1 then
      push(CHIP_SEP, "UiContextChipSep")
    end
    local text, level = chip_entry(buf, e)
    local body = level and ("UiContextChipH" .. level) or "UiContextChipScope"
    local cap = level and ("UiContextChipH" .. level .. "Cap") or "UiContextChipScopeCap"
    if i == 1 and squared_left then
      push(" ", body)
    else
      push(CHIP_LEFT_CAP, cap)
    end
    push(" " .. text .. " ", body)
    push(CHIP_RIGHT_CAP, cap)
  end
  return table.concat(parts), marks
end

---@internal
---Draw (or redraw) a single `style = "chips"` row for `win`: one breadcrumb
---line, sized to its own content rather than the window.
---@param win integer
---@param buf integer
---@param entries Ui.Context.Entry[]
local function draw_chips(win, buf, entries)
  local key = buf
    .. "@"
    .. vim.api.nvim_buf_get_changedtick(buf)
    .. "|chips|"
    .. table.concat(
      vim.tbl_map(function(e)
        return tostring(e.row)
      end, entries),
      ","
    )
    .. "|"
    .. vim.api.nvim_win_get_width(win)
    .. "x"
    .. vim.api.nvim_win_get_height(win)
  local f = floats[win]
  if f and f.key == key and vim.api.nvim_win_is_valid(f.win) then
    return
  end

  local anchor = ANCHORS[cfg.position.anchor] or ANCHORS.top
  local squared_left = anchor.h == "full" or anchor.h == "left"
  local text, marks = chip_line(buf, entries, squared_left)
  local natural_width = vim.fn.strdisplaywidth(text)
  local col, width = resolve_col_width(win, natural_width)
  local byte_len = #text
  if natural_width > width then
    text = trunc_to_width(text, width)
    byte_len = #text
  end

  local cbuf = scratch_buf(f)
  vim.bo[cbuf].modifiable = true
  vim.api.nvim_buf_set_lines(cbuf, 0, -1, false, { text })
  vim.bo[cbuf].modifiable = false

  vim.api.nvim_buf_clear_namespace(cbuf, NS, 0, -1)
  for _, m in ipairs(marks) do
    local start_col, end_col, hl = m[1], m[2], m[3]
    if start_col < byte_len then
      pcall(vim.api.nvim_buf_set_extmark, cbuf, NS, 0, start_col, {
        end_col = math.min(end_col, byte_len),
        hl_group = hl,
        priority = 300,
      })
    end
  end

  local wconfig = {
    relative = "win",
    win = win,
    row = resolve_row(win, 1),
    col = col,
    width = math.max(width, 1),
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = cfg.zindex,
    noautocmd = true,
  }
  local fwin = place_float(f, cbuf, wconfig)
  floats[win] = { win = fwin, buf = cbuf, key = key }
end

---@internal
---Draw (or redraw) the overlay of `win` for `entries`: dispatches on
---`cfg.style`.
---@param win integer
---@param buf integer
---@param entries Ui.Context.Entry[]
local function draw(win, buf, entries)
  if cfg.style == "chips" then
    draw_chips(win, buf, entries)
  else
    draw_mimic(win, buf, entries)
  end
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

  -- Never over the cursor: in the window that has focus, the cell(s) the
  -- overlay would cover must not be where the cursor is. `style = "chips"`
  -- always draws one row regardless of `#entries`; a non-"top" anchor may
  -- not start at row 0, so the covered row is resolved the same way the
  -- draw itself will place it.
  if win == vim.api.nvim_get_current_win() then
    local shown_rows = cfg.style == "chips" and 1 or #entries
    local overlay_row = resolve_row(win, shown_rows)
    local screen_row = vim.api.nvim_win_call(win, function()
      return vim.fn.winline()
    end) - 1
    local row_hit = screen_row >= overlay_row and screen_row < overlay_row + shown_rows

    -- A "full" anchor spans every column, so the row alone decides it, same
    -- as before there was a column to speak of. A compact anchor only
    -- covers its own box, so a cursor elsewhere on that row must not close
    -- it -- checked against the live float's own geometry (authoritative,
    -- and already there whenever a previous draw might need covering; with
    -- none yet, this stays row-only for one frame, until the first draw
    -- gives it something to check against).
    local anchor = ANCHORS[cfg.position.anchor] or ANCHORS.top
    local col_hit = true
    if row_hit and anchor.h ~= "full" then
      local f = floats[win]
      if f and vim.api.nvim_win_is_valid(f.win) then
        local wcfg = vim.api.nvim_win_get_config(f.win)
        local screen_col = vim.api.nvim_win_call(win, function()
          return vim.fn.wincol()
        end) - 1
        col_hit = screen_col >= wcfg.col and screen_col < wcfg.col + wcfg.width
      end
    end

    if row_hit and col_hit then
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
---A `max_lines` value if it is a non-negative number, else nil. `math.huge`
---means "no limit", which is what 0 says and what a JSON file can hold.
---@param v any
---@return integer|nil
local function as_line_count(v)
  if type(v) == "number" and v >= 0 then
    return v == math.huge and 0 or math.floor(v)
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
  local path = M.state_path()
  local ok, err
  if next(overrides) == nil then
    ok, err = state.remove(path)
  else
    ok, err = state.write(path, overrides)
  end
  save_failed = not ok
  if not ok then
    vim.notify("ui.context: could not save sticky settings: " .. tostring(err), vim.log.levels.WARN)
  end
end

---@internal
---Redraw the overlays after `cfg` changed. A drawn overlay is cached by what it
---shows, not by how it is styled: a changed option (headings, say) would
---otherwise wait for the next scroll. Once per change, however many values it
---touched -- each redraw closes every float and re-runs the Tree-sitter query.
---@return nil
local function redraw()
  if enabled then
    M.close_all()
    M.refresh_all()
  end
end

---@internal
---Apply the tunables in `opts` to `cfg`, without redrawing. A value of the wrong
---type is ignored, the previous one stays.
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
  if opts.style == "mimic" or opts.style == "chips" then
    cfg.style = opts.style
  end
  if type(opts.position) == "table" then
    -- Replaces the whole table rather than merging into it: "where it goes"
    -- is one decision, not three independent ones, and a merge would leave
    -- a stale `row`/`col` from an earlier `setup()` call in effect after an
    -- anchor-only one.
    local p = opts.position
    cfg.position = {
      anchor = (p.anchor ~= nil and ANCHORS[p.anchor] ~= nil) and p.anchor or "top",
      row = type(p.row) == "number" and math.floor(p.row) or nil,
      col = type(p.col) == "number" and math.floor(p.col) or nil,
    }
  end
  scope_cache = {}
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
  if type(opts.state_file) == "string" and opts.state_file ~= "" then
    cfg.state_file = state.resolve(opts.state_file)
  end
  if cfg.persist and (opts.persist ~= nil or opts.state_file ~= nil) then
    save_failed = false
    local saved = state.read(M.state_path())
    if saved then
      overrides = saved
    end
  end
  reapply_overrides()
  if enabled then
    build_refresher()
    redraw()
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

---Cap the Markdown heading level that gets pinned (`:UI sticky depth N`).
---@param level integer  clamped into 1..6
---@return integer applied
function M.set_max_level(level)
  local _, level_set = apply({ headings = { max_level = level } })
  if level_set then
    overrides.max_level = cfg.headings.max_level
    persist_overrides()
    redraw()
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
  redraw()
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
  redraw()
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

---Whether what `depth` / `lines` set is safely in the state file: `persist` is
---on and the last write did not fail (a path that holds somebody else's file, or
---cannot be written).
---@return boolean
function M.is_saved()
  return cfg.persist and not save_failed
end

---Where `depth` / `lines` changes are written when `persist` is on: an absolute
---path, `state_file` resolved (`~`, `$VAR`) or the default one.
---@return string
function M.state_path()
  return cfg.state_file or state.default_path()
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
