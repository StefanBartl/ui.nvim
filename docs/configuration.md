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

Called from `chadrc.lua` in the host config, whose return value NvChad reads:

```lua
-- lua/chadrc.lua
local ok, config = pcall(function()
  return require("ui.config").setup()
end)

return {
  base46 = config.base46,
  ui = { statusline = config.ui.statusline },
}
```

It takes optional overrides for the theme block:

```lua
require("ui.config").setup({
  base46 = { theme = "rosepine", transparency = true },
})
```

An override is merged onto a copy; the shipped defaults are not mutated.

---

## The statusline variants

Six layouts ship. Which one is assembled is the `STATUSLINE_VARIANT` constant
in `lua/ui/config/init.lua`, readable through `ui.config.get_variant()`. It is
a `setup()`-time choice rather than a runtime one — NvChad reads the assembled
table once while booting.

| Variant | What it is |
| --- | --- |
| `normal` | NvChad's own statusline, unmodified. The shipped default |
| `base` | Minimal: cursor position, working directory, progress |
| `lspbased` | LSP-aware breadcrumbs plus the enhanced segments |
| `custom` | The older custom breadcrumb implementation |
| `custom_light` | `custom`, assembled through a merge-based `setup()` |
| `custom_minimal` | `custom`, built on NvChad's `gen_block` pattern |

An unknown variant name falls back to `normal` with a notification rather than
throwing. `:checkhealth ui` reports the active variant and whether its module
resolves, because the fallback is otherwise quiet.

Whether six layouts is the right number is an open question — several of
them differ by a single segment.

---

## Where the values live

[`lua/ui/config/DEFAULTS.lua`](../lua/ui/config/DEFAULTS.lua) aggregates
everything shipped: the theme block, the statusline variant, and the module
flags `ui.setup` walks.

These tables are **not** live configuration — nothing mutates them at
runtime. `:UI theme` writes through base46 and NvChad's
own state, not through here, which is also why there is no `reset` to build on
top of them.

---

## What is not configurable

| Thing | Why |
| --- | --- |
| Which segments a variant contains | A variant *is* its segment list. Making it composable is the difference between shipping presets and shipping a framework, and this ships presets |
| The `:UI` command name | One verb is the project convention. A configurable name would break `:checkhealth`, the bindings docs and every reference at once |
| The theme list | It is whatever base46 has installed, read live so a newly installed theme is offered without a restart |
