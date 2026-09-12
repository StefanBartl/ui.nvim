# Configuration — ui.nvim

Two entry points, and they run at different times. That separation is the one
thing worth understanding before changing anything here.

| Call | When | Answers |
| --- | --- | --- |
| `ui.config.setup()` | while NvChad boots, through `chadrc` | Which theme, which statusline layout |
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

Called from `chadrc.lua` in the reference host, which today still routes
through NvChad (roadmap step 7 has not rewired it). NvChad's own `chadrc`
mechanism never read a `theme` key — it read `base46`, for its own theme
engine. Since step 6 removed base46, this example is the plugin's own API
contract, not something NvChad understands; the actual host wiring for a
NvChad-free host is step 7, not yet written:

```lua
-- lua/chadrc.lua (illustrative -- see note above)
local ok, config = pcall(function()
  return require("ui.config").setup()
end)

return {
  theme = config.theme,
  ui = { statusline = config.ui.statusline },
}
```

It takes optional overrides for the theme block:

```lua
require("ui.config").setup({
  theme = { theme_toggle = { "rosepine", "tokyonight" }, transparency = true },
})
```

An override is merged onto a copy; the shipped defaults are not mutated.

---

## The statusline variants

Four generic presets ship. Which one is assembled is the `STATUSLINE_VARIANT`
constant in `lua/ui/config/init.lua`, readable through `ui.config.get_variant()`.
It is a `setup()`-time choice rather than a runtime one — NvChad reads the
assembled table once while booting.

| Variant | What it is |
| --- | --- |
| `default` | Full-featured, closest to the historical NvChad default. The shipped default |
| `minimal` | cursor position, working directory, progress — nothing else |
| `lsp` | LSP-aware breadcrumbs plus the enhanced segments |
| `blocks` | `lsp`'s segments, drawn as gen_block chips |

An unknown variant name falls back to `default` with a notification rather
than throwing. `:checkhealth ui` reports the active variant and whether its
module resolves, because the fallback is otherwise quiet.

**This used to be six layouts, and the open question of whether that was the
right number is resolved (2026-09-12).** `custom` was the only one with real
personal-plugin coupling (`casedesk.nvim`, `filetree.nvim`) — not a preset by
this repo's own standard (generic, useful without either plugin), so it moved
to `docs/examples/personal-statusline-example.lua` instead.
`lspbased`/`custom_light` were the same segment set assembled two different
ways (one literally delegated to the other); one file now, `lsp`.

A host with its own plugin-specific segments — the case this repo's `custom`
preset used to cover — passes a fully-built variant table directly instead of
naming one of the four presets above:

```lua
require("ui.config").setup({
  variant = require("your_config.statusline"), -- lives in YOUR config, any shape
})
```

`opts.variant`, when it is a table, is used as-is instead of resolving
`STATUSLINE_VARIANT` against this repo's own `ui.config.statusline.*` files —
see `docs/examples/personal-statusline-example.lua` for the full pattern.

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
