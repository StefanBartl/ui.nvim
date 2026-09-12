> **Alpha.** The implementation moved in on 2026-09-08; step 3 (2026-09-08)
> ported the statusline primitives and separator config this plugin's own
> code used to read from NvChad, step 4 (2026-09-08) gave it a statusline
> render entrypoint of its own — `ui.statusline.render`, the
> `vim.o.statusline` / `generate()` walk that used to be entirely
> `nvchad.init` + `nvchad.stl.utils.generate()` — step 5 (2026-09-08)
> replaced `nvchad.tabufline`: `vim.t.bufs` bookkeeping and buffer/tab
> movement are `ui.bindings.keymaps.tabufline.state`'s own code now. Step 6
> (2026-09-12) replaced `base46`: accent colors come from the active
> colorscheme's own highlight groups (`ui.theme.palette`), transparency is
> this plugin's own toggle (`ui.theme.transparency`), and theme switching is
> a real `:colorscheme` call, no bundled theme engine at all. Every module,
> every one of the six shipped statusline layouts end to end, buffer/tab
> navigation, and theme/transparency handling now work with **neither NvChad
> nor base46** on the runtimepath (verified headless). Only the *host* this
> plugin was extracted from still wires `chadrc.lua` to NvChad's own renderer
> (step 7, not done) — that is the one remaining piece.

# ui.nvim

