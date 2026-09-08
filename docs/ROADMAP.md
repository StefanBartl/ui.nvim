# Roadmap — ui.nvim

The implementation moved in on 2026-09-08 (one prefix rename out of the host
config, verified by grep). What is left is the decoupling: this plugin's own
code no longer requires NvChad to load, assemble, render, or move buffers and
tabs (steps 1-5, all 2026-09-08); the theme palette and the host wiring do
not — steps 6-7. This file is the scope, the measured coupling, and the
decisions still
open.

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

The extraction was mostly a move — a prefix rename out of the host config,
verified by grep — with one difference that is the whole point of this
repository: it still has five things to decouple from a distribution.

---

## The coupling to NvChad — corrected measurement

**The first measurement in this file was wrong, and this section replaces it.**
It claimed "exactly two symbols" and made a point of the number. It counted
`require("x")` with one regex and never matched `pcall(require, "x")` — which
is the form most of this code uses, because most of these calls are already
guarded. Three symbols were invisible to it.

Counted properly, both call forms, on 2026-09-08, before step 3:

| Symbol | Calls | Files | Guarded by `pcall` | What it provides |
| --- | ---: | ---: | ---: | --- |
| `nvchad.stl.utils` | 21 | 10 | 14 | Statusline primitives: separator glyph sets, the mode table |
| `nvconfig` | 3 | 3 | **0** | NvChad's resolved UI configuration, read for separator style |
| `nvchad.tabufline` | 3 | 2 | 3 | Buffer/tab movement and close for the tabline keymaps |
| `base46` | 4 | 2 | 4 | Theme loading, transparency toggle |
| `base46.themes` | 1 | 1 | 1 | The theme name list `:UI theme` completes over |

**Step 3 is done (2026-09-08).** `nvchad.stl.utils` is ported to
`lua/ui/statusline/utils/primitives.lua`; the three unguarded `nvconfig`
reads (`config/statusline/custom_minimal.lua`, `config/statusline/normal.lua`,
`statusline/utils/get_separators.lua`) are each a local `separator_style`
literal now. Verified headless with NvChad entirely off the runtimepath:
every statusline variant module requires and `ui.config.setup()` assembles
without error. `nvchad.tabufline`, `base46`, `base46.themes` are unchanged.

### A second correction: the symbol count was never the whole coupling

