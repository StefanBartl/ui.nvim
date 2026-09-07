# Roadmap — ui.nvim

Nothing here is implemented. This is the scope, the measured starting point,
and the decisions that have to be made before the first line of `lua/` exists.

---

## Table of contents

- [Starting point](#starting-point)
- [The two coupling points](#the-two-coupling-points)
- [Open decisions](#open-decisions)
- [Planned scope, by area](#planned-scope-by-area)
- [Order of work](#order-of-work)
- [Explicitly out of scope](#explicitly-out-of-scope)

---

## Starting point

An existing implementation, in daily use, living inside one Neovim config as
`lua/wkdnvchad/**` — 41 files, ~4,500 lines — plus a thin `chadrc.lua` adapter.

| Area | Files | What is there |
| --- | --- | --- |
| `config/` | 8 | Theme assembly, six statusline layouts (`normal`, `base`, `lspbased`, `custom`, `custom_light`, `custom_minimal`) |
| `ui/statusline/` | 26 | Breadcrumbs, cursor progress, devicons, formatter state, highlighting, an LSP module with document-symbol and Treesitter symbol sources, test-runner and plugin-progress segments, a working-directory-mode badge |
| `ui/highlights/` | 1 | Diagnostic highlight groups |
| `mappings/` | 3 | Buffer and tab navigation, tabline reordering |
| `usrcmd/` | 3 | `:UI theme/themes/toggle/transparency/status/help` and theme management |

The extraction is therefore mostly a move, the way
[my.nvim](https://github.com/StefanBartl/my.nvim)'s was — with one difference
that is the whole point of this repository: my.nvim had nothing to decouple
from, and this has two things.

---

## The two coupling points

Measured, not estimated: every `require` in those 4,500 lines, grouped.

### `nvchad.stl.utils`

Statusline primitives — separator glyph sets and the mode table (mode code →
label and highlight group).

Small, and replaceable without a decision: both are data. The mode table has
to be written out once, and the separator sets are a handful of string pairs.
The only judgement call is whether the mode table becomes configuration or
stays a constant.

### `nvconfig`

The distribution's resolved UI configuration, read for theme name,
transparency and statusline settings.

This is the one that carries a real decision, and it is
[open](#open-decisions): where does a palette come from once this is gone.

### Everything else

[lib.nvim](https://github.com/StefanBartl/lib.nvim) — lazy requires, LRU
memoization, string helpers, the autocmd/keymap/usercmd wrappers, notify, the
UI highlight helper, buffer-to-tab movement — plus Neovim's own API, plus one
soft dependency on a sibling plugin for a status badge.

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

1. Repository scaffold to the project gate: `config/DEFAULTS.lua`, `bindings/`,
   `@types/`, `health.lua`, `TESTS/` with a runner that fails loudly,
   `.luacheckrc`, a LuaLS zero measurement before the first push.
2. Move the implementation over as one prefix rename, verified by grep — the
   same way my.nvim was moved, and for the same reason: a rename is provable,
   a restructure is not.
3. Replace `nvchad.stl.utils` — data, no decision.
4. Decide [the palette question](#open-decisions) and replace `nvconfig`.
5. Host wiring, then remove the old modules from the config only after the new
   ones demonstrably load.

Steps 1–2 could start today. Step 4 is the one that needs thinking rather than
typing.

---

## Explicitly out of scope

| Not | Where it belongs |
| --- | --- |
| Cursorline, mode tinting, indent guides, occurrence highlighting | [my.nvim](https://github.com/StefanBartl/my.nvim) — content, not frame |
| The declarative option set | my.nvim |
| A colorscheme | See [decision 1](#open-decisions); the goal is to consume one, not to be one |
| A plugin bundle | This is a UI layer, not a distribution |
| A statusline DSL | Presets, not a framework — see [decision 2](#open-decisions) |
