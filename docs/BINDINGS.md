# Bindings — ui.nvim

Every command, keymap and autocommand this plugin registers. Read by
`:Bindings` out of the installed plugin directory, so this file is the source
of truth rather than a copy of one.

Nothing here is registered until `require("ui").setup({ all = true })` runs.

---

## Table of contents

- [Commands](#commands)
- [Keymaps](#keymaps)
- [Autocommands](#autocommands)
- [What deliberately has no binding](#what-deliberately-has-no-binding)

---

## Commands

One verb, `:UI`, with `<Tab>` completion over its subcommands and over the
theme list.

| Command | Args | Does |
| --- | --- | --- |
| `:UI theme {name}` | completes over every colorscheme Neovim can see | `:colorscheme {name}` |
| `:UI themes` | — | List the available themes, marking the active one |
| `:UI toggle` | — | Swap between the two themes in `theme.theme_toggle` |
| `:UI transparency` | — | Toggle background transparency |
| `:UI variant {name}` | completes over the statusline-variant registry | Switch the active statusline preset at runtime |
| `:UI variants` | — | List the registered variants (four shipped presets plus anything a host registered), marking the active one |
| `:UI status` | — | Current theme, transparency state, statusline variant |
| `:UI help` | — | The subcommand list, in a float |

**Completion is two-level:** the first argument completes over the eight
subcommands, the argument after `theme`/`variant` over the theme list / the
variant registry respectively. The theme list is
`vim.fn.getcompletion("", "color")` at the moment `<Tab>` is pressed, so a
colorscheme installed mid-session is offered; the variant list is
`ui.config.variants.list()`, so a variant a host registers from its own
config (`require("ui.config.variants").register(name, variant)`) shows up
in completion the moment that call runs, next to the four shipped presets.

**`:UI variant` is a runtime switch, unlike the preset choice
`ui.config.STATUSLINE_VARIANT` used to be.** It calls `ui.config.setup({
variant = name })` and then `ui.statusline.render.enable()` with the result
-- both steps, since assembling a config and pointing `vim.o.statusline` at
it are separate. `ui.config.get_variant()` reports whichever name was
actually resolved last, which is what changes after a switch (the
`STATUSLINE_VARIANT` constant itself is only the boot-time default and does
not change).

**No range, no count.** Every subcommand acts on global state — the theme, the
transparency flag — where a line range or a repeat count has no meaning.

---

## Keymaps

Registered by `ui.bindings.keymaps.setup({ all = true })`, which `ui.setup`
calls when `all` or `keymaps` is set.

### Buffers

| Key | Mode | Does |
| --- | --- | --- |
| `<Tab>` | `n` | Next buffer |
| `<S-Tab>` | `n` | Previous buffer |
| `<leader>bc` | `n` | Close the current buffer, keeping the window layout |

### Tabs

| Key | Mode | Does |
| --- | --- | --- |
| `<leader>tr` | `n` | Move the current buffer one position right in the tabline |
| `<leader>tl` | `n` | Move it one position left |
| `<leader>tt` | `n` | Move the current buffer into a new tab |

Every one of these is wrapped: a failure notifies and returns rather than
raising, because they sit on keys pressed constantly and a traceback out of
`<Tab>` makes the editor feel broken.

`<leader>tr` and `<leader>tl` go through `ui.bindings.keymaps.tabufline.state`
(own code as of roadmap step 5, not `nvchad.tabufline`) — they work with
NvChad entirely absent.

---

## Autocommands

All of them are cache invalidation for statusline segments, which is why none
of them live in a central `bindings/autocmds.lua`: each belongs to the cache it
clears, and a central registrar would be a second place to keep in step with
the segment that owns the data.

| Augroup | Owner | Clears |
| --- | --- | --- |
| `UiDeviconsCache` | `statusline/modules/file_icons` | Resolved file-type icons |
| `UiFormattersCache` | `statusline/modules/formatters` | Formatter state per buffer |
| `UiHighlightCache` | `statusline/modules/highlighting` | Derived statusline highlight groups |
| `UiPathsCache` | `statusline/modules/lsp/helpers` | Resolved paths for the LSP segment |
| `UiLspSymbolsCache` | `statusline/modules/lsp/symbols` | Document symbols |
| `UiCwdModeBadgeHl` | `statusline/modules/filetree_cwd_mode` | Rebuilds the badge highlights on `ColorScheme` |
| `LspBreadcrumbsAsync` | `statusline/modules/lsp` | Drives the asynchronous breadcrumb request |

---

## What deliberately has no binding

| Thing | Why |
| --- | --- |
| A dedicated statusline-variant keymap | `:UI variant {name}` (see Commands above) covers it — a command with completion over the registry is more discoverable than a keymap would be for something with more than two states |
| A `bindings/autocmds.lua` | There is no plugin-level autocmd to put in it. Every one of the seven above belongs to the cache it clears — a central registrar would be a second source of truth for the same state. This is a documented deviation from `NEW-08`, not an oversight |
| Individual statusline segments | They are on or off by which variant is assembled, not by a key. Four toggles for four segments would be more surface than the choice deserves |

**The statusline variant used to be listed here as a setup()-time-only
choice** ("switching it at runtime would mean re-assembling what NvChad read
through `chadrc` at boot"). That reasoning stopped applying once this
plugin owned its own render entrypoint (step 4) instead of routing through
NvChad's — `:UI variant` (2026-09-12) is exactly that re-assembly, done on
demand instead of never.