Finishing step 3 did not make the plugin render without NvChad, and it was
never going to — the "5 symbols, 32 call sites" measurement only ever counted
`require()` calls inside *this repository*. It could not see the one piece
that matters most, because that piece has never lived here: something has to
turn the `{order, modules}` table `ui.config.setup()` assembles into
`vim.o.statusline`, and today that something is entirely NvChad's —
`nvchad.init` sets `vim.o.statusline = "%!v:lua.require('nvchad.stl.<theme>')
()"`, and `nvchad.stl.<theme>` calls `nvchad.stl.utils.generate(order,
modules)`. This plugin had never owned a render entrypoint of its own — see
step 4 in [Order of work](#order-of-work) below, **done as of 2026-09-08**,
which closed exactly this gap: `ui.statusline.render` is that walk now, own
code, own tests, no NvChad symbol touched. Step 3's own text ("no decision,
just typing") had not anticipated needing it.

### What each one actually needs

| Symbol | Replacement |
| --- | --- |
| `nvchad.stl.utils` | ~~Data. Separator sets and the mode table.~~ Done — `ui.statusline.utils.primitives` |
| `nvconfig` | ~~Only `ui.statusline.separator_style` is read.~~ Done — each variant owns a `SEPARATOR_STYLE` literal |
| `nvchad.tabufline` | ~~Buffer/tab movement.~~ Done — `ui.bindings.keymaps.tabufline.state`. `lib.nvim.buf_win_tab`'s existing modules turned out to have no overlap once checked (see step 5 below) |
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

Breadcrumbs are currently rendered into `vim.wo.winbar` from outside this
plugin. A winbar is frame, not content, so by this repository's own dividing
line it belongs here. Against that: the breadcrumb *content* is produced by a
separate content layer's context providers, deeply tied to that layer's own
configuration registry.

Likely answer: that layer keeps producing the string and gains a way to hand
it over, `ui.nvim` decides where it is drawn. Not settled.

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
3. ~~Replace `nvchad.stl.utils` and the three unguarded `nvconfig` reads.~~ —
   done 2026-09-08: `lua/ui/statusline/utils/primitives.lua`, and each
   statusline variant now owns its own `separator_style` literal. Verified
   headless with NvChad off the runtimepath: every variant module requires,
   `ui.config.setup()` assembles, `luacheck`/`stylua` clean, spec suite green.
4. ~~Give this plugin its own statusline render entrypoint.~~ — done
   2026-09-08: `lua/ui/statusline/render.lua`. `generate(cfg)` is the
   `order`/`modules` walk (`nvchad/stl/utils.lua`'s `generate()`, own code);
   `enable(cfg)`/`render()`/`disable()` are the `vim.o.statusline` wiring
   (`nvchad/init.lua`'s one-line assignment, own code). A key a variant's
   own `modules` does not cover falls back to `ui.statusline.themes.default`
   — a ported `nvchad/stl/default.lua`, the only base theme any of the six
   shipped variants actually needs (`custom`'s `theme = "minimal"` and
   `custom_minimal`'s `theme = "default"` both cover every key in their own
   `order` themselves, so neither ever reads the fallback). `file()`, the
   `lsp_msg` state and the `LspProgress` autocmd — the other things this
   plugin used to reach into `nvchad.stl.utils` for but step 3 had not
   ported, because nothing needed them until something actually called
   `generate()` — moved into `ui.statusline.utils.primitives` alongside it.
   Verified headless, NvChad off the runtimepath: all six shipped variants
   assemble through `ui.config.setup()` and render end to end through
   `generate()` (`TESTS/statusline_render_spec.lua`); `:checkhealth ui`'s
   dependency section no longer stops at NvChad being absent.
   `luacheck`/`stylua` clean, full spec suite green.

   **One real bug turned up proving this end to end**, not a hypothetical:
   `ui.config.statusline.custom`'s `cursor` module called `get_separators()`
   with no argument — every other call site in that file passes
   `SEPARATOR_STYLE`, this one didn't, and `get_separators.lua` indexed a nil
   table. Silent before this step: `nvchad.stl.utils.generate()` does not
   `pcall` a module call, so the failure only ever surfaced with the
   cursor-progress mode active, live, under the real host. `generate()` here
   does `pcall` each module (a broken segment renders empty and warns once,
   rather than taking the whole statusline down on every redraw) — which is
   what caught it in a headless test the moment `custom` was exercised as a
   normal case rather than a special one. Fixed in the same commit.
5. ~~Replace `nvchad.tabufline`.~~ — done 2026-09-08:
   `lua/ui/bindings/keymaps/tabufline/state.lua`. `nvchad.tabufline` never
   appeared as a `require()` in this repo's own three call sites by
   accident, the same way `nvconfig` didn't at step 4 -- what those three
   call sites actually needed was `close_buffer()`/`move_buf()`, but what
   made `next()`/`prev()` (already NvChad-independent code) do anything at
   all was `vim.t.bufs` -- populated and kept current by `BufAdd`/
   `BufEnter`/`tabnew`/`BufDelete` autocmds that lived in NvChad's own
   `nvchad/tabufline/lazyload.lua`, `require`d from `nvchad/init.lua`, never
   named in this repo. Same shape of gap as step 4's render entrypoint, one
   level down: the render entrypoint was missing pipe-work outside this
   repo's `require()` graph; here it was state bookkeeping outside it.
   `state.lua` ports both the bookkeeping and the two functions, own code,
   `TESTS/tabufline_state_spec.lua` (12 tests) drives real buffer/tab
   operations against it headless, without NvChad. The roadmap's own claim
   that `lib.nvim.buf_win_tab` "already does part of it" did not hold up
   once checked -- grepped for `close_buffer`/`move_buf`/`vim.t.bufs` across
   that module, no match; it solves a different problem (safe-save, capture,
   tab utilities). What is intentionally NOT here, same reasoning as step 4:
   a rendered tabline (`vim.o.tabline` / `nvchad.tabufline.modules`) --
   separate, larger scope, see "Planned scope, by area > Tabline" above.
6. Decide [the palette question](#open-decisions) and replace `base46`.
7. Host wiring, then remove `lua/wkdnvchad/` from the config only after the
   new modules demonstrably load.

Step 6 is next, and the one that needs thinking rather than typing.

---

## Explicitly out of scope

| Not | Because |
| --- | --- |
| Cursorline, mode tinting, indent guides, occurrence highlighting | Content, not frame — out of scope here |
| The declarative option set | Content, not frame |
| A colorscheme | See [decision 1](#open-decisions); the goal is to consume one, not to be one |
| A plugin bundle | This is a UI layer, not a distribution |
| A statusline DSL | Presets, not a framework — see [decision 2](#open-decisions) |
