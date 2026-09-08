> **Alpha — and it still requires NvChad.** The implementation moved in on
> 2026-09-08; step 3 of the decoupling (2026-09-08 too) ported the statusline
> primitives and separator config this plugin's own code used to read from
> NvChad, and every module now loads with NvChad entirely absent. What is
> still missing is bigger than the remaining symbols (`nvchad.tabufline`,
> `base46`): this plugin has never had its own statusline render entrypoint —
> `vim.o.statusline` and the `generate()` loop are still entirely NvChad's.
> `:checkhealth ui` reports that as an error, not a note. Removing it is the
> whole [roadmap](docs/ROADMAP.md).

# ui.nvim

```
██╗   ██╗██╗   ███╗   ██╗██╗   ██╗██╗███╗   ███╗
██║   ██║██║   ████╗  ██║██║   ██║██║████╗ ████║
██║   ██║██║   ██╔██╗ ██║██║   ██║██║██╔████╔██║
██║   ██║██║   ██║╚██╗██║╚██╗ ██╔╝██║██║╚██╔╝██║
╚██████╔╝██║██╗██║ ╚████║ ╚████╔╝ ██║██║ ╚═╝ ██║
 ╚═════╝ ╚═╝╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝╚═╝     ╚═╝
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

- [Roadmap](docs/ROADMAP.md) — the measured NvChad coupling and what is left to do.
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
| [NvChad](https://github.com/NvChad/NvChad) (v2.5) | **required today** — see below. Removing this is the roadmap |

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

Step 3 (also 2026-09-08) ported `nvchad.stl.utils` into this plugin's own
`ui.statusline.utils.primitives` and gave every statusline variant its own
`separator_style` literal instead of reading `nvconfig`. Neither symbol is
required by this plugin's code any more, and every statusline variant module
now loads and assembles with NvChad entirely absent from the runtimepath
(verified headless). `nvchad.tabufline`, `base46` and `base46.themes` are
unchanged — steps 4 and 5.

> **That still does not mean this plugin renders without NvChad, and the
> "five symbols, 32 call sites" count above was never the whole coupling.**
> `ui.config.setup()` only ever returned a config table; something else has
> always had to turn `{order, modules}` into `vim.o.statusline`. That
> something is entirely NvChad's: `nvchad.init` sets `vim.o.statusline =
> "%!v:lua.require('nvchad.stl.<theme>')()"`, and `nvchad.stl.<theme>` calls
> `nvchad.stl.utils.generate()` — a render entrypoint this plugin has never
> had one of its own. None of steps 3-5 as written closes that gap; it needs
> its own line in [the roadmap](docs/ROADMAP.md).
>
> A separate, earlier version of this section claimed "exactly two symbols"
> and made a point of the number. It was wrong: the measurement counted
> `require("x")` with a single regex and never matched `pcall(require, "x")`,
> which is the form most of this code uses — precisely because most of these
> calls are already guarded. Three symbols were invisible to it.

---

## What it is not

| Not | Because |
| --- | --- |
| A colorscheme | It arranges and applies colours; it does not define a palette from scratch. What it reads a palette *from* is [the open decision](docs/ROADMAP.md#open-decisions) |
| A distribution | No plugin list, no opinionated bundle. One UI layer |
| A statusline framework | It ships layouts, not a DSL for building them. A framework is what you write when you do not know what you want; this starts from six layouts that are already in daily use |
| Where content highlighting goes | Out of scope here — see [Scope](#scope) |

---

## Status

Alpha. The code is here and runs; the decoupling has not happened.

```vim
:checkhealth ui
```

names every dependency, says which NvChad symbols are missing when they are,
and is explicit that NvChad is a hard requirement rather than an optional
integration. [docs/ROADMAP.md](docs/ROADMAP.md) has the measured coupling, the
order of work, and the four decisions still open.

---

## License

MIT — see [LICENSE](LICENSE).
