# Statusline modules — ui.nvim

Every segment this plugin ships, in one place — so building your own
statusline is picking from a list and wiring it in, not reading source to
find out what exists. This is a catalog, not a new mechanism: every module
below is exactly one `order` key plus, for the non-builtin ones, one
`modules` entry — the same `ui.config.setup()`/`opts.variant` shape
[configuration.md](configuration.md) already documents. Writing your own
module from scratch, the way `docs/examples/personal-statusline-example.lua`
does for `mode`/`git`/`cursor`, stays exactly as possible as before this page
existed.

`:UI modules` prints the same list from inside Neovim, read from
[`lua/ui/statusline/catalog.lua`](../lua/ui/statusline/catalog.lua) — this
page and that command can't drift apart, they're the same data.

---

## Table of contents

- [Built into the "default" theme](#built-into-the-default-theme)
- [Standalone modules](#standalone-modules)
- [Building your own module](#building-your-own-module)
- [What is deliberately not here](#what-is-deliberately-not-here)

---

## Built into the "default" theme

`ui.statusline.themes.default` is the fallback module set every preset that
does not name its own `theme` resolves against (see that module's own doc
comment). Add any of these keys to your own `order` — no `modules` entry
needed unless you want to override how it renders.

| Key | Shows | Needs | Used by |
| --- | --- | --- | --- |
| `mode` | Current Vim mode, as a filled colour chip | — | default, minimal, lsp, blocks |
| `file` | File name and devicon | — | default |
| `git` | Branch name plus added/changed/removed counts | gitsigns.nvim | default, minimal, blocks |
| `lsp_msg` | Live LSP progress message (hidden below 120 columns) | — | default |
| `diagnostics` | Per-severity error/warn/hint/info counts | — | default, minimal, lsp, blocks |
| `lsp` | Name of the attached LSP client | — | default, minimal, lsp, blocks |
| `cwd` | Current working directory's basename (hidden below 85 columns) | — | default, minimal |
| `cursor` | Line/column position | — | default, minimal, lsp, blocks |

```lua
-- Minimal wiring: just the key, nothing in `modules`.
order = { "mode", "%=", "diagnostics", "lsp" },
```

---

## Standalone modules

Each needs the key in `order` **and** a `modules` entry that requires and
calls it — one line, always the same shape:

```lua
local lazy = require("lib.lua.lazy")
local plugin_progress = lazy.require("ui.statusline.modules.plugin_progress")

-- ...
order = { "mode", "%=", "plugin_progress" },
modules = {
  plugin_progress = function()
    return plugin_progress()
  end,
},
```

| Key | Shows | Needs | Source |
| --- | --- | --- | --- |
| `plugin_progress` | Whichever plugin is currently running a long operation | `lib.nvim.progress` | `ui.statusline.modules.plugin_progress` |
| `plugin_summary` | lazy.nvim's own/external plugin count, e.g. `"12/48"` | lazy.nvim | `ui.statusline.modules.plugin_summary` |
| `casedesk` | Current case's short info (number, company, reply count) plus an SLA badge | casedesk.nvim | `ui.statusline.modules.casedesk` |
| `filetree_cwd_mode` | filetree.nvim's cwd-mode badge (`PROJECT`/`LOCK`/`MANUAL`/…), as a filled capsule | filetree.nvim | `ui.statusline.modules.filetree_cwd_mode` |
| `undo_depth` | Undo steps available on the current branch, plus a glyph if the undo tree has branched | — | `ui.statusline.modules.undo_depth` |
| `search_count` | `[current/total]` match position while `hlsearch` is active | — | `ui.statusline.modules.search_count` |
| `breadcrumbs` | Repo-relative path + LSP/Treesitter symbol context, mode-band coloured | — | `ui.statusline.modules.lsp` |

A soft dependency ("Needs" above) degrades to an empty segment when the
plugin isn't installed — none of these throw or need a guard in your own
config.

`breadcrumbs` needs one extra piece most others don't — a highlight group to
colour it by mode:

```lua
local hl_module = lazy.require("ui.statusline.modules.highlighting")
local lsp_module = lazy.require("ui.statusline.modules.lsp")

modules = {
  breadcrumbs = function()
    local band = hl_module.mode_band_group()
    local content = lsp_module.render_breadcrumbs_inherit_lspfirst(band)
    if not content or content == "" then
      return ""
    end
    return hl_module.hl_open(band) .. content
  end,
},
```

If your winbar (`ui.winbar.set()`, or a content plugin writing
`vim.wo.winbar` directly) already draws breadcrumbs, you almost certainly do
not also want this one — see `ui.winbar`'s own doc comment. Two independent
implementations of the same idea drawing the same information twice is
exactly the redundancy `docs/examples/personal-statusline-example.lua`
removed it for.

---

## Building your own module

A module is `fun(): string`, nothing more — anything below is a piece to
build one from, not a module itself:

| Piece | For |
| --- | --- |
| `ui.statusline.utils.primitives` | Raw building blocks the "default" theme wraps with highlights: `git()`, `lsp()`, `diagnostics()`, `file()`, `lsp_msg()`, `is_activewin()`, `modes` (the mode-name/highlight-suffix table) |
| `ui.statusline.utils.get_separators` | Resolves a `separator_style` name (or `{left, right}` table) to the actual glyph pair |
| `ui.statusline.cursor_ctl` | Row/column scroll-progress rendering — what several presets' own `cursor` override uses |
| `ui.statusline.modules.highlighting` | `mode_band_group()` (the current mode's highlight group, for colouring anything by mode), `hl_open()`/`hl_wrap()`/`stl_strip_hl()` |

`docs/examples/personal-statusline-example.lua` is a full example built
entirely from these plus the table above — copy it as a starting point.
