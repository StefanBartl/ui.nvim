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
- [Clickable modules](#clickable-modules)
- [Responsive mode](#responsive-mode)
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
| `casedesk` | Current case's short info (number, company, reply count) plus a yellow/red SLA urgency badge | casedesk.nvim | `ui.statusline.modules.casedesk` |
| `filetree_cwd_mode` | filetree.nvim's cwd-mode badge (`PROJECT`/`LOCK`/`MANUAL`/…), as a filled capsule; `opts.history = true` adds a 3-dot mode/root trail | filetree.nvim | `ui.statusline.modules.filetree_cwd_mode` |
| `undo_depth` | Undo steps available on the current branch, plus a glyph if the undo tree has branched | — | `ui.statusline.modules.undo_depth` |
| `search_count` | `[current/total]` match position while `hlsearch` is active | — | `ui.statusline.modules.search_count` |
| `diagnostics_sparkline` | A 20-glyph density row showing WHERE diagnostics sit in the buffer, not just how many | — | `ui.statusline.modules.diagnostics_sparkline` |
| `macro_counter` | Live keystroke count for the macro currently recording, e.g. `"@a · 23"` | — | `ui.statusline.modules.macro_counter` |
| `time_in_buffer` | Elapsed time since this buffer was first entered this session, e.g. `"12m"` | — | `ui.statusline.modules.time_in_buffer` |
| `github_stats_badge` | This week's view count for the repo the buffer is in, e.g. `"42 views this week"` — only inside a repo github_stats.nvim tracks | github_stats.nvim | `ui.statusline.modules.github_stats_badge` |
| `runtime_analysis_ampel` | Traffic-light glyph (🟢/🟡/🔴) for whether any runtime-analysis.nvim-instrumented plugin errored or ran slow today | runtime-analysis.nvim | `ui.statusline.modules.runtime_analysis_ampel` |
| `recommender_badge` | Count of recommender.nvim alias suggestions open for the current buffer, e.g. `"3 alias suggestions open for this file"` | recommender.nvim | `ui.statusline.modules.recommender_badge` |
| `session_status` | sessions.nvim's active session name, with a dirty marker (` *`) when the window/buffer layout changed since the last save or load | sessions.nvim | `ui.statusline.modules.session_status` |
| `sandbox_ambient` | sandbox.nvim's ambient container summary, e.g. `"docker (2/5)"` | sandbox.nvim | `ui.statusline.modules.sandbox_ambient` |
| `since_last_save` | Duration since the buffer became modified, escalating muted -> `DiagnosticWarn` -> `DiagnosticError` the longer it sits unsaved | — | `ui.statusline.modules.since_last_save` |
| `idle_clock` | Wall-clock time, e.g. `"14:32"`, shown only once the editor has been idle (`CursorHold`) and hidden again on the next keystroke | — | `ui.statusline.modules.idle_clock` |
| `breadcrumbs` | Repo-relative path + symbol context, mode-band coloured. The LSP half comes from `my.nvim` when it is installed; Tree-sitter otherwise — see below | my.nvim (soft) | `ui.statusline.modules.lsp` |
| `matchup_offscreen` | vim-matchup's offscreen-match source line (syntax-highlighted, gutter stripped), as one segment | vim-matchup, with `matchup_matchparen_offscreen = { method = "status_manual" }` | `ui.statusline.modules.matchup_offscreen` |

A soft dependency ("Needs" above) degrades to an empty segment when the
plugin isn't installed — none of these throw or need a guard in your own
config.

`diagnostics_sparkline` is a drop-in alternative to the plain `diagnostics`
segment above, not a companion to it — pick one or the other. The buffer is
split into 20 equal-line slices; each renders `ui.statusline.cursor_ctl
.renderer.pct_bar()`'s usual 8-level bar, height by how many diagnostics
land in that slice (relative to the busiest one), colour by the worst
severity present there. An empty slice renders in the same neutral colour
`lsp_msg` uses, not a severity one — "nothing here" is not "low severity of
something".

`macro_counter` shows `vim.fn.reg_recording()`'s register plus a live
keystroke count while it records — Neovim has no API to read a register's
content mid-recording, so the count comes from a `vim.on_key()` hook
bracketed by `RecordingEnter`/`RecordingLeave`, registered once at first
render.

`time_in_buffer` is per-session, not persisted across restarts or
aggregated across sessions — a `sessions.nvim`-based cross-session total is
a possible follow-up, not built here.

`github_stats_badge` resolves the current buffer's repo from its `git
remote get-url origin` (cached per directory) and only shows anything when
that repo is one `github_stats.nvim.config.get_repos()` actually tracks —
personal and low-utility by design, not something a generic statusline
plugin could offer.

`runtime_analysis_ampel` renders nothing until at least one plugin has a
runtime-analysis.telemetry instance (`known_namespaces()` non-empty), then
turns red if any instrumented function called today has ever errored, or
yellow if none have errored but one runs noticeably slow today (lifetime
mean call time above 50ms) — otherwise green. "Today" is the closest honest
proxy this data supports: telemetry aggregates calls rather than
timestamping each one, so this reads `Data.days[today]` for which functions
were active, not a true "this second" signal.

`filetree_cwd_mode`'s `opts.history = true` appends the last 3
`(mode, root)` badges as small dots after the usual capsule — filled for
the current one, hollow for earlier ones, each colored the same way the
capsule itself is. Off by default (a visual addition, not a fix). Keyed by
mode AND root, not mode alone: swapping between two `lock` cases with
different roots — the "jumping between two open cases" scenario the idea
names — produces two distinct dots even though the mode name never
changes. Tracked off filetree's own `User FiletreeCwdModeChanged` autocmd,
the same one this module's header already documents needing no extra
refresh wiring for.

`casedesk`'s SLA badge stays hidden until a clock drops under
`config.sla_warn_at` of its budget — casedesk.nvim's own SLA.md §6C design,
kept as-is here: an always-visible countdown for a case with a six-week
budget is noise, not signal. Once visible, it is two-stage rather than one
flat color: yellow (`%#DiagnosticWarn#`) while urgent but not yet overdue,
red (`%#DiagnosticError#`, marker `SLA!`) once the deadline has passed.

`since_last_save` renders nothing while the buffer is unmodified (right
after a save, or before the first edit) and shows a `● <duration>` once it
is — muted (`Comment`) at first, `DiagnosticWarn` past
`opts.warn_after_seconds` (default 60), `DiagnosticError` past
`opts.critical_after_seconds` (default 300) — softer than a plain `[+]`
flag that never distinguishes "just typed a character" from "forgot to
save for twenty minutes". The clock resets the moment the buffer is saved,
not merely capped or hidden.

`idle_clock` is built on `ui.statusline.utils.idle`, a small reusable
primitive (`is_idle()` / `wrap(segment_fn)`) for any segment that should
only appear once the editor has sat still for `updatetime` ms
(`CursorHold`/`CursorHoldI`) and disappear again on the very next
keystroke or cursor move — IDEEN-statusline.md's "Idle-Erweiterung nach N
Sekunden Inaktivität" names a mini git log or extra breadcrumb room as
other possible payloads; `idle_clock` is only the first (its own
suggested "Uhrzeit"), and a future one can reuse `ui.statusline.utils.idle`
without its own `CursorHold` wiring.

`session_status` and `sandbox_ambient` are thin requires, not
reimplementations: both sessions.nvim and sandbox.nvim already ship a
ready-made, statusline-plugin-agnostic component
(`sessions.statusline.component()`, `sandbox.statusline.status()`) that is
cached/rate-limited on their own side and documented safe to call on every
redraw, so this module is exactly the `pcall(require, ...)` wrapper needed to
drop either into an `order` list the same way as any other soft-dependency
module here — no separate caching, debouncing or error handling happens on
this side.

`recommender_badge` calls `recommender.nvim`'s own analyzer directly (the
one its `analyzer` config option already selects — `regex` by default) with
its own `threshold`/`custom_aliases`/`blacklist`, so this always agrees with
what `:Recommender` itself would report; no separate config to keep in
sync. The result is cached per buffer by `nvim_buf_get_changedtick`, so
editing invalidates it but an unrelated redraw does not re-scan the buffer.

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

## Clickable modules

`ui.statusline.utils.clickable` is a generic click layer: `wrap(segment_fn,
handlers)` takes any `fun(): string` and returns a new one whose rendered
text responds to mouse clicks, via one shared `%id@UiSlClick@...%X` protocol
rather than a hand-written global Vimscript function per action (that
one-global-per-action shape is what `ui.tabline.utils`' `btn` does instead,
which fits a small fixed set of tabline actions but does not scale to an open
set of statusline segments). `handlers` is a table keyed by button:
`{ l = fn, r = fn, m = fn }` for left/right/middle click, each `fun(): nil`.

The three modules below are all built the same way — `clickable.wrap()` on
top of an existing (or new) segment function, at module-load time, not
per-render:

```lua
-- ui.statusline.modules.diagnostics_clickable, in full:
local primitives = require("ui.statusline.utils.primitives")
local clickable = require("ui.statusline.utils.clickable")

return clickable.wrap(primitives.diagnostics, {
  l = function()
    vim.diagnostic.goto_next()
  end,
})
```

| Key | Shows | Needs | Source |
| --- | --- | --- | --- |
| `diagnostics_clickable` | `diagnostics`, plus a left click jumps to the next one (`vim.diagnostic.goto_next()`) | — | `ui.statusline.modules.diagnostics_clickable` |
| `git_clickable` | `git`, plus a left click opens a dependency-free branch switcher (`vim.ui.select` over `git branch`) and a right click a `lib.nvim.contextmenu` (switch / copy branch name / details) | gitsigns.nvim for the text; a `git` executable on `$PATH` for the clicks | `ui.statusline.modules.git_clickable` |
| `variant` | Active statusline variant name; a left click opens a quick-switch menu over `ui.config.variants.list()`, then runs `:UI variant <name>` | — | `ui.statusline.modules.variant` |

Wiring is identical to any other standalone module — the key in `order`, a
`modules` entry that requires and calls it:

```lua
order = { "mode", "%=", "diagnostics_clickable", "git_clickable" },
modules = {
  diagnostics_clickable = require("ui.statusline.modules.diagnostics_clickable"),
  git_clickable = require("ui.statusline.modules.git_clickable"),
},
```

Building your own clickable module is `clickable.wrap()` around whatever
segment function you already have (see the "Building your own module"
section below for the building blocks) — nothing about `wrap()` requires the
segment itself to be new.

---

## Responsive mode

`Ui.Statusline.Config.responsive = true` drops every `order` key NOT tagged
`essential` in the catalog while the statusline's own window
(`vim.g.statusline_winid`) is narrower than `responsive_width` (default 80
columns) — a narrow split falls back to "just the essentials" (`mode`,
`file`, `diagnostics`, `cursor`) instead of either hard-truncating every
segment's own text or requiring a hand-maintained second, "compact" `order`
list per preset that would drift from the real one the moment either
changes (IDEEN-statusline.md's "Adaptive Segmentauswahl nach
Fensterbreite" explicitly named that drift risk as the reason NOT to do
it that way):

```lua
ui.statusline.render.enable({
  order = { "mode", "file", "git", "%=", "lsp", "diagnostics", "cursor" },
  modules = { --[[ ... ]] },
  responsive = true,
  responsive_width = 90, -- optional; default 80
})
```

Off by default — an existing `order`/`modules` config renders identically
whether or not this page exists. Opting a segment INTO the always-kept set
is a one-line catalog change (`essential = true` on its entry in
[`lua/ui/statusline/catalog.lua`](../lua/ui/statusline/catalog.lua)), not a
per-preset one; a key `responsive` mode has never heard of (a host's own
custom module not in the catalog at all) is kept rather than silently
dropped, since this mechanism has no basis to judge it either way. The
`"%="` alignment break is always kept regardless of width.

---

## Building your own module

A module is `fun(): string`, nothing more — anything below is a piece to
build one from, not a module itself:

| Piece | For |
| --- | --- |
| `ui.statusline.utils.primitives` | Raw building blocks the "default" theme wraps with highlights: `git()`, `lsp()`, `diagnostics()`, `file()`, `lsp_msg()`, `is_activewin()`, `modes` (the mode-name/highlight-suffix table) |
| `ui.statusline.utils.get_separators` | Resolves a `separator_style` name (or `{left, right}` table) to the actual glyph pair |
| `ui.statusline.utils.clickable` | `wrap(segment_fn, handlers)` — makes any segment respond to left/right/middle clicks. See [Clickable modules](#clickable-modules) above |
| `ui.statusline.utils.idle` | `is_idle()` / `wrap(segment_fn)` — makes any segment render nothing until `CursorHold`/`CursorHoldI` (`updatetime` ms with no input), hidden again on the next keystroke or cursor move. `idle_clock` above is the first module built on it |
| `ui.statusline.cursor_ctl` | Row/column scroll-progress rendering — what several presets' own `cursor` override uses. `cursor_ctl.renderer.pct_bar(pct)` (an 8-level density glyph from a 0..100 value) is reusable on its own — `diagnostics_sparkline` above is the first module to do that |
| `ui.statusline.modules.highlighting` | `mode_band_group()` (the current mode's highlight group, for colouring anything by mode), `hl_open()`/`hl_wrap()`/`stl_strip_hl()` |

`docs/examples/personal-statusline-example.lua` is a full example built
entirely from these plus the table above — copy it as a starting point.

## Who owns the breadcrumb's symbol context

The async `textDocument/documentSymbol` engine behind `breadcrumbs` used to
live here. It lives in `my.nvim` now, as
`my.hl_config.breadcrumbs.ctx.providers.lsp_symbols` (cross-feature report,
finding B1).

Both plugins' roadmaps draw the same line: **`my.nvim` paints inside the
window — breadcrumb content — and `ui.nvim` is the frame.** Symbol context
is content, and having it here meant the frame plugin owned it while the
content plugin's own LSP stage read a buffer variable nothing ever set. One
feature in two places, with the working half on the wrong side.

So the flow is one-directional now, and it mirrors `ui.winbar` exactly:

| Surface | Produces the text | Places it |
| --- | --- | --- |
| winbar | `my.nvim` | `ui.nvim` (`ui.winbar.set`) |
| statusline breadcrumb | `my.nvim` | `ui.nvim` (`modules.lsp`) |

**Without `my.nvim` nothing breaks.** `ui.statusline.modules.lsp` falls back
to its own Tree-sitter symbol module, which is the same graceful
degradation `my.nvim` performs in the other direction when `ui.nvim` is
absent and it writes the winbar itself. `:checkhealth ui` reports which of
the two you are getting, under "Optional integrations".

## Where a sibling's segment is built

Seven sibling plugins feed segments here, and they split into two shapes.

**The sibling ships the component; this plugin places it.** Six of the
seven, each a ~24-line adapter here:

| Segment | Provided by |
| --- | --- |
| `sandbox_ambient` | `sandbox.statusline` |
| `session_status` | `sessions.statusline` |
| `recommender_badge` | `recommender.statusline` |
| `github_stats_badge` | `github_stats.statusline` |
| `runtime_analysis_ampel` | `runtime-analysis.statusline` |
| `casedesk` | `casedesk.statusline` |

Four of those six used to be built here instead — 494 lines reaching into
`recommender.config`, `github_stats.analytics`, `casedesk.resolve/meta/sla`
and so on, with each plugin's own design decisions restated in this
repository and no test in theirs to hold them. They moved to the plugins
that own the data (cross-feature report, finding E). Each ships a
`docs/statusline.md` covering lualine, heirline and the native statusline
as well, so the component is not ui.nvim-specific.

**This plugin builds it, from a documented API.** One of the seven:

`filetree_cwd_mode` calls `filetree.feature("cwd_mode").badge()` — the
external-statusline API filetree.nvim documents for exactly this, next to
its `component()` sibling. It reaches into nothing internal. What the
remaining lines here do is *this* plugin's own presentation: the bg-filled
capsule, `ui.theme.palette` accents, `get_separators()`, the `St_*`
highlight groups, and the history-dots option, which is a ui.nvim feature
rather than a filetree concept.

That one is deliberately **not** moved. Pushing it into filetree.nvim would
make that plugin depend on this one's palette and separator vocabulary and
emit ui.nvim-specific statusline syntax — coupling in the wrong direction.
The line count made it look like the other four; the call sites do not.

The pattern that beats both, where it applies: `plugin_progress` reads
`lib.nvim.progress`'s shared registry and names no plugin at all, so a new
one needs no change here.

## The kit exists twice, on purpose

`ui.kit` is also present in lib.nvim, as `lib.nvim.ui.kit`. That is not a
leftover: `PLAN-ui-kit-migration.md` step 6 decided it deliberately. Eleven
of lib.nvim's own call sites use the kit — `viewer` for five debug and
report views, `select`, `menu`, `surface` under `progress`'s kit style —
and lib.nvim cannot require `ui.nvim` without inverting the dependency
direction the whole fleet rests on. So both copies stay, and lib.nvim's is
frozen: no new features, only what is here already.

**"Frozen" does not mean "keeps known bugs", and for a while it did.** By
2026-09-17 three fixes and a security note lived only here, while the copy
lib.nvim actually runs still leaked an augroup per popup, left a picker
debounce timer running past its picker, and mis-anchored a submenu near the
bottom of the screen. Nothing compared the two, so nobody noticed for
weeks.

[`TESTS/kit_drift_spec.lua`](../TESTS/kit_drift_spec.lua) compares them
now, on every CI run — this repository already checks lib.nvim out at
`ci-verified` for its other specs — and fails naming the file that differs.

**So: a fix made in `lua/ui/kit/` has to be mirrored into lib.nvim's copy**,
with the rename applied (`ui.kit` → `lib.nvim.ui.kit`, `Ui.Kit` →
`Lib.UI.Kit`). The spec ignores whitespace, because undoing the rename
lengthens lines — `ui.kit.sync` becomes `lib.nvim.ui.kit.sync` — and pushes
one `error()` past the shared 100-column budget, so stylua wraps it on one
side only. Byte-identity is not achievable; identical code is.