```
██╗   ██╗██╗
██║   ██║██║
██║   ██║██║
██║   ██║██║
╚██████╔╝██║
 ╚═════╝ ╚═╝
       .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)

The frame around the window: statusline, tabline, theme assembly. The layer
meant to let a Neovim config stand on its own instead of on a distribution's
UI — which it does not do yet, because it is still standing on one.

---

## Table of contents

- [Documentation](#documentation)
- [What this is for](#what-this-is-for)
- [Scope](#scope)
- [Requirements](#requirements)
- [The coupling to NvChad](#the-coupling-to-nvchad)
- [What it is not](#what-it-is-not)
- [Status](#status)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where.

- [Configuration](docs/configuration.md) — both setup entry points and the six statusline variants.
- [Bindings cheatsheet](docs/BINDINGS.md) — commands, keymaps and autocommands.
- [Health check](docs/health.md) — what `:checkhealth ui` reports, line by line.

`:help ui` is the same reference inside the editor.

---

## What this is for

A Neovim configuration that uses a distribution gets its statusline, its
tabline and its theme handling from that distribution. Replacing pieces of
those — a different statusline layout, an LSP-aware breadcrumb segment, a
theme toggle — means writing code that reaches into the distribution's own
modules by name.

That code accumulates, and at some point it is doing most of the work while
still depending on the thing it replaced. `ui.nvim` is the plan for taking
that last step: the same UI, standing on Neovim's own APIs.

It starts from an existing, working implementation rather than from a blank
page: roughly 4,500 lines of statusline, tabline and theme code that ran in one
config against NvChad, moved here on 2026-09-08. It still runs against NvChad —
see [The coupling to NvChad](#the-coupling-to-nvchad) for exactly how much.

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required |
| [NvChad](https://github.com/NvChad/NvChad) (v2.5) | not required by this plugin's own code any more (steps 4-6) — still what the reference host's `chadrc.lua` routes rendering through until step 7 rewires it; see below |

Optional, each detected at runtime and blanking only its own segment:
`nvim-web-devicons` (file icons), `neotest` (test-runner segment),
`casedesk.nvim` (working-directory badge).

---

## Scope

| Area | What it covers |
| --- | --- |
| Statusline | Several complete layouts, an LSP-aware breadcrumb segment, cursor-progress indicators, file icons, formatter and diagnostic state, test-runner and plugin-progress segments |
| Tabline | Buffer and tab navigation, buffer reordering, moving a buffer to another tab |
| Theme | Palette assembly, a theme toggle, transparency, the `:UI` command that drives all of it |
| Highlights | The groups the frame paints with, kept stable across theme switches |

The dividing line this repository draws is worth stating plainly:

> **Content lives inside the window. `ui.nvim` paints the frame around it.**

Cursorline, mode tinting, indent guides, occurrence highlighting and a
declarative option set are content — they work with any statusline and any
distribution, and are out of scope here. Statusline, tabline and theme
assembly are frame.

---

## The coupling to NvChad

Counted on 2026-09-08, before step 3:

| Symbol | Calls | Guarded | What it provides |
| --- | ---: | ---: | --- |
| `nvchad.stl.utils` | 21 | 14 | Statusline primitives: separator glyphs, the mode table |
| `nvconfig` | 3 | **0** | NvChad's resolved UI configuration, read for separator style |
| `nvchad.tabufline` | 3 | 3 | Buffer/tab movement for the tabline keymaps |
| `base46` | 4 | 4 | Theme loading and the transparency toggle |
| `base46.themes` | 1 | 1 | The theme list `:UI theme` completes over |

Step 3 (2026-09-08) ported `nvchad.stl.utils` into this plugin's own
`ui.statusline.utils.primitives` and gave every statusline variant its own
`separator_style` literal instead of reading `nvconfig`. Neither symbol is
required by this plugin's code any more, and every statusline variant module
loads and assembles with NvChad entirely absent from the runtimepath.
`base46`/`base46.themes` are gone too as of step 6 — see below. This table
now describes history, not a current dependency: none of these five symbols
appear in this plugin's own code any more, under any name.

> **Step 3 alone did not mean this plugin rendered without NvChad, and the
> "five symbols, 32 call sites" count above was never the whole coupling.**
> `ui.config.setup()` only ever returned a config table; something else had
> to turn `{order, modules}` into `vim.o.statusline`. Before step 4 that
> something was entirely NvChad's: `nvchad.init` set `vim.o.statusline =
> "%!v:lua.require('nvchad.stl.<theme>')()"`, and `nvchad.stl.<theme>` called
> `nvchad.stl.utils.generate()`.
>
> **Step 4 (2026-09-08) closed that gap.** `ui.statusline.render.generate()`
> is the same walk, own code, own tests, and `enable()`/`render()`/
> `disable()` are the `vim.o.statusline` wiring around it. Every `order` key
> a variant's own `modules` does not cover falls back to
> `ui.statusline.themes.default` — the one theme any of the six shipped
> layouts actually needs; `minimal`/`vscode`/`vscode_colored` are not ported,
> since nothing here falls through to them (see that module's own doc
> comment). Proving it end to end (`TESTS/statusline_render_spec.lua`)
> surfaced one real bug along the way: `custom.lua`'s `cursor` module called
> `get_separators()` with no argument, indexing a nil table — silent under
> NvChad's own `generate()`, which does not `pcall` a module call, and only
> reachable with the cursor-progress mode active. Fixed in the same commit.
>
> What step 4 does **not** mean: that this plugin renders without NvChad
> *today*, for a user of the reference host it was extracted from. Nothing
> outside this plugin's own tests calls `enable()` yet — the host's
> `chadrc.lua` still hands its config to NvChad's own renderer, and rewiring
> that is step 7.
>
> **Step 5 (2026-09-08) replaced `nvchad.tabufline`, and found the same
> shape of gap one level down.** `nvchad.tabufline` never appeared as a
> `require()` at the three call sites that needed it by accident, any more
> than `nvconfig` did before step 4 — what those three sites called for was
> `close_buffer()`/`move_buf()`, but what made this plugin's own
> `next()`/`prev()` do anything at all was `vim.t.bufs`, and that list was
> built and kept current by autocmds that lived entirely in NvChad's own
> `nvchad/tabufline/lazyload.lua`, required from `nvchad/init.lua` and never
> named anywhere in this repo. `ui.bindings.keymaps.tabufline.state` ports
> the bookkeeping and the two functions; the roadmap's own claim that
> `lib.nvim.buf_win_tab` "already does part of it" turned out not to hold up
> once checked — grepped for the actual functions, no match. Not ported,
> same reasoning as step 4: a rendered tabline (`vim.o.tabline`) is separate,
> larger scope, still "Planned scope > Tabline".
>
> A separate, earlier version of this section claimed "exactly two symbols"
> and made a point of the number. It was wrong: the measurement counted
> `require("x")` with a single regex and never matched `pcall(require, "x")`,
> which is the form most of this code uses — precisely because most of these
> calls are already guarded. Three symbols were invisible to it.
>
> **Step 6 (2026-09-12) replaced `base46`, the last symbol on the list, and
> decided the open palette question in the process.** Of the three options
> weighed (depend on a colorscheme library, read the active colorscheme's own
> highlight groups, ship a palette), the second won on every axis that
> mattered — dependencies, security surface, and universality all point the
> same way once diagnostic highlight groups are the anchor, the same
> technique lualine's "auto" theme already relies on: `DiagnosticError` /
> `DiagnosticHint` / `DiagnosticInfo` / `DiagnosticOk` / `Comment` are close
> to universally defined, because built-in LSP diagnostics need them. The
> third option survives only as `ui.theme.palette`'s fallback layer, for a
> colorscheme that leaves one of those groups undefined.
>
> The only place this plugin ever read a *raw color value* out of base46 was
> `filetree_cwd_mode`'s cwd-mode badge (`base46.get_theme_tb("base_30")`) —
> everything else base46 touched was theme *switching*, not color data.
> Switching is now a real `pcall(vim.cmd.colorscheme, name)` (`ui.bindings
> .usrcmds.themes`), and the theme list is `getcompletion("", "color")` —
> every colorscheme Neovim can see, not a fixed ~50-name NvChad set. One
> deliberate scope cut alongside it: the old code persisted a theme choice by
> string-replacing a line in `chadrc.lua` on disk. That is gone, on purpose —
> choosing a startup colorscheme is the host's own `init.lua`, the same as
> any Neovim config, not something a UI-frame plugin should be rewriting
> files for.

---

## What it is not

| Not | Because |
| --- | --- |
| A colorscheme | It arranges and applies colours; it does not define a palette from scratch. Accent colors come from the active colorscheme's own highlight groups (`ui.theme.palette`, step 6) |
| A distribution | No plugin list, no opinionated bundle. One UI layer |
| A statusline framework | It ships layouts, not a DSL for building them. A framework is what you write when you do not know what you want; this starts from six layouts that are already in daily use |
| Where content highlighting goes | Out of scope here — see [Scope](#scope) |

---

## Status

Alpha. The code is here and runs, and steps 3-6 of the decoupling are done —
only the host wiring (step 7) is not. This plugin's own code needs neither
NvChad nor base46 any more, for any of statusline, tabline, or theme.

```vim
:checkhealth ui
```

names every dependency, reports its own statusline render entrypoint as
resolving and rendering standalone, and says whether NvChad is present as
information rather than a fatal error — it stopped being one at step 4.

---

## License

MIT — see [LICENSE](LICENSE).
