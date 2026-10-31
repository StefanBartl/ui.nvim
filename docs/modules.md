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
| `tasks_counter` | Open tasks of the project in the cwd, read from the wkdbook task vault, e.g. `"T:7"` (`breakdown = true`: `"T:7 P1:2 B:1"`) | a task vault (optional) | `ui.statusline.modules.tasks_counter` |
| `diagnostics_sparkline` | A 20-glyph density row showing WHERE diagnostics sit in the buffer, not just how many | — | `ui.statusline.modules.diagnostics_sparkline` |
| `macro_counter` | Live keystroke count for the macro currently recording, e.g. `"@a · 23"` | — | `ui.statusline.modules.macro_counter` |
| `showcmd` | The pending key sequence (`'showcmd'`), e.g. `"2d"`; takes `'showcmdloc'` only while the key is in the active `order` | — | `ui.statusline.modules.showcmd` |
| `time_in_buffer` | Elapsed time since this buffer was first entered this session, e.g. `"12m"` | — | `ui.statusline.modules.time_in_buffer` |
| `github_stats_badge` | This week's view count for the repo the buffer is in, e.g. `"42 views this week"` — only inside a repo github_stats.nvim tracks | github_stats.nvim | `ui.statusline.modules.github_stats_badge` |
| `runtime_analysis_ampel` | Traffic-light glyph (🟢/🟡/🔴) for whether any runtime-analysis.nvim-instrumented plugin errored or ran slow today | runtime-analysis.nvim | `ui.statusline.modules.runtime_analysis_ampel` |
| `recommender_badge` | Count of recommender.nvim alias suggestions open for the current buffer, e.g. `"3 alias suggestions open for this file"` | recommender.nvim | `ui.statusline.modules.recommender_badge` |
| `session_status` | sessions.nvim's active session name, with a dirty marker (` *`) when the window/buffer layout changed since the last save or load | sessions.nvim | `ui.statusline.modules.session_status` |
| `sandbox_ambient` | sandbox.nvim's ambient container summary, e.g. `"docker (2/5)"` | sandbox.nvim | `ui.statusline.modules.sandbox_ambient` |
| `gitsuite_conflict` | gitsuite.nvim's ambient merge-conflict indicator, e.g. `"MERGE 2"` | gitsuite.nvim | `ui.statusline.modules.gitsuite_conflict` |
| `terminal_count` | terminal.nvim's terminals: the current one with the project's count, e.g. `"build (3)"`, or just the count, e.g. `"2 terminals"` | terminal.nvim | `ui.statusline.modules.terminal_count` |
| `since_last_save` | Duration since the buffer became modified, escalating muted -> `DiagnosticWarn` -> `DiagnosticError` the longer it sits unsaved | — | `ui.statusline.modules.since_last_save` |
| `idle_clock` | Wall-clock time, e.g. `"14:32"`, shown only once the editor has been idle (`CursorHold`) and hidden again on the next keystroke | — | `ui.statusline.modules.idle_clock` |
| `idle_git_log` | The last one to three commits of the buffer's repo, e.g. `"a1b2c3d Fix the parser · 9f8e7d6 Add tests"`, read once per idle phase and shown only while idle; empty outside a repo | git | `ui.statusline.modules.idle_git_log` |
| `breadcrumbs` | Repo-relative path + symbol context, mode-band coloured. The LSP half comes from `my.nvim` when it is installed; Tree-sitter otherwise — see below | my.nvim (soft) | `ui.statusline.modules.breadcrumbs` |
| `idle_breadcrumbs` | `breadcrumbs`, with a wider budget and no fixed path cap while the editor is idle (less shortening of path and symbol chain); identical to `breadcrumbs` otherwise | my.nvim (soft) | `ui.statusline.modules.idle_breadcrumbs` |
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

