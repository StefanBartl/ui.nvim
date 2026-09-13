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
- [Where the values live](#where-the-values-live)
- [What is not configurable](#what-is-not-configurable)

---

## `ui.setup()`

```lua
require("ui").setup({
  all = true,      -- shorthand for every flag below
  keymaps = true,  -- buffer/tab navigation and tabline mappings
  usrcmds = true,  -- the :UI command and theme management
})
```

Nothing here is on by default. A host that wants everything passes `all = true`, which
is what the flags exist to make explicit — the two halves are independently
useful, and a config that already has its own buffer keymaps wants only
`usrcmds`.

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
