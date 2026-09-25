# What it does and what not

| Area | What it covers |
| --- | --- |
| Statusline | Several complete layouts, an LSP-aware breadcrumb segment, cursor-progress indicators, file icons, formatter and diagnostic state, test-runner and plugin-progress segments; hovering a module shows what it means and highlights it, right/double click opens a menu to add/remove modules and save the current layout so it survives a restart |
| Tabline | Buffer and tab navigation, buffer reordering (keys, a "move to position" prompt, dragging a chip, auto-scrolling at the edges), a right-click menu of per-tab actions, pinning a tab, reopening a recently closed one, moving a buffer to another tab |
| Theme | Palette assembly, a theme toggle, transparency, the `:UI` command that drives all of it |
| Highlights | The groups the frame paints with, kept stable across theme switches |
| Winbar | Owns the `vim.wo.winbar` write (`ui.winbar.set`) — a content plugin (breadcrumbs, typically) keeps producing the string and hands it over instead of writing the surface itself |
| UI Kit | `ui.kit` (`lua/ui/kit/README.md`) — a themed, composable popup/menu/prompt toolkit (note, toast, input, select, form, menu, confirm, compare, an interactive picker, a layout engine); `ui.contextmenu` (`lua/ui/contextmenu/README.md`) — right-click menu item builders and a renderer on top of it. Freshly ported from `lib.nvim.ui.kit`/`lib.nvim.contextmenu` — usable on its own (`require("ui.kit")`/`require("ui.contextmenu")`), but the ~30 repos that consume the `lib.nvim` originals have not moved over yet, and there is no install-spec toggle wiring it in or out yet either |
| Right-click menu | `ui.menu` (`lua/ui/menu/README.md`) — the general menu on `<RightMouse>`/`<A-b>`, drawn by `ui.contextmenu`: a fly-out per installed sister plugin (`<plugin>.integrations.menu`, each with a three-layer opt-out: installed, ui.nvim's `integrations.<name>`, the plugin's own switch), the general sections Code/Clipboard/File/Delete/Tools (destructive entries off by default), and rows of your own by plugin/filetype/section. "Copy/Delete Marked" act on the selection captured when the menu opened. Explicit-only: `ui.setup({ menu = { ... } })` |
| Screenkey | `ui.screenkey` — an in-editor keystroke HUD for recording demos/GIFs (`vim.on_key()` + `vim.fn.keytrans()`, rendered in a `ui.kit.surface` corner float). Off by default; `:UI screenkey` toggles it for the session |
| Colour picker | `ui.colorpicker` — an interactive picker in a `ui.kit.surface` float (hue row, saturation × lightness grid for that hue, shades of the pick, `#hex`/`rgb()`/`hsl()` readout), driven by the window's own cursor; `<CR>` writes the colour back over the literal it opened on or after the cursor, `y` yanks. `:UI color [#hex]`, or `require("ui.colorpicker").open({ on_pick = ... })` from a host's menu. The colour math is `ui.colorpicker.color` |
| Zen | `ui.zen` — distraction-free writing: the current buffer in a centred float (`width` 120 or a fraction) over a backdrop dimmed by `backdrop`, `laststatus`/`showtabline`/`ruler`/`showcmd` saved and restored, the gutter options emptied per `wo`; the cursor travels in and back out, a buffer switch inside the box is followed. `:UI zen [on|off]`; `require("ui.zen").setup({...})` for the tunables. The restore hangs off `WinClosed`, so `:q` in the box works too |
| Notify | `ui.notify` — `vim.notify` as stacked, level-coloured toasts (`ui.kit.toast`) with per-level timeouts and a ring-buffer history that `:UI notify history` opens in a `ui.kit.viewer`; `disable()` restores the previous handler exactly. Explicit-only: `ui.setup({ notify = true })` or `:UI notify on` |
| Keys | `ui.keys` — the keymaps under a prefix as a menu (`ui.kit.menu`): buffer-local over global, `which_key_ignore` respected, groups named from `setup({ groups })`, a picked row feeds the keys. `:UI keys [prefix]`; `require("ui.keys").open("<leader>s")` from a host key. Deliberately not a timeout popup |
| Context | `ui.context` — a sticky code-context overlay: the enclosing function/class/loop lines that scrolled off the top, pinned over the window's first rows (Tree-sitter ancestor walk from the first visible line, node types matched by pattern rather than per-grammar queries, drawn in a non-focusable `relative="win"` float with the source line numbers in the gutter; in Markdown -- including `markdown.mdx` and any filetype mapped to the `markdown` parser -- the pinned heading chain, capped by heading level and by row count; a body node's lone `{` line is never pinned). Off by default; `ui.setup({ sticky = true })` (or `context = true`) or `:UI sticky` |
| Window picker | `ui.windowpicker` — pick a window by letter: a one-cell floating hint (`lib.nvim.window.make_scratch`, not `ui.kit`) centred over every eligible window, one keypress jumps to it. Replaces `s1n7ax/nvim-window-picker`'s `pick_window()` — a drop-in for anything that calls `require("window-picker").pick_window(...)`. `filter_rules`-style options (`include_current_win`, `autoselect_one`, `bo.filetype`/`bo.buftype` exclusions) via `require("ui.windowpicker").setup({...})`; `:UI winpick` picks and jumps directly |

The dividing line this repository draws is worth stating plainly:

> **Content lives inside the window. `ui.nvim` paints the frame around it.**

Cursorline, mode tinting, indent guides, occurrence highlighting and a
declarative option set are content — they work with any statusline and any
distribution, and are out of scope here. Statusline, tabline and theme
assembly are frame.

## What it is not

| Not | Because |
| --- | --- |
| A colorscheme | It arranges and applies colours; it does not define a palette from scratch. Accent colors come from the active colorscheme's own highlight groups (`ui.theme.palette`) |
| A distribution | No plugin list, no opinionated bundle. One UI layer |
| A statusline framework | It ships presets, not a DSL for building them. A framework is what you write when you do not know what you want; this starts from four generic layouts already in daily use, plus a documented way to bring your own (`opts.variant`, see [docs/examples/](examples/)) |
| A NvChad replacement | It never covered anything outside statusline/tabline/theme, and does not now either. Everything else NvChad's own plugin bundle installed (Mason, which-key, Treesitter, Telescope, gitsigns, nvim-web-devicons, and more) needs its own, separate plugin spec once NvChad is gone — see [nvchad-migration.md](nvchad-migration.md) |