`tasks_counter` counts the open tasks of the project in the cwd and shows
them as `T:7`. The data is the wkdbook task vault -- one Markdown file per
task under `<area>/ROADMAP/tasks/`, plus a generated `<area>/ROADMAP/TASKS.md`
overview -- read directly as files, so it needs neither the nvim-config task
engine nor any other plugin. Without a vault, or without an area folder for
the cwd, the segment is empty and nothing errors. "Open" means the statuses
`open`, `doing`, `blocked` and `decision` (not `parked`; `statuses` changes
that); with `breakdown = true` it adds `P1:n` (prio 1, yellow) and `B:n`
(blocked, red) when they are non-zero. Where it looks: the vault is
`opts.vault`, else `$TASKS_VAULT`, else
`$REPOS_DIR/tasks-vault`; the area is the folder
name of the git root above the cwd (`areas = { nvim = "nvim-config" }` maps a
folder name to a different area, `area` fixes it or computes it). It never
blocks a redraw: the files are read asynchronously (`vim.uv`), the result is
reused for `ttl_ms` (30 s) and dropped on `DirChanged`; a redraw only reads
that cache, and a saved Markdown file inside the vault refreshes it at once
(`watch_writes`). The source is pluggable (`source = "index"`, `"tasks_dir"`
or a `function(ctx, done)` handing `done({ { status = "open", prio = 1 }, ...
})`); `"tasks_dir"` reads `tasks/*.md` and the folder tasks
`tasks/<slug>/<slug>.md`, understands a quoted value, a trailing `# comment`
and a BOM like the task engine does, and parses each line in linear time (a
file with a huge whitespace run cannot stall the editor). Options:
`require("ui").setup({ tasks = {...} })` or
`require("ui.statusline.modules.tasks_counter.config").setup({...})`; every
option with its default is listed in that file's `DEFAULTS`. Wire it like any
opt-in module: `"tasks_counter"` in `order`, and
`tasks_counter = function() return tasks_counter() end` in `modules`.

`macro_counter` shows `vim.fn.reg_recording()`'s register plus a live
keystroke count while it records — Neovim has no API to read a register's
content mid-recording, so the count comes from a `vim.on_key()` hook
bracketed by `RecordingEnter`/`RecordingLeave`, registered once at first
render.

