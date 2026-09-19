# Health check — ui.nvim

```vim
:checkhealth ui
```

Eight sections. As of roadmap step 6, only one thing in the first is fatal:
`lib.nvim` missing. NvChad's presence is information now, not a dependency
check — steps 3-5 replaced everything this plugin's own code used to read
out of it, one gap at a time, and step 6 did the same for base46.

---

## Dependencies

| Line | Means |
| --- | --- |
| ✅ `lib.nvim is available` | The root module resolves |
| ✅ `all 11 required lib.nvim modules resolve` | Every module this plugin requires by name was found |
| ❌ `lib.nvim is not on the runtimepath` | Fatal — install `StefanBartl/lib.nvim`. Only failure that stops the report |
| ℹ️ `NvChad is present` / `NvChad is not present` | Neither is an error, and this plugin's own code does not need either answer -- it just reports what this particular host looks like. NvChad is not required and (in the reference host this plugin was extracted from, as of step 7, 2026-09-13) not installed at all any more |

`nvconfig`, `nvchad.stl.utils`, `nvchad.tabufline`, `base46` and
`base46.themes` are gone from this section entirely — not reclassified as
soft, removed, because this plugin's own code no longer reads any of them
under any name (steps 3-6).

---

## Configuration

| Line | Means |
| --- | --- |
| ✅ `active colorscheme "x", transparency default false, toggle pair a / b` | `vim.g.colors_name` plus the shipped theme block |
| ℹ️ `statusline variant: x` | Which of the four shipped presets (or a host-registered one) is assembled |
| ✅ `variant module ui.config.statusline.x resolves` | The variant name is a module path at heart; a typo in it degrades to `default` with a notification nobody sees twice |
| ❌ `variant "x" does not resolve` | It will silently fall back to `default`. This line is why the check exists |
| ✅ `ui.config.setup() assembles` | The table this plugin's own `ui.statusline.render` reads was produced, without touching a NvChad or base46 symbol |

---

## Statusline render entrypoint

New at step 4. Checks the module that replaced `nvchad.init` +
`nvchad.stl.utils.generate()`.

| Line | Means |
| --- | --- |
| ✅ `ui.statusline.render resolves` | `generate`/`enable`/`render`/`disable` are all present |
| ✅ `generate() renders the 'default' theme's fallback modules without NvChad` | A synthetic config ran through `generate()` and produced a string, standalone |
| ℹ️ `a config is currently enable()d` | Something called `ui.statusline.render.enable()` — `vim.o.statusline` is this plugin's, not the host's |
| ℹ️ `enable() has not been called` | `vim.o.statusline` is whatever the host last set it to -- this plugin has no way to know what that was from in here |

---

## Tabline render entrypoint

Mirrors the statusline section above, one option later: checks the module
that replaced `nvchad.tabufline`'s render side.

| Line | Means |
| --- | --- |
| ✅ `ui.tabline.render resolves (generate/enable/render/disable)` | All four are present |
| ✅ `generate() renders the shipped tabline config without NvChad` | The shipped tabline config ran through `generate()` and produced a string, standalone |
| ℹ️ `a config is currently enable()d` | Something called `ui.tabline.render.enable()` — `vim.o.tabline` is this plugin's |
| ℹ️ `enable() has not been called` | `vim.o.tabline` is whatever the host last set it to |

---

## Modules

One line per submodule, from `package.loaded` rather than a `require` — a
module left out of `setup()` should report as off, and requiring it here would
load it and make the report a lie.

| Line | Means |
| --- | --- |
| ✅ `keymaps` / `usrcmds` | `setup()` turned it on |
| ℹ️ `… is off` | You did not ask for it. Informational, not a warning |
| ⚠️ `:UI is not registered` | `usrcmds` never ran — `require("ui").setup({ all = true })` |

`keymaps` also covers buffer/tab navigation as of step 5 — `<Tab>`/`<S-Tab>`/
`<leader>bc`/`<leader>tr`/`<leader>tl` all run on
`ui.bindings.keymaps.tabufline.state`'s own `vim.t.bufs` bookkeeping, not
`nvchad.tabufline`. Nothing in this section reports that separately; if
`keymaps` is on, so is buffer/tab navigation.

---

## Statusline segments

