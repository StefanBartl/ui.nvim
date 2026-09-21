# Configuration — ui.nvim

Two entry points, and they run at different times. That separation is the one
thing worth understanding before changing anything here.

| Call | When | Answers |
| --- | --- | --- |
| `ui.config.setup()` | from your own config's startup, whenever you want the frame drawn | Which theme, which statusline/tabline layout |
| `ui.setup(opts)` | after, from your config | Which keymaps and commands exist |

Folding them together would mean the keymaps had to exist before the theme
did.

---

## Table of contents

- [ui.setup()](#uisetup)
- [ui.config.setup()](#uiconfigsetup)
- [The statusline variants](#the-statusline-variants)
- [Tabline styles](#tabline-styles)
- [Where the values live](#where-the-values-live)
- [What is not configurable](#what-is-not-configurable)

---

## `ui.setup()`

```lua
require("ui").setup({
  all = true,      -- shorthand for every flag below
  keymaps = true,  -- buffer/tab navigation and tabline mappings
  usrcmds = true,  -- the :UI command and theme management
  menu = false,    -- opt out of ui.contextmenu's renderer/trigger
  context = true,  -- the sticky code-context overlay; or a table of ui.context tunables
                   -- (`sticky` is the same switch under the `:UI sticky` name, `false` leaves it off)
  notify = true,   -- vim.notify as toasts with a history; or a table of ui.notify tunables
})
```

`context` is the other exception, in the opposite direction: it is
explicit-only. `all = true` does **not** turn it on, because `ui.context`
draws over the buffer's first rows and a host asking for the keymaps and the
command should not get that as a side effect. Pass `true` for the shipped
tunables or a table (`{ max_lines = 3, trim = "outer", min_window_height = 6,
debounce_ms = 30, line_numbers = true, node_types = {...},
exclude_node_types = {...}, exclude_filetypes = {...}, zindex = 20,
headings = { enable = true, max_level = 6, icons = {...} } }`) to override them;
`:UI sticky` (`:UI context` is the older spelling) toggles it for the session
either way.

How deep the context reaches is two separate limits:

- `headings.max_level` (1..6, default 6) is the deepest Markdown heading level
  that is pinned. Inside an H5 section with `max_level = 4` the chain is H1..H4;
  the H5 itself is not pinned. Setext headings count too (`===` is level 1,
  `---` level 2). It only affects Markdown; `:UI sticky up` still reaches every
  section, pinned or not.
- `max_lines` (default 3, 0 = unlimited) is how many rows the context may take,
  after the level cap. One number for every filetype, or a table keyed by
  filetype: `max_lines = { default = 3, markdown = 6 }`. A filetype without an
  entry takes `default`. `trim = "outer"` (the default) drops the outermost
  lines past the cap, `"inner"` the innermost.

At runtime `:UI sticky depth 4` and `:UI sticky lines markdown 6` change the same
two values for the session.

Outside Markdown the context comes from Tree-sitter, so a filetype without a
parser (plain text) pins nothing. Which nodes count as a scope is `node_types`
/ `exclude_node_types`, one Lua-pattern list for every grammar. A node is a scope
when its type matches a `node_types` entry and no `exclude_node_types` entry
(the excludes are broad on purpose: `_expression$` keeps calls, struct literals
and Rust's `x?` out). One exception makes it possible to take a single member of
an excluded family back: a `node_types` entry anchored at both ends (`^name$`)
names exactly that type, and the excludes cannot veto it. That is how Rust's
`if_expression`, `for_expression`, `while_expression`, `loop_expression` and
`match_expression` are pinned although `_expression$` is excluded. A plain
`^prefix` or `suffix$` entry is a family and is still subject to the excludes.

What the shipped lists pin per language (`:lua =vim.treesitter.get_node():type()`
shows the type under the cursor; `require("ui.context").is_scope_type(type)`
answers for one name):

| Language | Pinned | Left out on purpose | Checked against |
|---|---|---|---|
| Lua | `function_declaration`/`function_definition`, `if`/`elseif`/`else`, `for`, `while`, `repeat`, `do` | | parser (spec) |
| Markdown | `section`, i.e. the heading chain (see above) | fenced code, lists, quotes | parser (spec) |
| Rust | `function_item`, `impl_item`, `trait_item`, `struct_item`, `enum_item`, `mod_item`, `if`/`for`/`while`/`loop`/`match` expressions, `match_arm`, `else_clause` | calls, closures, struct literals, `x?` (`try_expression`) | parser (spec) |
| Python | `function_definition`, `class_definition`, `if`/`elif`/`else`, `for`, `while`, `with`, `try`/`except`/`finally`, `match`/`case` | decorators, comprehensions, lambdas | parser (spec) |
| Go | `function_declaration`, `method_declaration`, `func_literal`, `if`, `for`, `switch`/`select` and their `case`s, `type_declaration` | calls, composite literals | queries |
| Java | `class`/`interface`/`enum`/`record`, `method_declaration`, `constructor_declaration`, `if`, `for`/enhanced `for`, `while`, `do`, `switch`, `try`/`catch`/`finally` | `method_invocation`, lambdas | queries |
| C# | `class`/`struct`/`interface`/`enum`/`record`, `namespace`, `method`, constructor, `if`, `for`/`foreach`, `while`, `switch`, `try`/`catch`/`finally` | invocations, lambdas, properties | queries |
| JavaScript, TypeScript | `function`/`method`/`class` declarations, `arrow_function`, `function_expression`, `if`, `for`, `while`, `switch`/`case`, `try`/`catch`/`finally`; TypeScript also `interface`, `enum`, `namespace` | `call_expression` | queries |
| Kotlin | `function_declaration`, `class_declaration`, `secondary_constructor`, `if`/`when` expressions, `for`, `while`, `do_while_statement`, `catch_block` | lambdas, calls, `try_expression` | queries |
| Bash, Zsh | `function_definition`, `if`, `elif` (Bash; Zsh's queries do not name it), `else`, `for`, `c_style_for_statement`, `while`, `case` | subshells, `{ ...; }` groups | queries |
| C | `function_definition`, `struct`/`enum` specifiers, `if`, `for`, `while`, `do`, `switch`, `case` | | queries |
| JSON, YAML, TOML | nothing: none of their node types is a scope | | queries |

"Parser (spec)" means a real buffer is parsed in `TESTS/context_spec.lua`
(skipped, not failed, where the parser is not installed); "queries" means the
node names were taken from nvim-treesitter's `queries/<lang>/*.scm` and the
match is asserted by name without a parser. A callback such as
`describe("x", function () ... end)` is pinned by the function node
(`function_expression`, `arrow_function`, `func_literal`), and so shows the
`describe(` line; the call node itself is never pinned. For a language not in
the table, `node_types` is the knob: add the grammar's node names, exactly
(`"^block_mapping_pair$"`) when the type would otherwise fall under an exclude.

Two things to know when changing the lists. Set them through
`ui.setup({ context = { node_types = {...} } })` or `require("ui.context").setup`,
not by editing the table `config()` returns: the answer per node type is
remembered until `setup` runs. And an entry that is not a valid Lua pattern
(`"["`, or a non-string) is skipped with one warning instead of raising on every
cursor move. A side effect of the exact `function_expression` entry: Nix (and
OCaml) use that name for the file-level lambda, so a Nix file keeps its
`{ pkgs, ... }:` header pinned. A `node_types` you pass replaces the shipped list
rather than extending it, so to drop that entry pass the list without it.

In a Markdown buffer the pinned heading lines are drawn as headings, not as
raw source: each takes its level's `@markup.heading.N.markdown` colours (through
`UiContextH1`..`UiContextH6`, so a colorscheme's per-level palette carries over),
a full-width band in that level's background (`UiContextH1Row`..`UiContextH6Row`),
and a level icon over the `#` marker. The icon is as wide as the marker it covers,
so the text keeps its source columns and deeper levels indent by their level.
A heading is an ATX one as CommonMark has it -- up to three spaces of indent, and
an empty `##` counts -- and the level cap and the drawing read it the same way,
so an indented heading is both capped and drawn, with the icon on its `#`.
`headings = false` (or `{ enable = false }`) draws the raw lines as before;
`headings = { icons = false }` keeps the `#`s and only colours the line;
`headings = { icons = { "1", "2", "3", "4", "5", "6" } }` sets one glyph per level.

`notify` is explicit-only for the same reason: it replaces `vim.notify`, and
a host that routes notifications through noice or snacks should not lose
that to `all = true`. `true` installs `ui.notify` with the shipped tunables;
a table (`{ history_size = 200, min_level = vim.log.levels.INFO, timeouts =
{ [vim.log.levels.ERROR] = 8000 }, titles = { ... } }`) overrides them.
`:UI notify off` puts the previous handler back.

Nothing here is on by default, with one deliberate exception: `menu` is
opt-**out**, not opt-in. `ui.contextmenu`'s `open`/`bind_buffer` already work
with no setup call at all, so `all = true` (or omitting `menu` entirely)
leaves that behaviour exactly as it was; only an explicit `menu = false`
does anything, disabling the renderer/trigger while leaving the item
builders (`entry`/`group`/`submenu`) unconditional -- the semantics decided
in this plugin's own `ui.kit`/`ui.contextmenu` migration: `menu = false`
must mean the menu never renders, not that it is installed-but-silent.

Everything else here is opt-in as before: a host that wants everything
passes `all = true`, which is what the flags exist to make explicit — the
keymaps/usrcmds halves are independently useful, and a config that already
has its own buffer keymaps wants only `usrcmds`.

---

## `ui.config.setup()`

No distribution hook to call it from — this plugin does not need or expect
one. It is a plain function: call it once from wherever your own config's
startup sequence lives, assemble the result, then hand the relevant half to
each renderer's own `enable()`:

```lua
-- Anywhere in your own startup, once (this is the reference host's own
-- shape, config/ui_statusline/init.lua -- adapt names, not structure):
local ok, assembled = pcall(require("ui.config").setup, {
  theme = { theme_toggle = { "rosepine", "tokyonight" }, transparency = true },
})
if ok then
  require("ui.statusline.render").enable(assembled.ui.statusline)
  require("ui.tabline.render").enable(assembled.ui.tabline)
end
```

`ui.config.setup()` only ever assembles a config table; it does not touch
`vim.o.statusline`/`vim.o.tabline` itself. Both `enable()` calls are the
separate step that actually points those options at this plugin's own
renderers -- see [`:UI variant`'s own implementation](../lua/ui/bindings/usrcmds/init.lua)
for the same two-step shape used at runtime.

`theme` is the only overridable block at setup time (see the `theme_toggle`/
`transparency` fields in the example above). An override is merged onto a
copy; the shipped defaults are not mutated.

---

## The statusline variants

Four generic presets ship. Which one is assembled at boot is the
`STATUSLINE_VARIANT` constant in `lua/ui/config/init.lua` — but unlike before
step 4 (when NvChad read the assembled table once while booting through
`chadrc` and that was the only chance), this is no longer the only way to
pick one: `:UI variant {name}` (or `ui.config.setup({ variant = name })` +
`ui.statusline.render.enable()`) switches it at runtime, because this plugin
owns its own render entrypoint now.

| Variant | What it is |
| --- | --- |
| `default` | Full-featured, closest to the historical NvChad default. The shipped default |
| `minimal` | cursor position, working directory, progress — nothing else |
| `lsp` | LSP-aware breadcrumbs plus the enhanced segments |
| `blocks` | `lsp`'s segments, drawn as gen_block chips |

An unknown variant name falls back to `default` with a notification rather
than throwing. `:checkhealth ui` reports the boot-time default, whether it
is registered, and the actually active one separately — they can differ
after a runtime switch.

**This used to be six layouts, and the open question of whether that was the
right number is resolved (2026-09-12).** `custom` was the only one with real
personal-plugin coupling (`casedesk.nvim`, `filetree.nvim`) — not a preset by
this repo's own standard (generic, useful without either plugin), so it moved
to `docs/examples/personal-statusline-example.lua` instead.
`lspbased`/`custom_light` were the same segment set assembled two different
ways (one literally delegated to the other); one file now, `lsp`.

### `ui.config.variants` — naming a variant that is not one of the four

A host with its own plugin-specific segments — the case this repo's `custom`
preset used to cover — registers it under its own name instead of naming one
of the four presets above:

```lua
require("ui.config.variants").register(
  "personal", -- whatever name you like -- shows up in :UI variant completion
  require("your_config.statusline") -- lives in YOUR config, any shape
)

require("ui.config").setup({ variant = "personal" })
```

`M.register(name, variant)` accepts the built table directly, or a zero-arg
function returning one (for lazy loading, the same way the four shipped
presets register themselves). Once registered, `"personal"` is
indistinguishable from a shipped preset to everything that reads the
registry — `:UI variant personal`, its completion, `ui.config.setup({
variant = "personal" })`.

`opts.variant` still also accepts a table directly (used anonymously,
bypassing the registry) — the only difference is an anonymous table has no
name for `:UI status`/`ui.config.get_variant()` to report. See
`docs/examples/personal-statusline-example.lua` for the full worked example,
including the `register()` call.

---

## Tabline styles

The tabline has one shipped config, not a variant choice like the
statusline (see `ui.config.init.lua`'s own note on why: `cfg.style` is a
single field of it, not a whole `{order, modules}` table to pick between).
That field still resolves through a registry, `ui.tabline.styles`, the
same way `separator_style` resolves through
`ui.statusline.utils.primitives.separators`:

| Style | What it does |
| --- | --- |
| `rounded` (default) | A cap on every internal chip boundary; square only where the visible run actually meets an edge |
| `square` | Nothing added; chips sit flush against each other |
| `divider` | One plain vertical bar per internal boundary, no rounding |

An unrecognized or unset name falls back to `rounded` rather than throwing.

### `ui.tabline.styles` — registering your own look

```lua
require("ui.tabline.styles").register(
  "my_style", -- shows up in :UI tabline-style completion
  function(chips, chip_bufs, cur, flush_right)
    -- mutate `chips` (parallel to `chip_bufs`) in place -- see
    -- ui.tabline.styles's own doc comment for what each shipped decorator
    -- does with these same four parameters
  end
)

require("ui.config").setup({ tabline = { style = "my_style" } })
```

`:UI tabline-style {name}` switches it at runtime, and `:UI tabline-styles`
lists every registered name, marking the active one -- unlike
`:UI variant`, this does not need a full `ui.config.setup()` round-trip: it
mutates `cfg.style` directly on the table `ui.tabline.render.current()`
already holds (the tabline config is a single instance, not reassembled
per switch), then `:redrawtabline` makes it visible.

## Tabline mouse behaviour

Three opt-outs on the same tabline config, each on by default -- `false` turns
the gesture back into a plain "switch to that buffer" click:

```lua
require("ui.config").setup({
  tabline = {
    context_menu = false,      -- right-click on a chip opens its tab menu
    drag = false,              -- press-and-drag a chip along the bar to reorder it
    middle_click_close = false, -- middle-click on a chip closes it
  },
})
```

What each gesture does, and what the menu holds, is in
[BINDINGS.md](BINDINGS.md#tabline-mouse).

---

## Where the values live

[`lua/ui/config/DEFAULTS.lua`](../lua/ui/config/DEFAULTS.lua) aggregates
everything shipped: the theme block, the statusline variant, and the module
flags `ui.setup` walks.

These tables are **not** live configuration — nothing mutates them at
runtime. `:UI theme` calls `:colorscheme` and reads `vim.g.colors_name` back,
not through here, which is also why there is no `reset` to build on top of
them.

---

## What is not configurable

| Thing | Why |
| --- | --- |
| Which segments a variant contains | A variant *is* its segment list. Making it composable is the difference between shipping presets and shipping a framework, and this ships presets |
| The `:UI` command name | One verb is the project convention. A configurable name would break `:checkhealth`, the bindings docs and every reference at once |
| The theme list | It is whatever colorscheme Neovim can see (`getcompletion("", "color")`), read live so a newly installed one is offered without a restart |
