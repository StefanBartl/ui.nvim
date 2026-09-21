# Tests

Headless spec suite for ui.nvim, written against plenary.nvim's
busted-compatible harness (`describe`/`it`, luassert `assert.*`).

## Run

From the repo root:

```sh
scripts/test.sh                    # every spec under TESTS/
scripts/test.sh TESTS/foo_spec.lua # a single spec file
```

That wraps `nvim --clean --headless -u scripts/minimal_init.lua -c
"PlenaryBustedDirectory TESTS/ { minimal_init = 'scripts/minimal_init.lua',
sequential = true }"`. `scripts/minimal_init.lua` needs `lib.nvim` (a hard
runtime dependency — lazy, memo, notify, bindings.\*, debounce, fs.\*) and
`plenary.nvim` (the test harness itself) on the runtimepath; see that file's
own doc comment for the four ways each is found (`$LIB_NVIM_DIR`/
`$PLENARY_DIR`, a `.deps/<name>` checkout, a sibling checkout next to this
repo, or the plugin manager's own `lazy/<name>` directory) — on a machine
that already runs this plugin, no environment variable is needed at all.
CI (`.github/workflows/ci.yml`) checks out `lib.nvim` at its `ci-verified`
ref and `plenary.nvim` at latest into `.deps/`.

The same workflow also runs `stylua --check .` (v2.5.2) and `luacheck .`
(1.2.0, `std = "luajit"`) as two more independent jobs — run those locally
with the same two commands.

## Layout

55 spec files, 717 `it()` cases as of 2026-09-21 (the summary line of
`scripts/test.sh` is the live count). Grouped by area rather than listed
alphabetically, since the file names already say what each one covers:

| Area | Files |
| --- | --- |
| Config / variants / setup | `config_spec.lua`, `variants_spec.lua`, `keymaps_spec.lua` |
| Theme / transparency | `theme_spec.lua`, `theme_picker_spec.lua` |
| Health | `health_spec.lua` |
| Statusline render pipeline | `statusline_render_spec.lua`, `statusline_responsive_spec.lua`, `statusline_highlights_spec.lua`, `statusline_catalog_spec.lua`, `statusline_clickable_spec.lua`, `statusline_hover_menu_spec.lua` (column hit-testing, the `<MouseMove>` tooltip, the right/double-click "manage this module" menu), `primitives_separators_spec.lua`, `cursor_ctl_renderer_spec.lua` |
| Statusline segments | `casedesk_spec.lua`, `diagnostics_sparkline_spec.lua`, `filetree_cwd_mode_history_spec.lua`, `github_stats_badge_spec.lua`, `idle_clock_spec.lua`, `idle_spec.lua`, `lsp_symbols_treesitter_spec.lua`, `macro_counter_spec.lua`, `recommender_badge_spec.lua`, `runtime_analysis_ampel_spec.lua`, `sandbox_ambient_spec.lua`, `session_status_spec.lua`, `since_last_save_spec.lua`, `time_in_buffer_spec.lua`, `undo_depth_search_count_spec.lua` |
| Tabline / tabufline | `tabline_render_spec.lua`, `tabline_styles_spec.lua`, `tabufline_forget_spec.lua`, `tabufline_state_spec.lua`, `tabline_menu_spec.lua` (the per-tab right-click menu, its gating, and the left/right/middle click dispatch), `tabline_layout_drag_spec.lua` (which chip is under a column, and the transient drag mappings) |
| `ui.kit` (floating-window widget toolkit) | `ui_kit_spec.lua` — ~230 assertions ported near-verbatim from the standalone `ui.kit` repo's own suite (`PLAN-ui-kit-migration.md` step 3), covering theme, surface, note, toast, input, prompt, layout, the native chooser + `hover_select` shim, the interactive picker, button-confirm, viewer, form, and live_input through the single `ui.kit` facade |
| Context menu | `contextmenu_spec.lua` — ported the same way from the standalone `ui.contextmenu` repo |
| Sticky context | `context_spec.lua` — a real window over real Lua/Markdown buffers with Neovim's bundled parsers: which scopes are pinned, the heading chain in Markdown and its variants (`markdown.mdx`, registered `rmd`), `headings.max_level` and the per-filetype `max_lines`, the `:UI sticky` command and its completion |
| Sticky context, real grammars | `context_languages_spec.lua` — Go, Java, C#, JavaScript, TypeScript, Kotlin and Bash against their real parsers; each is skipped where the parser is not installed (`:TSInstall go java c_sharp javascript typescript kotlin bash`) |
| Misc widgets | `screenkey_spec.lua`, `winbar_spec.lua` |
| Drift guards | `kit_drift_spec.lua` — `lib.nvim` deliberately kept its own frozen copy of `ui.kit`/`ui.contextmenu` (eleven of `lib.nvim`'s own call sites use it, and `lib.nvim` cannot depend on `ui.nvim` without inverting the fleet's dependency direction); this asserts that frozen copy has not silently drifted from this repo's live version. Skips (rather than fails) when no `lib.nvim` checkout is found beside this repo (`$LIB_NVIM_DIR`, `.deps/lib.nvim`, or a `../lib.nvim` sibling) — runs for real both in CI and locally whenever one of those resolves |
| Source encoding | `source_encoding_spec.lua` — the repository's `lua/`, `TESTS/`, `docs/`, `doc/`, `scripts/` and `README.md` for double-encoded UTF-8: text read as Latin-1 or Windows-1252 and written back as UTF-8, which Lua, stylua and a reviewer all let through. It found the `<Space>` example label of `screenkey_spec.lua` and `docs/health.md` (the open-box glyph U+2423); a second case proves the patterns match built damage and leave clean text alone |
| Regression coverage | `bugfix_regressions_spec.lua` — one `describe` per bug, named for the bug it guards against rather than just the function under test, see below |

## Bugs found and fixed this round (2026-09-18)

Found by code reading + empirical reproduction against the pre-fix code
(a throwaway repro script, run headless), fixed directly, and pinned with a
real regression assertion in `bugfix_regressions_spec.lua`:

1. **`ui.statusline.modules.formatters` measured and cut its display-column
   budget in bytes.** `ellipsize_middle(s, max)` compared `#s` (a byte
   count) against `max` (a *display-column* budget — this plugin's own
   statusline/breadcrumb space) and cut with plain `string.sub` (byte
   offsets). For any multi-byte character — umlauts, CJK, emoji, all
   ordinary in real filenames and LSP symbol names — this either
   under-filled the available space or, worse, sliced a character in half,
   leaving a dangling UTF-8 continuation/lead byte in the rendered
   statusline. Reproduced directly: `ellipsize_middle(("ä"):rep(30), 11)`
   returned a string containing a literal orphaned `0xC3` byte next to the
   ellipsis before the fix. `ellipsize_path_components` and
   `compact_breadcrumb_line` had the same byte-vs-column confusion in their
   own budget arithmetic (though, since path components only ever get cut
   at a `/` boundary, that half of the bug under-filled the budget rather
   than corrupting bytes).

   Fixed by measuring with `lib.lua.strings.width.display_width` (already
   shipped in `lib.nvim` for exactly this) throughout, and rewriting
   `ellipsize_middle`'s cut logic to walk codepoints via
   `lib.lua.strings.utf8.iter` so both the head and tail cuts land on a
   character boundary. `ui.statusline.modules.lsp`'s breadcrumb rendering is
   the real call site (`compact_breadcrumb_line` → `ellipsize_path_components`
   / `ellipsize_middle`), so this was a real, user-visible rendering bug, not
   a theoretical one. See the `bug: ellipsize_middle …` and
   `bug: ellipsize_path_components …` describes in `bugfix_regressions_spec.lua`.

This module had no dedicated spec file before this pass — the only prior
reference to it was an unrelated comment mentioning its `stl_escape`
function in a different bug's regression test. A real, previously
zero-covered coverage gap, closed with 4 new assertions targeted at the
actual defect rather than padding for a number.

## What's covered vs. what's still open

The four recurring bug patterns this campaign checks for on every repo were
looked for specifically:

- **(a) `health.lua` crashing on a missing dependency.** Already fixed
  before this pass (commit `7ebf544`, "the soft-dependency report was
  loading the plugins it reports on") — `ui.health.check_dependencies()`
  uses a pure `pcall(require, mod)` probe for every hard dependency and
  bails out (`return false`) before any later section runs; the whole
  soft-dependency report (`ui.util.soft_require`) resolves presence via
  `vim.loader.find` (existence only), never `require`, specifically so a
  health check cannot be the thing that loads the plugin it is reporting
  on. Every other soft-dependency call site in `lua/**` (`file_icons/
  devicons.lua`, `plugin_summary/init.lua`, `tabline/utils.lua`, `lsp/
  init.lua`, `statusline/utils/primitives.lua`) routes through
  `ui.util.soft_require.try()` and guards the result with `if not X then …`
  before using it. No instance of this pattern found.
- **(b) non-idempotent augroup registration.** Every `autocmd.group(name,
  …)` call site in `lua/**` passes `clear = true` (or, for the one raw
  `vim.api.nvim_create_augroup` call in `ui.kit.theme`, a hand-rolled
  `_colorscheme_hook` guard plus `{ clear = true }`, with a comment
  explaining why the `lib.nvim` wrapper is deliberately not used there).
  Verified empirically, not just by reading: reloaded `ui.statusline.utils.
  idle`, `ui.statusline.modules.since_last_save`, `ui.bindings.keymaps.
  tabufline.state`, and `ui.kit.theme` three times each in one headless
  `nvim` process and counted live autocmds via `nvim_get_autocmds` after
  each reload — counts were stable across all three reloads for every
  module (no growth). This relies on `lib.nvim`'s own `autocmd.group()`/
  `get_augroup()` re-clearing on a cached name when `clear = true` is
  passed again, fixed in `lib.nvim` commit `f3725e8` — confirmed present in
  the sibling checkout this repo's tests run against.
- **(c) byte-offset vs. display-column confusion.** Found and fixed (see
  above). Everywhere else that measures string width for layout —
  `ui.kit.confirm`/`input`/`live_input`/`menu`/`preview`, `ui.screenkey`,
  `ui.tabline.modules`/`utils` — already uses `vim.fn.strdisplaywidth`.
  Highlight/extmark column math in `ui.kit.menu` (`col_start`/`col_end`
  built from `#text`) is correct as-is, not an instance of this bug: Neovim's
  extmark/highlight API is byte-indexed by design, unlike a
  terminal-column budget.
- **(d) Windows path handling.** `ui.statusline.modules.lsp.helpers.paths`
  is this repo's one path-comparison-heavy module (drive detection, home-tilde,
  relative-to-root/cwd). Its `norm_sep()` normalizes separators AND
  upper-cases a Windows drive letter before any comparison
  (`^([A-Za-z]):/ ` → `string.upper(d)`), and both `M.path_absolute()` return
  paths and `home_tilde()`'s own home-directory value are run through it
  before being compared — so a lowercase `c:/...` buffer path and an
  uppercase `C:/...` `os_homedir()` value (or vice versa) still match. No
  instance of a case-sensitive drive comparison found.

Real, previously-zero-coverage code closed this round: `ui.statusline.
modules.formatters` (`ellipsize_middle`, `ellipsize_path_components`,
`compact_breadcrumb_line`'s budget arithmetic) — see above.

## What can't be tested headless

Left honestly out of scope, matching this repo's own existing practice of
not padding for a number:

- **Real floating-window rendering appearance** (border glyphs, colors as
  actually painted to a terminal) — `ui_kit_spec.lua` and the render specs
  verify the *logic* (state machine, buffer/window lifecycle, what text and
  highlight extmarks get produced) exhaustively, headless, but not how a
  real terminal paints the result. Open a picker/confirm/menu/toast in a
  real Neovim session to verify appearance.
- **The nvzone/menu popup actually appearing on RightMouse**
  (`ui.contextmenu`) is UI-only the same way; `contextmenu_spec.lua`
  verifies the menu-building logic, not the popup rendering itself.

## Adding a spec

Match the existing style: a `describe("ui.module.path", function() … end)`
per module (or `describe("bug: <what was broken>", …)` in
`bugfix_regressions_spec.lua` for a regression), `it("does the specific
thing", function() … end)` per case, luassert `assert.*` calls. No file list
to register — `scripts/test.sh`'s `PlenaryBustedDirectory` picks up every
`*_spec.lua` under `TESTS/` automatically.
