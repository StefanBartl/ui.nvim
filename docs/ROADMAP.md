# Roadmap — ui.nvim

The implementation moved in on 2026-09-08 (one prefix rename out of the host
config, verified by grep). What is left is the decoupling: this plugin still
requires NvChad, and `:checkhealth ui` says so as an error rather than a note.
This file is the scope, the measured coupling, and the decisions still open.

---

## Table of contents

- [Starting point](#starting-point)
- [The coupling to NvChad — corrected measurement](#the-coupling-to-nvchad--corrected-measurement)
- [Open decisions](#open-decisions)
- [Planned scope, by area](#planned-scope-by-area)
- [Order of work](#order-of-work)
- [Explicitly out of scope](#explicitly-out-of-scope)

---

## Starting point

The implementation came from one Neovim config's `lua/wkdnvchad/**` — 41
files, ~4,500 lines — plus a thin `chadrc.lua` adapter that stays in the host.
It is `lua/ui/**` here now.

| Area | Files | What is there |
| --- | --- | --- |
| `config/` | 8 | Theme assembly, six statusline layouts (`normal`, `base`, `lspbased`, `custom`, `custom_light`, `custom_minimal`) |
| `statusline/` | 26 | Breadcrumbs, cursor progress, devicons, formatter state, highlighting, an LSP module with document-symbol and Treesitter symbol sources, test-runner and plugin-progress segments, a working-directory-mode badge |
| `highlights/` | 1 | Diagnostic highlight groups |
| `bindings/keymaps/` | 3 | Buffer and tab navigation, tabline reordering |
| `bindings/usrcmds/` | 3 | `:UI theme/themes/toggle/transparency/status/help` and theme management |

The extraction was mostly a move, the way
[my.nvim](https://github.com/StefanBartl/my.nvim)'s was — with one difference
that is the whole point of this repository: my.nvim had nothing to decouple
from, and this has five things.

---

## The coupling to NvChad — corrected measurement

**The first measurement in this file was wrong, and this section replaces it.**
It claimed "exactly two symbols" and made a point of the number. It counted
`require("x")` with one regex and never matched `pcall(require, "x")` — which
is the form most of this code uses, because most of these calls are already
guarded. Three symbols were invisible to it.

Counted properly, both call forms, on 2026-09-08:

| Symbol | Calls | Files | Guarded by `pcall` | What it provides |
| --- | ---: | ---: | ---: | --- |
| `nvchad.stl.utils` | 21 | 10 | 14 | Statusline primitives: separator glyph sets, the mode table |
| `nvconfig` | 3 | 3 | **0** | NvChad's resolved UI configuration, read for separator style |
| `nvchad.tabufline` | 3 | 2 | 3 | Buffer/tab movement and close for the tabline keymaps |
| `base46` | 4 | 2 | 4 | Theme loading, transparency toggle |
| `base46.themes` | 1 | 1 | 1 | The theme name list `:UI theme` completes over |

Five symbols, 32 call sites. That is still a bounded job — 22 of the 32 are
already behind a `pcall`, so they have a defined absent-behaviour and only
need something to fall back *to* — but it is not the "two data symbols" the
first pass claimed, and the plan below was written against that wrong number.

The three unguarded `nvconfig` reads are the sharp edge: `config/statusline/
custom_minimal.lua`, `config/statusline/normal.lua` and
`statusline/utils/get_separators.lua` throw outright without NvChad. Those are
where a decoupling has to start, not where it can end.

### What each one actually needs

| Symbol | Replacement |
| --- | --- |
| `nvchad.stl.utils` | Data. The separator sets are a handful of string pairs and the mode table is one constant. No decision, just typing |
| `nvconfig` | Only `ui.statusline.separator_style` is read. Once the separators are this plugin's own, so is the setting |
| `nvchad.tabufline` | Buffer/tab movement. `lib.nvim.buf_win_tab` already does part of it; the rest is `nvim_buf_delete` and list bookkeeping |
| `base46` / `base46.themes` | **The open decision.** This is the palette question below |

---

## Open decisions

### 1. Where the palette comes from

Three options, none of them obviously right:

| Option | For | Against |
| --- | --- | --- |
| Depend on a colorscheme library (base46 or similar) | The existing theme list keeps working unchanged; no palette to maintain | Trades one dependency for another. If that library is the distribution's own, nothing was decoupled |
| Read the active colorscheme's own highlight groups | No palette at all — `nvim_get_hl` against `Normal`, `Comment`, `DiagnosticError` and so on. Works with every colorscheme automatically | Groups that a colorscheme does not define have to degrade gracefully, and "the right colour for a statusline section" is not always one of the groups it does define |
| Ship a palette | Full control, no dependency | Now this is partly a colorscheme, which [the README says it is not](../README.md#what-it-is-not) |

**Leaning:** the second, with the third as a fallback layer for groups that
are missing. That keeps the promise that this is not a colorscheme, and it is
the only option that works with a colorscheme the author did not anticipate.

### 2. Whether the statusline layouts stay six

Six layouts is a lot for one user, and some of them differ by a segment. They
may collapse into fewer layouts plus a segment list — which is the difference
between shipping presets and shipping a framework, and the README currently
promises presets. Decide by looking at what the six actually differ in.

### 3. What `chadrc.lua` becomes

Today it is the distribution's own configuration entry point, delegating to
the implementation. Without the distribution there is no `chadrc.lua`, and the
host calls `require("ui").setup(...)` directly — which is simpler, but means
the migration has a step where both exist.

### 4. Whether the winbar comes here

`my.nvim` renders breadcrumbs into `vim.wo.winbar`. A winbar is frame, not
content, so by this repository's own dividing line it belongs here. Against
that: the breadcrumb *content* is produced by my.nvim's context providers,
which are deeply tied to its configuration registry.

Likely answer: my.nvim keeps producing the string and gains a way to hand it
over, ui.nvim decides where it is drawn. Not settled.

---

## Planned scope, by area

### Statusline

- Layout assembly from named segments
- Segments: mode, file name and icon, git state, diagnostics, LSP client and
  progress, formatter, cursor position and progress, test-runner state,
  breadcrumbs
- Per-segment enable/disable and ordering
- Debounced updates — the existing implementation already does this, and the
  reason is measured: a statusline is re-evaluated on nearly every event

### Tabline

- Buffer and tab list with icons and modified state
- Navigation, closing, reordering
- Moving a buffer to another tab

### Theme

- `:UI theme {name}` with completion, `:UI toggle` between two configured
  themes, `:UI transparency`
- Re-applying every group the frame owns after a switch — the failure mode
  this has to get right is a theme change leaving half the statusline in the
  old palette

### Health

`:checkhealth ui` — required for every plugin in this collection. What it has
to answer: which layout is active, whether every segment resolves, whether the
palette source is present, and which colorscheme the groups were derived from.

---

## Order of work

1. ~~Move the implementation over as one prefix rename, verified by grep~~ —
   done 2026-09-08. `wkdnvchad.` → `ui.`, plus flattening the `ui/ui/` stutter
   the new root name produced.
2. ~~Repository scaffold to the project gate~~ — done: `config/DEFAULTS.lua`,
   `bindings/{keymaps,usrcmds}`, `@types/`, `health.lua`, `.luacheckrc`,
   `TESTS/` with a runner that fails loudly, LuaLS at zero.
3. **Replace `nvchad.stl.utils` and the three unguarded `nvconfig` reads.**
   Data and one setting; no decision, just typing. This is what makes the
   plugin load at all without NvChad.
4. Replace `nvchad.tabufline` — buffer/tab movement, partly already in
   `lib.nvim.buf_win_tab`.
5. Decide [the palette question](#open-decisions) and replace `base46`.
6. Host wiring, then remove `lua/wkdnvchad/` from the config only after the
   new modules demonstrably load.

Step 3 is the next one and needs no decision. Step 5 is the one that needs
thinking rather than typing.

---

## Explicitly out of scope

| Not | Where it belongs |
| --- | --- |
| Cursorline, mode tinting, indent guides, occurrence highlighting | [my.nvim](https://github.com/StefanBartl/my.nvim) — content, not frame |
| The declarative option set | my.nvim |
| A colorscheme | See [decision 1](#open-decisions); the goal is to consume one, not to be one |
| A plugin bundle | This is a UI layer, not a distribution |
| A statusline DSL | Presets, not a framework — see [decision 2](#open-decisions) |
