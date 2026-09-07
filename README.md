> **Planning stage — not implemented.** This repository holds the scope and the
> reasoning, and no `lua/` tree yet. Nothing here is installable. An empty
> plugin that can be added to a spec and does nothing would be worse than no
> repository at all, so there deliberately is no entry point.

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
![Status](https://img.shields.io/badge/status-planning-lightgrey)

The frame around the window: statusline, tabline, theme assembly. Planned as
the layer that lets a Neovim config stand on its own instead of on a
distribution's UI.

---

## Table of contents

- [What this is for](#what-this-is-for)
- [Scope](#scope)
- [The measurement](#the-measurement)
- [What it is not](#what-it-is-not)
- [Status](#status)
- [License](#license)

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
page. Roughly 4,500 lines of statusline, tabline and theme code already run
in one config against NvChad. The interesting number is how much of it is
actually coupled — see [The measurement](#the-measurement).

---

## Scope

| Area | What it covers |
| --- | --- |
| Statusline | Several complete layouts, an LSP-aware breadcrumb segment, cursor-progress indicators, file icons, formatter and diagnostic state, test-runner and plugin-progress segments |
| Tabline | Buffer and tab navigation, buffer reordering, moving a buffer to another tab |
| Theme | Palette assembly, a theme toggle, transparency, the `:UI` command that drives all of it |
| Highlights | The groups the frame paints with, kept stable across theme switches |

The sibling plugin [my.nvim](https://github.com/StefanBartl/my.nvim) is the
other half of the same split, and the line between them is worth stating
plainly:

> **my.nvim paints inside the window. ui.nvim paints the frame around it.**

Cursorline, mode tinting, indent guides, occurrence highlighting and the
declarative option set are content — they work with any statusline and any
distribution, and they are already extracted. Statusline, tabline and theme
assembly are frame.

---

## The measurement

The reason this is a plan and not a guess. The existing implementation's
coupling to NvChad was measured rather than estimated: every `require` in
those 4,500 lines was extracted and grouped.

The result is **two symbols**:

| Symbol | What it provides |
| --- | --- |
| `nvchad.stl.utils` | Statusline primitives — separators, the mode table |
| `nvconfig` | The distribution's resolved UI/theme configuration, read-only |

Everything else it uses is either
[lib.nvim](https://github.com/StefanBartl/lib.nvim) (the shared runtime) or
Neovim's own API. The original design note assumed "seven files reference
`nvchad.*`" and treated the decoupling as the large, uncertain part of the
work. It is not: two symbols, one of them a read of configuration and the
other a small helper table.

That does not make the work trivial — a palette has to come from somewhere
once `nvconfig` is gone, and that is a real decision about whether to depend
on a colorscheme library or ship a palette. But it does make it a bounded
decision rather than an open-ended port.

---

## What it is not

| Not | Because |
| --- | --- |
| A colorscheme | It arranges and applies colours; it does not define a palette from scratch. What it reads a palette *from* is the open question above |
| A distribution | No plugin list, no opinionated bundle. One UI layer |
| A statusline framework | It ships layouts, not a DSL for building them. A framework is what you write when you do not know what you want; this starts from four layouts that are already in daily use |
| Where content highlighting goes | That is [my.nvim](https://github.com/StefanBartl/my.nvim). See [Scope](#scope) |

---

## Status

Planning. The scope above is settled; the implementation has not started.

The full plan, including the migration order and the open questions, is in
the author's own notes rather than here — this repository will get its
`docs/ROADMAP.md` filled in as decisions are made. See
[docs/ROADMAP.md](docs/ROADMAP.md) for what is written down so far.

---

## License

MIT — see [LICENSE](LICENSE).
