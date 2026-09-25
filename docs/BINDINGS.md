# Bindings — ui.nvim

Every command, keymap and autocommand this plugin registers. Read by
`:Bindings` out of the installed plugin directory, so this file is the source
of truth rather than a copy of one.

Nothing here is registered until `require("ui").setup({ all = true })` runs,
**except `:KitPreview`** (see Commands below): `ui.kit`'s module load
registers it unconditionally, so any sibling plugin doing
`require("ui.kit")` turns it on regardless of whether `ui.setup()` ever runs.

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
| `:UI picker` | — | Open a floating theme picker (`ui.kit.select`) that applies the highlighted theme live as you move; `<CR>` keeps it, `<Esc>`/`q` restores the theme that was active before it opened |
| `:UI toggle` | — | Swap between the two themes in `theme.theme_toggle` |
| `:UI transparency` | — | Toggle background transparency |
| `:UI screenkey` | `on`/`off` for an explicit state | Toggle the in-editor keystroke HUD (`ui.screenkey`) -- off by default, for recording demos/GIFs |
| `:UI color [#hex]` | an optional start colour | Open the interactive colour picker (`ui.colorpicker`): a hue row, a saturation × lightness grid, a shades row; the window cursor selects, `<CR>` replaces the `#hex` the picker opened on (or inserts after the cursor), `y` yanks, `q` closes |
| `:UI zen` | `on`/`off` for an explicit state | Toggle the distraction-free box (`ui.zen`): the current buffer alone in a centred 120-column float over a dimmed backdrop, statusline/tabline/ruler hidden and the gutter emptied; closing the float any way restores everything |
| `:UI notify` | `on`/`off` for an explicit state; `history` opens the recorded notifications in a viewer; `clear` forgets them | Toggle `ui.notify`: `vim.notify` rendered as level-coloured `ui.kit.toast`s with per-level timeouts, every message recorded in a ring buffer -- off by default; `ui.setup({ notify = true })` turns it on at startup |
| `:UI keys [prefix]` | a key prefix as typed (`<leader>s`, `<C-w>`, `g`); default `<leader>` | Open the mappings under that prefix as a `ui.kit.menu`: one row per next key with the mapping's `desc`, prefixes with more below them as drill-down groups (named via `ui.keys.setup({ groups = ... })`), picking a row runs the mapping. Asked for, never timeout-triggered -- which-key's popup without the pending-key interception |
| `:UI sticky` (older spelling: `:UI context`) | `on`/`off`/`toggle` for an explicit state; `status` prints state, depth and row cap; `depth [1-6\|all]` the deepest Markdown heading level that is pinned; `lines [filetype] [n]` how many rows the context may take (0 = unlimited), for one filetype or for all the others; `reset` drops what `depth`/`lines` changed and returns to the configured values; `up [n]` jumps to the n-th enclosing scope above the window's top (1 = innermost, works with the overlay off) | Toggle the sticky code-context overlay (`ui.context`): the enclosing function/class/loop lines, or in Markdown the heading chain, pinned over the window's first rows while the body scrolls -- off by default; `ui.setup({ sticky = true })` (or the older `context = true`) turns it on at startup. `depth` and `lines` change the running session; with `persist = true` in the setup table they are also saved (`stdpath("state")/ui.nvim/sticky.json`) and come back at the next start, otherwise set `headings.max_level` and `max_lines` in that table |
| `:UI variant {name}` | completes over the statusline-variant registry | Switch the active statusline preset at runtime |
| `:UI variants` | — | List the registered variants (four shipped presets plus anything a host registered), marking the active one |
| `:UI tabline-style {name}` | completes over the tabline-style registry | Switch the active chip-boundary look at runtime |
| `:UI tabline-styles` | — | List the registered tabline styles (`rounded`/`square`/`divider` plus anything a host registered), marking the active one |
| `:UI status` | — | Current theme, transparency state, statusline variant, tabline style |
| `:UI help` | — | The subcommand list, in a float |

