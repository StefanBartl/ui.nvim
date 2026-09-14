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
| `:UI picker` | — | Open a floating theme picker (`lib.nvim.ui.kit.select`) that applies the highlighted theme live as you move; `<CR>` keeps it, `<Esc>`/`q` restores the theme that was active before it opened |
| `:UI toggle` | — | Swap between the two themes in `theme.theme_toggle` |
| `:UI transparency` | — | Toggle background transparency |
| `:UI screenkey` | `on`/`off` for an explicit state | Toggle the in-editor keystroke HUD (`ui.screenkey`) -- off by default, for recording demos/GIFs |
| `:UI variant {name}` | completes over the statusline-variant registry | Switch the active statusline preset at runtime |
| `:UI variants` | — | List the registered variants (four shipped presets plus anything a host registered), marking the active one |
| `:UI tabline-style {name}` | completes over the tabline-style registry | Switch the active chip-boundary look at runtime |
| `:UI tabline-styles` | — | List the registered tabline styles (`rounded`/`square`/`divider` plus anything a host registered), marking the active one |
| `:UI status` | — | Current theme, transparency state, statusline variant, tabline style |
| `:UI help` | — | The subcommand list, in a float |

**Completion is two-level:** the first argument completes over the thirteen
subcommands, the argument after `theme`/`variant`/`tabline-style` over the
theme list / the variant registry / the tabline-style registry
respectively (`screenkey`/`transparency` complete `on`/`off` the same way). The theme list is `vim.fn.getcompletion("", "color")` at the
moment `<Tab>` is pressed, so a colorscheme installed mid-session is
offered; the variant and tabline-style lists are
`ui.config.variants.list()`/`ui.tabline.styles.list()`, so an entry a host
registers from its own config (`require("ui.config.variants").register(...)`
/ `require("ui.tabline.styles").register(...)`) shows up in completion the
moment that call runs, next to the shipped entries.

**`:UI variant` is a runtime switch, unlike the preset choice
`ui.config.STATUSLINE_VARIANT` used to be.** It calls `ui.config.setup({
variant = name })` and then `ui.statusline.render.enable()` with the result
-- both steps, since assembling a config and pointing `vim.o.statusline` at
it are separate. `ui.config.get_variant()` reports whichever name was
actually resolved last, which is what changes after a switch (the
`STATUSLINE_VARIANT` constant itself is only the boot-time default and does
not change).

**`:UI tabline-style` is simpler: one field, not a separate config.** Unlike
a statusline variant (a whole `{order, modules}` table), `cfg.style` is one
field of the tabline's single shipped config -- switching it mutates that
field in place on the table `ui.tabline.render.current()` already holds,
then `redrawtabline` makes it visible immediately. No `ui.config.setup()`
round-trip needed. `require("ui.tabline.styles")` is the registry: three
shipped decorators (`rounded` default, `square`, `divider`) plus whatever a
host registers under its own name via `.register(name, fn)` -- see that
module's own doc comment for the decorator function shape.

**No range, no count.** Every subcommand acts on global state — the theme, the
transparency flag — where a line range or a repeat count has no meaning.

---

## Keymaps

Registered by `ui.bindings.keymaps.setup()`, which `ui.setup` calls when
`all` or `keymaps` is set, with `opts.keymaps` handed straight through as
`ui.bindings.keymaps.setup(opts.keymaps)`'s own parameter -- no `{ all =
true }` needed; that would in fact warn now ("no such keymap action: all"),
since `all` was this module's own bespoke flag, not something
`keymap.register()` itself knows. Every
left-hand side below is a shipped default, not fixed, and every action binds
by default -- nothing here needs to be turned on: `ui.setup({ keymaps = {
next = "<C-Right>", close = false } })` renames `next` and drops `close`
entirely, leaving every other action (`prev`, `close_all`, `move_right`,
`move_left`, `move_to_tab`, `toggle_theme`, `theme_picker`) at its default.
`keymaps =
false` (or
`ui.bindings.keymaps.setup(false)` directly) is the one-line "none of them"
switch, the same shape `my.nvim`'s own keymaps use.

### Buffers

| Key | `opts.keymaps` name | Mode | Does |
| --- | --- | --- | --- |
| `<Tab>` | `next` | `n` | Next buffer |
| `<S-Tab>` | `prev` | `n` | Previous buffer |
| `<leader>bc` | `close` | `n` | Close the current buffer (or `{count}` of them), keeping the window layout. An uncounted close (`1<leader>bc`, i.e. the plain keypress) briefly flashes the chip before closing; `{count}>1` closes immediately, unflashed |
| `<leader>bq` | `close_all` | `n` | Close every listed buffer in the current tab -- all flash together first, then close as one batch |

The flash on an uncounted close means a `:confirm`-style prompt for an
unsaved buffer now appears ~120ms later than a direct close would. Usually
unnoticeable; a deliberate trade-off for click-parity feedback, not a bug.

### Tabs

| Key | `opts.keymaps` name | Mode | Does |
| --- | --- | --- | --- |
| `<leader>tr` | `move_right` | `n` | Move the current buffer one position right in the tabline |
| `<leader>tl` | `move_left` | `n` | Move it one position left |
| `<leader>tt` | `move_to_tab` | `n` | Move the current buffer into a new tab |

### Theme

| Key | `opts.keymaps` name | Mode | Does |
| --- | --- | --- | --- |
| `<leader>ut` | `toggle_theme` | `n` | Toggle between the two themes in `theme.theme_toggle` -- same as `:UI toggle` |
| `<leader>uP` | `theme_picker` | `n` | Open the visual theme picker with live preview -- same as `:UI picker` |

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
| `ui_tabline_highlights` | `tabline/highlights` | Re-derives the `UiTb*` groups from `TabLine`/`TabLineFill`/`TabLineSel` on `ColorScheme` |
| `ui_tabline_utils_cache` | `tabline/utils` | Clears the devicon-color and built-highlight-group caches on `ColorScheme` |
| `ui_tabufline_state` | `bindings/keymaps/tabufline/state` | Maintains `vim.t.bufs` (`BufAdd`/`BufEnter`/`tabnew`/`BufDelete`/quickfix `FileType`) |

---

## What deliberately has no binding

| Thing | Why |
| --- | --- |
| A dedicated statusline-variant keymap | `:UI variant {name}` (see Commands above) covers it — a command with completion over the registry is more discoverable than a keymap would be for something with more than two states |
| A `bindings/autocmds.lua` | There is no plugin-level autocmd to put in it. Every one of the ten above belongs to the cache it clears — a central registrar would be a second source of truth for the same state. This is a documented deviation from `NEW-08`, not an oversight |
| Individual statusline segments | They are on or off by which variant is assembled, not by a key. Four toggles for four segments would be more surface than the choice deserves |
| A default keymap for `:UI screenkey` | It's a demo/recording aid, not something reached for during normal editing -- a keymap would occupy a slot for a toggle nobody hits by muscle memory. `:UI screenkey` is discoverable via `:UI help`/`<Tab>` like every other one-off subcommand |

**The statusline variant used to be listed here as a setup()-time-only
choice** ("switching it at runtime would mean re-assembling what NvChad read
through `chadrc` at boot"). That reasoning stopped applying once this
plugin owned its own render entrypoint (step 4) instead of routing through
NvChad's — `:UI variant` (2026-09-12) is exactly that re-assembly, done on
demand instead of never.