`showcmd` moves the pending key sequence (`2d`, `"a`, `<C-w>`, ...) from the
last screen line into the statusline. It renders only Neovim's own `%S`
item, inside a `%( %)` group, so it takes no columns while nothing is
pending. `'showcmdloc'` is what makes `%S` non-empty, and it belongs to the
segment only while the key `"showcmd"` is in the active `order`
(`ui.statusline.modules.showcmd.loc`): `render.enable()` sets it to
`"statusline"` for a variant that has the key and hands the earlier value
back for one that does not, `render.disable()` hands it back, and an `order`
edited in place (the menu's "Add module"/"Remove") is picked up on the next
redraw, applied from a `vim.schedule` callback, never mid-redraw. A value
somebody else set in the meantime is left alone. `'showcmd'` itself must be
on (Neovim's default).

- **Global statusline (`laststatus=3`)**: works the same — there is one
  statusline row, and `%S` there shows the keys typed in whichever window is
  current.
- **`:UI zen`**: with its defaults (`hide_statusline`, `hide_ruler`) zen sets
  `laststatus=0` and `showcmd` off, so nothing shows the pending keys while it
  is open — the segment's `'showcmdloc'` stays `"statusline"` and is not
  touched. Closing zen gives both options back and the segment shows keys
  again. `hide_ruler` is the option that turns `showcmd` off; the spec covers
  zen's defaults only.

Both are covered by `TESTS/statusline_showcmd_spec.lua`, which types a real
`2d` into a UI-attached child Neovim and reads the statusline back.

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
Sekunden Inaktivität" names three payloads, and all three are built on it
without their own `CursorHold` wiring:

- `idle_clock` — the time (its own suggested "Uhrzeit").
- `idle_git_log` — the last commits of the repo the buffer is in (the file's
  directory, or the window's cwd for a non-file buffer). No steady load: the
  read is `lib.nvim.git.log_async` (an argv list, no shell), runs at most
  once per repo per idle phase (`idle.phase()`), is cached for the rest of
  that phase and repaints the statusline once when it answers; the first
  idle redraw therefore renders empty. A buffer outside any repo (no `.git`
  upwards) renders empty without starting git. Options:
  `opts.max_count` (1..3, default 3) and `opts.subject_width` (display columns per
  subject, default 32; longer subjects end in `…`). Commit subjects are
  cleaned of control and invisible characters before they are shown.
- `idle_breadcrumbs` — a drop-in replacement for `breadcrumbs` that renders
  the same thing while active and, while idle, gets a wider budget
  (`opts.idle_width_frac` of the statusline's width -- `columns` with
  `laststatus=3`, the window's width otherwise --, default 0.65, never
  narrower than the active budget) and no fixed path cap (`path_max_chars`),
  so a long path and a deep symbol chain are cut less. While idle it starts
  with `%<`: a line that gets too long is cut at the start of the breadcrumb,
  so the mode chip and the other segments before it stay visible. The widening is a per-call override:
  the shared `ui.statusline.modules.lsp.config` and every other segment's
  width logic are untouched. The chain's content stays `my.nvim`'s (see
  [below](#who-owns-the-breadcrumbs-symbol-context)).

Both new ones are opt-in, like every idle payload:

```lua
modules = {
  idle_git_log = function()
    return require("ui.statusline.modules.idle_git_log")({ max_count = 2 })
  end,
  breadcrumbs = require("ui.statusline.modules.idle_breadcrumbs"),
},
```

`session_status`, `sandbox_ambient` and `gitsuite_conflict` are thin
requires, not reimplementations: sessions.nvim, sandbox.nvim and
gitsuite.nvim each already ship a ready-made, statusline-plugin-agnostic
component (`sessions.statusline.component()`, `sandbox.statusline.status()`,
`gitsuite.statusline.status()`) that is cached (rate-limited, for sandbox's;
keyed by `nvim_buf_get_changedtick`, for gitsuite's) on their own side and
documented safe to call on every redraw, so each of these modules is exactly
the wrapper needed to drop it into an `order` list the same way as any other
soft-dependency module here — no separate caching, debouncing or error
handling happens on this side.

`terminal_count` is the other shape: terminal.nvim documents `terminal.summary()`
(`{ count, visible, current }`, read from its registry only, no multiplexer is asked,
safe on every redraw) and this module only words it, from `package.loaded` so it never
pulls terminal.nvim in on the first redraw.

`recommender_badge` calls `recommender.nvim`'s own analyzer directly (the
one its `analyzer` config option already selects — `regex` by default) with
its own `threshold`/`custom_aliases`/`blacklist`, so this always agrees with
what `:Recommender` itself would report; no separate config to keep in
sync. The result is cached per buffer by `nvim_buf_get_changedtick`, so
editing invalidates it but an unrelated redraw does not re-scan the buffer.

`breadcrumbs` is coloured by the current mode band, which takes one extra
piece (a highlight group per mode) -- `ui.statusline.modules.breadcrumbs`
already wires it, so pointing the key at that module is enough:

```lua
modules = {
  breadcrumbs = require("ui.statusline.modules.breadcrumbs"),
},
```

The module is a thin wrapper over `ui.statusline.modules.lsp`
(`mode_band_group()`, `render_breadcrumbs_inherit_lspfirst(band)`,
`hl_open(band)`); copy its few lines if you want a variant of your own.

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
`{ l = fn, r = fn, m = fn, dbl = fn }` for left/right/middle/double-left
click, each `fun(): nil`. `dbl` fires instead of `l` when the native click
protocol reports two or more clicks (Neovim's own `<2-LeftMouse>`
convention); a handler table with no `dbl` entry just runs `l` again, so
double-clicking a module that never opted into the distinction behaves
exactly like clicking it once.

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
| `git_clickable` | `git`, plus a left click switches branches (`gitsuite.features.branch.switch()` when gitsuite.nvim is loaded, a bare `vim.ui.select` over local branches otherwise) and a right click opens a `ui.contextmenu` (switch / copy branch name / details) | gitsigns.nvim for the text; a `git` executable on `$PATH` for the clicks; gitsuite.nvim optionally, for the picker | `ui.statusline.modules.git_clickable` |
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

## Hover tooltip and the "manage this module" menu

Two things every rendered module gets automatically, with nothing to wire up
in `order`/`modules`:

- **Hover.** Rest the mouse on any module and a small float appears after a
  moment, showing that module's `ui.statusline.catalog` `summary` (the same
  English one-liner `:UI modules` prints) — or, for an entry that declares a
  `live` reader (currently just `plugin_progress`) and it returns something,
  that instead: what the module is doing *right now* rather than its static
  description. `summary` is still the fallback once `live` has nothing to
  report (nothing running). The module's own text also recolors for as long
  as it stays hovered — its foreground swapped to a single accent color (an
  amber/orange in most colorschemes, read from `DiagnosticWarn`), background
  and everything else about it left alone. Needs `'mousemoveevent'` (Neovim
  0.10+); degrades to "no hover" silently on an older Neovim, same as
  `ui.kit.chooser`'s own `hover` option. `:UI progress` shows the same
  `live` state as a popup, without needing the mouse over the module at all.
- **Right/double click → manage modules.** Right-clicking (or double-clicking,
  on a plain module) opens a context menu whose heading names the clicked
  module plus a short (catalog-summary-derived) description of what it does,
  then "Remove `<key>`" and an "Add module" fly-out listing every catalogued
  key not currently in `order`, each with its own short description.
  Picking one mutates the *live* `Ui.Statusline.Config` `render.enable()` was
  last given and redraws — runtime-only, exactly like `:UI variant <name>`:
  nothing is written back to your own config, so a restart reverts to
  whatever `order` you actually wrote. A module that already claims left
  click for its own purpose and opens a `vim.ui.select` picker with it
  (`git_clickable`, `variant`) has **no** double-click override onto this
  menu: Neovim's click protocol calls the handler once per physical click,
  so the first click of a double click already fires as an ordinary left
  click before the second one arrives — wiring `dbl` there would have opened
  this menu on top of the picker that first click just opened. Right click
  still reaches it either way (their own branch menu for `git_clickable`,
  this one for `variant`); double click on either module just re-runs left
  click, the same as a plain second click would.
- **Saving the layout.** The same menu's "Layout" group has "Save current
  layout" and "Clear saved layout". Saving writes the live `order` to a small
  JSON file (`ui.statusline.state`, default
  `stdpath("state")/ui.nvim/statusline_order.json`); `render.enable()` reads
  it back and applies it on every start from then on — add/remove changes
  made afterward are still session-only unless you save again. Clearing
  deletes the file, so the next start uses your own `order` again. Like
  `ui.context.state` (the `:UI sticky` persistence this mirrors), a missing,
  unreadable or foreign file is just "nothing saved" — it never raises, and
  `write`/`remove` refuse to touch a file that is not one this module wrote.

Both are implemented once, centrally, not per module: `ui.statusline.render
.generate()` wraps any segment that has no click region of its own in the
generic handler (`ui.statusline.menu`), and separately recolors whichever key
`ui.statusline.hover.current_key()` names on that redraw. A host-written
custom module gets the click-region wrap and the "Add/Remove" menu for free;
it only misses the hover tooltip's *text* if it has no `ui.statusline.catalog`
entry of its own (the recolor still applies).

If you bind your own global `<RightMouse>` dispatcher (the pattern
`ui.tabline.menu.pointer_on_tabline()` documents), have it call
`ui.statusline.menu.pointer_on_statusline()` and step aside when true, the
same way it already should for `pointer_on_tabline()` — otherwise a right
click on the statusline opens both this menu and your own general one, on
top of each other.

---

## Responsive mode

`Ui.Statusline.Config.responsive = true` drops every `order` key NOT tagged
`essential` in the catalog while the statusline's own window
(`vim.g.statusline_winid`) is narrower than `responsive_width` (default 80
columns) — a narrow split falls back to "just the essentials" (`mode`,
`file`, `diagnostics`, `cursor`, and `showcmd` if it is in `order`: it owns
`'showcmdloc'` there, so dropping it would show the pending keys nowhere,
and it takes no columns while idle) instead of either hard-truncating every
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
| `ui.statusline.utils.idle` | `is_idle()` / `wrap(segment_fn)` — makes any segment render nothing until `CursorHold`/`CursorHoldI` (`updatetime` ms with no input), hidden again on the next keystroke or cursor move; `phase()` numbers the idle phases, for a payload that does real work once per phase. `idle_clock`, `idle_git_log` and `idle_breadcrumbs` above are built on it |
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

Eight sibling plugins feed segments here, and they split into two shapes.

**The sibling ships the component; this plugin places it.** Seven of the
eight, each a ~20-24-line adapter here:

| Segment | Provided by |
| --- | --- |
| `sandbox_ambient` | `sandbox.statusline` |
| `session_status` | `sessions.statusline` |
| `recommender_badge` | `recommender.statusline` |
| `github_stats_badge` | `github_stats.statusline` |
| `runtime_analysis_ampel` | `runtime-analysis.statusline` |
| `casedesk` | `casedesk.statusline` |
| `gitsuite_conflict` | `gitsuite.statusline` |

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

## The kit lives in lib.nvim

Since 2026-10-28 the kit is **one** code base: `lib.nvim/lua/lib/nvim/ui/kit/`. Every module of `lua/ui/kit/` here is a
one-line re-export (`return require("lib.nvim.ui.kit.<name>")`), so `require("ui.kit.confirm")` and
`require("lib.nvim.ui.kit.confirm")` are the same table, and there is one theme state. What the earlier layout cost
(every kit change committed twice, a mirror script, a drift spec, two theme states, a fallback chain in the dialog
helper) is gone. A kit fix or feature is made in lib.nvim, with its spec there.

What stays in ui.nvim is the user's surface: the setup (`require("ui").setup`), presets and theme switching, the
`vim.ui` provider, and the kit specs, which now run through `ui.kit` and so also prove the re-exports. A spec that
stubs or reloads a kit module through `package.loaded` has to use the `lib.nvim.ui.kit.<name>` name: that is where
the module lives.

`ui.contextmenu` is still duplicated (lib.nvim keeps a frozen copy for its own call sites);
[`TESTS/contextmenu_drift_spec.lua`](../TESTS/contextmenu_drift_spec.lua) is what remains of the old drift guard.