Ten soft dependencies, each blanking only its own segment when absent:
`nvim-web-devicons` (file icons), `gitsigns` (the branch name and
added/changed/removed counts, `git`/`git_clickable`), `casedesk.config` (the
case info and SLA badge, `casedesk`), `filetree` (the cwd-mode badge,
`filetree_cwd_mode`), `github_stats.config` (the weekly view-count badge,
`github_stats_badge`), `runtime-analysis.telemetry` (the health ampel,
`runtime_analysis_ampel`), `recommender.config` (the alias-suggestion count,
`recommender_badge`), `sessions.statusline` (the active session name,
`session_status`), `sandbox.statusline` (the ambient container summary,
`sandbox_ambient`) and `lazy` (the own/external plugin count,
`plugin_summary`).

An `ℹ️ not installed` line here is never a problem — it is the report saying
which part of the statusline will be empty and why.

---

## Winbar

| Line | Means |
| --- | --- |
| ✅ `ui.winbar resolves` | A content plugin (my.nvim's `hl_config.breadcrumbs`, or any other) can contribute a winbar line to it instead of writing `vim.wo.winbar` itself |
| ❌ `ui.winbar did not load` | A contributing plugin will fall back to applying directly — not fatal to this plugin, but means the ownership handoff isn't happening |

This section only reports whether `ui.winbar` is *available* — whether
anything is actually contributing to it is `:checkhealth my`'s (or whichever
content plugin's) job to report, the same split as the diagnostics
ownership pattern this mirrors.

---

## Context

| Line | Means |
| --- | --- |
| ✅ `ui.context is on (max_lines N, M scope patterns)` | The sticky code-context overlay is enabled, with its current cap and the number of node-type patterns it treats as scopes |
| ℹ️ `ui.context is off` | The shipped default. `:UI context on` for the session, `ui.setup({ context = true })` for good |
| ✅ `Tree-sitter parser available for the current buffer (ft)` | The overlay can work in this buffer |
| ℹ️ `No Tree-sitter parser for the current buffer` | The overlay needs a parser per filetype; a buffer without one simply shows no context. Not an error — `:checkhealth` itself runs in such a buffer |
| ❌ `ui.context did not load` | The module errored on require; `:UI context` will fail the same way |

---

## Screenkey

`ui.screenkey.setup()` rejects an invalid value (wrong type, or below its
minimum) instead of accepting it and keeps whatever `cfg` already had; this
section surfaces what the last call rejected. That covers the integer
tunables (`width`, `height`, `margin`, `max_entries`, `fade_ms`) as well as
`labels` (a table mapping `keytrans()` names to replacement text, e.g.
`{ ["<Space>"] = "â£" }`; a non-string entry is dropped) and
`join_chars` (a boolean: run plain characters together into one chip per
typed word while `<Esc>`, `<C-…>` and repeat counts stay apart).

| Line | Means |
| --- | --- |
| OK `no rejected config values from the last setup() call` | Every field validated |
| WARN `<field> must be ...` (one per rejected field) | That `setup()` call passed something invalid for `<field>`; the message names what was kept instead |
| ERROR `ui.screenkey did not load` | The module errored on require |

---

## Optional integrations

Which foreign modules this plugin probes, and which of them resolve right
now. The list itself lives in `ui.util.soft_require`'s `PROBED` table.

| Line | Means |
| --- | --- |
| ✅ `N of M optional integrations resolve: …` | Those siblings/plugins are installed; their segments can render |
| ℹ️ `0 of M optional integrations resolve — standalone install` | Nothing optional is installed. Perfectly fine: every segment behind one of them renders empty by design |
| ℹ️ `not installed, and the matching segments render empty: …` | Names each missing module together with what it would have provided |

A miss is never an error — standalone is the ordinary case.

**The check does not load anything.** It resolves each module with
`vim.loader.find`, which finds the file and stops. Using `require` would
have made `:checkhealth ui` load every lazy plugin it asks about —
registering their autocmds, keymaps and commands as a side effect, and
then reporting them all as present because the check had just made them
so. A health report describes the session; it does not change it.

The section exists because the alternative is what actually happened once: the
statusline's Tree-sitter breadcrumb fallback probed
`nvim-treesitter.ts_utils`, nvim-treesitter deleted that module upstream,
and the probe answered "absent" forever. The feature went quiet in every
session with no error anywhere to say so. A probe list you can read is what
makes that kind of rot visible.