**`:KitPreview`** (`ui.kit`'s own command, not a `:UI` subcommand) opens the
live theme playground: a tab split with an editable Lua config buffer on the
left and a rendered widget gallery on the right that restyles as the config
settles (`lua/ui/kit/preview.lua`). Registered as soon as `ui.kit`'s module
loads — `require("ui.kit")` from any plugin, not just this one's own
`setup()` — so it is reachable even in a host that never calls
`ui.setup()`. The config buffer's contents are evaluated as Lua a short,
debounced delay after the last keystroke, not on every one (see the
in-buffer reference block, or `EVAL_DEBOUNCE_MS` in `preview.lua`).

**Completion is two-level, three for `sticky`:** the first argument completes
over the subcommands, the argument after `theme`/`variant`/`tabline-style` over the
theme list / the variant registry / the tabline-style registry
respectively (`screenkey`/`transparency`/`zen` complete `on`/`off` the same way, `sticky`/`context` add `toggle`/`status`/`depth`/`lines`/`reset`/`up`, `notify` adds `history`/`clear`). A third argument completes after `sticky depth` (`1`-`6`, `all`) and `sticky lines` (filetypes). The theme list is `vim.fn.getcompletion("", "color")` at the
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
entirely, leaving every other action (`prev`, `close_all`, `toggle_pin`,
`reopen_closed`, `move_right`, `move_left`, `move_to_tab`, `toggle_theme`,
`theme_picker`) at its default.
`keymaps =
false` (or
`ui.bindings.keymaps.setup(false)` directly) is the one-line "none of them"
switch, the same shape `my.nvim`'s own keymaps use.

### Right-click menu

Only when `ui.setup({ menu = { ... } })` (or `require("ui.menu").setup()`)
is called -- it takes over a global mapping, so it is opt-in.

| Key | Mode | Action | Option |
| --- | --- | --- | --- |
| `<RightMouse>` | normal, visual | Open the menu at the pointer. Inside a Visual selection it is kept; elsewhere the cursor moves to the pointer. On the tab bar / statusline the native click runs instead (their own menus) | `mouse = false` |
| `<A-b>` | normal, visual | Open the same menu at the cursor | `key = "<other>"` / `false` |

See [`lua/ui/menu/README.md`](../lua/ui/menu/README.md).

### Buffers

| Key | `opts.keymaps` name | Mode | Does |
| --- | --- | --- | --- |
| `<Tab>` | `next` | `n` | Next buffer |
| `<S-Tab>` | `prev` | `n` | Previous buffer |
| `<leader>bc` | `close` | `n` | Close the current buffer (or `{count}` of them), keeping the window layout. An uncounted close (`1<leader>bc`, i.e. the plain keypress) briefly flashes the chip before closing; `{count}>1` closes immediately, unflashed |
| `<leader>bq` | `close_all` | `n` | Close every listed buffer in the current tab -- all flash together first, then close as one batch. Pinned buffers are never among them |
| `<leader>bp` | `toggle_pin` | `n` | Pin/unpin the current buffer's tab -- see [Pinning](#pinning) |
| `<leader>bu` | `reopen_closed` | `n` | Reopen the most recently closed tab -- see [Reopening a closed tab](#reopening-a-closed-tab) |

The flash on an uncounted close means a `:confirm`-style prompt for an
unsaved buffer now appears ~25ms later than a direct close would. The delay
is deliberately much shorter than the flash itself (~120ms, which still runs
its full course): just long enough for the flash to reach the screen once, not
long enough to make a click on an "x" feel laggy.

### Tabs

| Key | `opts.keymaps` name | Mode | Does |
| --- | --- | --- | --- |
| `<leader>tr` | `move_right` | `n` | Move the current buffer one position right in the tabline |
| `<leader>tl` | `move_left` | `n` | Move it one position left |
| `<leader>tt` | `move_to_tab` | `n` | Move the current buffer into a new tab |

### Pinning

A pinned tab always sits ahead of every unpinned one in the tabline
(`vim.t.bufs`'s own "pins first" invariant -- `move_buf_to`/`move_buf`/a drag
all clamp their target into the buffer's own region, so a pin can never end
up mixed in among unpinned tabs), stays on screen even when there are more
open buffers than the bar can show, and is excluded from every bulk close
(`<leader>bq`, and the tab menu's `Close others`/`Close to the left`/`Close
to the right`/`Close saved`). A pinned chip shows a pin glyph in place of its
close button/modified dot; clicking it unpins. Middle-click and a plain
left-click on the "x" both refuse to close a pinned chip outright (a pin
notification instead) -- unpin it first, or use the tab menu's own `Close`,
which is a deliberate action through a menu rather than a stray click.

Pin state is tab-local (`vim.t`-scoped) and not persisted across a restart.

| Key | `opts.keymaps` name | Mode | Does |
| --- | --- | --- | --- |
| `<leader>bp` | `toggle_pin` | `n` | Pin/unpin the current buffer's tab |

Also reachable from the tab menu's `Pin`/`Unpin` entry (below), or by
clicking a pinned chip's own pin glyph to unpin it.

### Reopening a closed tab

A ring of the last 20 real files closed this session (not scratch buffers,
terminals, or the quickfix list), newest first, deduplicated by path -- the
tabline's counterpart to a browser's Ctrl+Shift+T. Recorded on `BufDelete`
while the buffer still exists, so its name and last cursor position (the
`"` mark) are captured before it is gone.

| Key | `opts.keymaps` name | Mode | Does |
| --- | --- | --- | --- |
| `<leader>bu` | `reopen_closed` | `n` | Reopen the most recently closed tab |

`:edit`s the file, restores the cursor, and places it back at the slot it
closed from in the CURRENT tab (not necessarily the tab it originally
closed from) -- or just switches to it if it is already open there. Unsaved
changes in the closed buffer do not come back, only the file as it sits on
disk; a file deleted since it closed reopens nothing and notifies instead of
raising. The tab menu's `Reopen closed tab ▸` submenu (below) lists the
whole ring, not just the newest entry.

### Tabline mouse

Not keymaps -- the tabline's own click protocol reports which button hit which
chip, so nothing here is bound and nothing needs `ui.setup({ keymaps = ... })`.

| Gesture | On | Does |
| --- | --- | --- |
| Left click | a chip | Switch to that buffer (flashes) |
| Left press and drag | a chip | Carry it along the bar; it re-slots live under the pointer, the drop needs no extra step. Holding at either edge auto-scrolls the visible window (see "Dragging" below) |
| Right click | a chip, or its "x"/pin glyph | Open that tab's context menu (below) |
| Middle click | a chip | Close it -- refused on a pinned chip |
| Left click | a chip's "x" | Close it -- refused on a pinned chip |
| Left click | a pinned chip's pin glyph (its "x" slot) | Unpin it |

Each of the first three of "context_menu"/"drag"/"middle_click_close" has an
opt-out on the tabline config (see
[configuration.md](configuration.md#tabline-mouse-behaviour)); with one off,
that gesture just switches to the chip, as any click used to. Pin protection
has no opt-out.

**The tab context menu** (`ui.tabline.menu`) holds only actions on that tab,
drawn through `ui.contextmenu` -- so nvzone/menu when it is installed, the kit
menu otherwise -- with the chip kept lit while it is up. Entries gate
themselves: nothing to close on the left of the first tab, `Save` only on a
modified one.

| Group | Entries |
| --- | --- |
| *(the file name)* | `Save` (modified only), `Pin`/`Unpin`, `Close` |
| Close | `Close others`, `Close to the left`, `Close to the right`, `Close saved` (only when saved and unsaved tabs both exist) -- all three exclude pinned tabs from the set they close, and drop out entirely once nothing unpinned is left to close |
| Move | `Move to position…` (asks for a number: `3` is an absolute slot, `+2`/`-1` are relative), `Move left`, `Move right`, `Move to start`, `Move to end` |
| Buffer | `Copy path ▸` (absolute, relative, file name), `Open in split`, `Open in vertical split`, `Move to new tab page`, `Reopen closed tab ▸` (one entry per closed-tab ring slot; absent while the ring is empty) |

Every "close" entry asks once, up front, when any of the buffers it would
close has unsaved changes -- the same single prompt `<leader>bq` shows.
Closing a tab that is not the current one leaves the current window where it
is. `Reopen closed tab` is not really about the clicked tab -- every chip's
menu offers the same ring, since one has to hang the submenu off SOME chip.

**A host with its own global `<RightMouse>` mapping** still reaches the chip
menu, provided that mapping replays the native click first
(`vim.cmd.exec('"normal! \\<RightMouse>"')` -- which is what makes the chip's
click handler fire). It then has to step aside, or two menus open on top of
each other:

```lua
vim.keymap.set({ "n", "v" }, "<RightMouse>", function()
  vim.cmd.exec('"normal! \\<RightMouse>"')
  if require("ui.tabline.menu").pointer_on_tabline() then
    return -- the chip's own menu is already on its way
  end
  -- ... the host's general menu ...
end)
```

**Dragging auto-scrolls at either edge.** When more buffers are open than
the bar can show, the visible run normally follows the current buffer; a
drag re-slots among the visible chips only. Holding the pointer still
against the left or right edge of the chip run (within a few columns, no
further movement needed) instead nudges the window one chip further that
way on a short timer, revealing chips further from the current buffer to
drop onto -- released, or the drag ends, and the window goes back to
following the current buffer. `ui.tabline.scroll` owns this; nothing here
is configurable.

The mouse gesture itself claims `<LeftDrag>` and `<LeftRelease>` for exactly
the length of one press-drag-release -- they are unmapped again on release
(and after 5 s of silence, in case a release never arrives), and any mapping
they shadowed is put back, so ordinary drag-select is untouched between
drags.

### Statusline mouse

Not keymaps either, with one exception (hover) -- everything but that rides
the statusline's own click protocol, same as the tabline above. Nothing here
needs `ui.setup({ keymaps = ... })`.

| Gesture | On | Does |
| --- | --- | --- |
| Hover (rest the pointer) | any module | After a moment, a small float shows that module's `ui.statusline.catalog` summary; the module's own text recolors to a single accent (amber/orange in most colorschemes) for as long as it stays hovered |
| Right click | any module | Open that module's own menu if it has one (`git_clickable`: branch switch/copy/details), otherwise the generic "manage this module" menu (below) |
| Double click | a plain module (no left-click action of its own) | The generic "manage this module" menu |
| Double click | `git_clickable`/`variant` (left click opens a `vim.ui.select` picker) | Runs left click again, same as a plain second click -- **not** the manage menu: Neovim's click protocol calls the handler once per physical click, so the FIRST click of a double click already fires with `clicks == 1` before the second arrives with `clicks == 2`; wiring the menu to `dbl` here would open it on top of the picker that first click had just opened |

Hover needs `'mousemoveevent'` (Neovim 0.10+; on an older Neovim it degrades
to "no hover", never an error) and binds one real keymap, `<MouseMove>` in
`n`/`i`/`v`, registered by `ui.statusline.hover` itself as soon as a
statusline is enabled -- there is nothing to configure and no entry in the
table above because it is not one this config or a host would bind.

**The "manage this module" menu** (`ui.statusline.menu`) holds two groups:

| Group | Entries |
| --- | --- |
| *(the clicked module's key)* | `Remove <key>` (only when it is currently in `order`) |
| — | `Add module ▸` -- every catalogued key not currently in `order`, each with a short summary |
| Layout | `Save current layout` (writes the live `order` to disk, restored on every future start -- see [modules.md](modules.md#hover-tooltip-and-the-manage-this-module-menu)), `Clear saved layout` (only once something is actually saved) |

Add/remove is runtime-only (reverts on restart) unless "Save current layout"
was used; both mutate the live `Ui.Statusline.Config` `render.enable()` was
last given and trigger a redraw.

**A host with its own global `<RightMouse>` mapping** needs the same
step-aside `ui.tabline.menu.pointer_on_tabline()` already gets, or a right
click on the statusline opens both this menu and the host's own general one:

```lua
vim.keymap.set({ "n", "v" }, "<RightMouse>", function()
  vim.cmd.exec('"normal! \\<RightMouse>"')
  if require("ui.tabline.menu").pointer_on_tabline() then
    return
  end
  if require("ui.statusline.menu").pointer_on_statusline() then
    return -- the statusline's own menu is already on its way
  end
  -- ... the host's general menu ...
end)
```

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
