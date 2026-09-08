> **Alpha — and it still requires NvChad.** The implementation moved in on
> 2026-09-08, but the decoupling has not happened yet: five NvChad/base46
> symbols are still reached for, three of them unguarded. `:checkhealth ui`
> reports that as an error, not a note. Installing this without NvChad gets you
> a plugin that throws. Removing that coupling is the whole
> [roadmap](docs/ROADMAP.md).

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

Five symbols, 32 call sites, counted on 2026-09-08:

| Symbol | Calls | Guarded | What it provides |
| --- | ---: | ---: | --- |
| `nvchad.stl.utils` | 21 | 14 | Statusline primitives: separator glyphs, the mode table |
| `nvconfig` | 3 | **0** | NvChad's resolved UI configuration, read for separator style |
| `nvchad.tabufline` | 3 | 3 | Buffer/tab movement for the tabline keymaps |
| `base46` | 4 | 4 | Theme loading and the transparency toggle |
| `base46.themes` | 1 | 1 | The theme list `:UI theme` completes over |

Twenty-two of the thirty-two already sit behind a `pcall`, so they have a
defined behaviour when the symbol is absent and need something to fall back
*to* rather than a rewrite. The three unguarded `nvconfig` reads are the sharp
edge — they throw outright — and they are where step 3 of the roadmap starts.

> **An earlier version of this section claimed "exactly two symbols" and made
> a point of the number.** It was wrong. The measurement counted
> `require("x")` with a single regex and never matched `pcall(require, "x")`,
> which is the form most of this code uses — precisely because most of these
> calls are already guarded. Three symbols were invisible to it. The number is
> corrected here rather than quietly fixed, because the wrong one was used to
> argue that the decoupling was smaller than the original design note assumed.

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
