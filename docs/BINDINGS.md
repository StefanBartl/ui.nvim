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
| `:UI theme {name}` | completes over installed base46 themes | Switch to a theme and reload every highlight |
| `:UI themes` | — | List the available themes, marking the active one |
| `:UI toggle` | — | Swap between the two themes in `base46.theme_toggle` |
| `:UI transparency` | — | Toggle background transparency |
| `:UI status` | — | Current theme, transparency state, statusline variant |
| `:UI help` | — | The subcommand list, in a float |

**Completion is two-level:** the first argument completes over the six
subcommands, the argument after `theme` over the theme names. The name list is
read from `base46.themes` at the moment `<Tab>` is pressed, so a theme
installed mid-session is offered.

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

`<leader>tr` and `<leader>tl` go through `nvchad.tabufline`, guarded by
`pcall` — without NvChad they are bound and do nothing. That is a known gap,
not a design: see [ROADMAP.md](ROADMAP.md).

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
| The statusline variant | Switching it at runtime would mean re-assembling what NvChad read through `chadrc` at boot. It is a `setup()`-time choice, and `:UI status` reports which one is active |
| A `bindings/autocmds.lua` | There is no plugin-level autocmd to put in it. Every one of the seven above belongs to the cache it clears — a central registrar would be a second source of truth for the same state. This is a documented deviation from `NEW-08`, not an oversight |
| Individual statusline segments | They are on or off by which variant is assembled, not by a key. Six toggles for six segments would be more surface than the choice deserves |
