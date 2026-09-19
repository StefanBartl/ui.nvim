# What it does and what not

| Area | What it covers |
| --- | --- |
| Statusline | Several complete layouts, an LSP-aware breadcrumb segment, cursor-progress indicators, file icons, formatter and diagnostic state, test-runner and plugin-progress segments |
| Tabline | Buffer and tab navigation, buffer reordering, moving a buffer to another tab |
| Theme | Palette assembly, a theme toggle, transparency, the `:UI` command that drives all of it |
| Highlights | The groups the frame paints with, kept stable across theme switches |
| Winbar | Owns the `vim.wo.winbar` write (`ui.winbar.set`) — a content plugin (breadcrumbs, typically) keeps producing the string and hands it over instead of writing the surface itself |
| UI Kit | `ui.kit` (`lua/ui/kit/README.md`) — a themed, composable popup/menu/prompt toolkit (note, toast, input, select, form, menu, confirm, compare, an interactive picker, a layout engine); `ui.contextmenu` (`lua/ui/contextmenu/README.md`) — right-click menu item builders and a renderer on top of it. Freshly ported from `lib.nvim.ui.kit`/`lib.nvim.contextmenu` — usable on its own (`require("ui.kit")`/`require("ui.contextmenu")`), but the ~30 repos that consume the `lib.nvim` originals have not moved over yet, and there is no install-spec toggle wiring it in or out yet either |
| Screenkey | `ui.screenkey` — an in-editor keystroke HUD for recording demos/GIFs (`vim.on_key()` + `vim.fn.keytrans()`, rendered in a `ui.kit.surface` corner float). Off by default; `:UI screenkey` toggles it for the session |
| Colour picker | `ui.colorpicker` — an interactive picker in a `ui.kit.surface` float (hue row, saturation × lightness grid for that hue, shades of the pick, `#hex`/`rgb()`/`hsl()` readout), driven by the window's own cursor; `<CR>` writes the colour back over the literal it opened on or after the cursor, `y` yanks. `:UI color [#hex]`, or `require("ui.colorpicker").open({ on_pick = ... })` from a host's menu. The colour math is `ui.colorpicker.color` |
| Zen | `ui.zen` — distraction-free writing: the current buffer in a centred float (`width` 120 or a fraction) over a backdrop dimmed by `backdrop`, `laststatus`/`showtabline`/`ruler`/`showcmd` saved and restored, the gutter options emptied per `wo`; the cursor travels in and back out, a buffer switch inside the box is followed. `:UI zen [on|off]`; `require("ui.zen").setup({...})` for the tunables. The restore hangs off `WinClosed`, so `:q` in the box works too |
| Context | `ui.context` — a sticky code-context overlay: the enclosing function/class/loop lines that scrolled off the top, pinned over the window's first rows (Tree-sitter ancestor walk from the first visible line, node types matched by pattern rather than per-grammar queries, drawn in a non-focusable `relative="win"` float with the source line numbers in the gutter). Off by default; `ui.setup({ context = true })` or `:UI context` |

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
