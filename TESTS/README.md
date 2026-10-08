# Tests

Headless spec suite for ui.nvim, written in the busted style
(`describe`/`it`, luassert `assert.*`) and run by
[testing.nvim](https://github.com/StefanBartl/testing.nvim).

## Run

From the repo root:

```sh
scripts/test.sh                    # every spec under TESTS/
scripts/test.sh --file config      # only spec files whose name contains "config"
scripts/test.sh --json ir.json     # also write the machine-readable result
```

`scripts/test.sh` hands everything after its name to `testing run .`
(`nvim -n -i NONE --headless -u NONE -l <testing.nvim>/scripts/testing.lua`),
configured by `.testing.lua`: one child Neovim per spec file, the same
isolation the old runner gave. `TESTS/minimal_init.lua` runs in every child
and puts this repo and its dependencies on the runtimepath. `testing.nvim`
(the runner) and `lib.nvim` (a hard runtime dependency — lazy, memo, notify,
bindings.\*, debounce, fs.\*) are each looked up in four places: `$TESTING_NVIM_DIR`/
`$LIB_NVIM_DIR`, a `.deps/<name>` checkout, a sibling checkout next to this
repo, or the plugin manager's own `lazy/<name>` directory — on a machine that
already runs this plugin, no environment variable is needed at all. A
dependency that is not found is an error naming all four places, exit code 1.
CI (`.github/workflows/ci.yml`) checks out `testing.nvim` and `lib.nvim` at
their `ci-verified` ref into `.deps/` and uploads the JSON result as an
artifact when the tests fail.

The same workflow also runs `stylua --check .` (v2.5.2) and `luacheck .`
(1.2.0, `std = "luajit"`) as two more independent jobs — run those locally
with the same two commands.

## Layout

60 spec files, ~800 `it()` cases as of 2026-09-21 (the summary line of
`scripts/test.sh` is the live count). Grouped by area rather than listed
alphabetically, since the file names already say what each one covers:

| Area | Files |
| --- | --- |
| Config / variants / setup | `config_spec.lua`, `variants_spec.lua`, `keymaps_spec.lua` |
| Theme / transparency | `theme_spec.lua`, `theme_picker_spec.lua` |
| Health | `health_spec.lua` |
| Statusline render pipeline | `statusline_render_spec.lua`, `statusline_responsive_spec.lua`, `statusline_highlights_spec.lua`, `statusline_catalog_spec.lua`, `statusline_clickable_spec.lua`, `statusline_hover_menu_spec.lua` (column hit-testing, the `<MouseMove>` tooltip, the right/double-click "manage this module" menu), `primitives_separators_spec.lua`, `cursor_ctl_renderer_spec.lua`, `cursor_ctl_spec.lua` (`get_mode`/`set_mode`/`toggle_mode`, and that a direct assignment to `mode` can no longer bypass the whitelist -- the PRIN-10 fix) |
| Statusline segments | `casedesk_spec.lua`, `diagnostics_sparkline_spec.lua`, `filetree_cwd_mode_history_spec.lua`, `github_stats_badge_spec.lua`, `idle_clock_spec.lua`, `idle_spec.lua`, `lsp_symbols_treesitter_spec.lua`, `macro_counter_spec.lua`, `recommender_badge_spec.lua`, `runtime_analysis_ampel_spec.lua`, `sandbox_ambient_spec.lua`, `session_status_spec.lua`, `since_last_save_spec.lua`, `time_in_buffer_spec.lua`, `undo_depth_search_count_spec.lua`, `matchup_offscreen_spec.lua` (vim-matchup's own `w:matchup_statusline`, read back as one segment instead of `method = "status"` overwriting `&l:statusline`) |
| Tabline / tabufline | `tabline_render_spec.lua`, `tabline_styles_spec.lua`, `tabufline_forget_spec.lua`, `tabufline_state_spec.lua`, `tabline_menu_spec.lua` (the per-tab right-click menu, its gating, and the left/right/middle click dispatch), `tabline_layout_drag_spec.lua` (which chip is under a column, and the transient drag mappings), `tabline_pins_spec.lua` (pins as drawn: a pinned chip is never dropped under overflow, and the click guard refuses to close one; the `vim.t.bufs` mechanics are `tabufline_state_spec.lua`'s), `tabline_reopen_spec.lua` (the closed-tab ring, driven through `record`/`reopen` directly rather than the `BufDelete` autocmd), `tabline_scroll_spec.lua` (the auto-scroll offset a drag arms at either edge, and what `modules.buffers()` does with it) |
| `ui.kit` (floating-window widget toolkit) | `ui_kit_spec.lua` — ~230 assertions ported near-verbatim from the standalone `ui.kit` repo's own suite (`PLAN-ui-kit-migration.md` step 3), covering theme, surface, note, toast, input, prompt, layout, the native chooser + `hover_select` shim, the interactive picker, button-confirm, viewer, form, and live_input through the single `ui.kit` facade; also form back navigation (`back = true`, `ui.kit.input`'s `on_back`/`buttons`) driven from Normal mode with `getmousepos()` stubbed for clicks (and `vim.uv.hrtime` for the held-`<BS>` guard), the button row kept one line under the field and in view, the shared `ui.kit.buttons` helper, and `kit.confirm`'s click/focus behaviour pinned across its move onto that helper |
| `ui.kit` form back navigation, real UI | `ui_kit_form_back_ui_spec.lua` — the same feature in a child Neovim started with `--embed` and a UI attached (RPC: `nvim_input`, `nvim_input_mouse`), because this runner never enters Insert mode and cannot produce a real click: every field of a chain opens in Insert mode (forward, back, and after the last one Insert mode is left), `<BS>` deletes until the field is empty and only then goes back (a held one stops at the empty field instead of deleting the earlier answers too), `<Down>` + `<CR>`/`<Tab>` drive the button row, a real mouse click on `[ ← Back ]` lands on the button (the bordered float's `getmousepos()` rows, which a stub cannot fake), a long answer that scrolls the field sideways keeps the row drawn in view and clickable where it is drawn, a paste with a newline stays one line with the row under it, and a field split by a linewise register or `<C-j>` leaves the button row whole when the focus moves onto it (the prompt's buffer has no auto-indent: `stopinsert` used to delete the space under the parked cursor). The child gets its runtimepath over RPC (a path with a space or a comma does not survive `--cmd "set rtp^="`) |
| `ui.kit.input`, real UI | `ui_kit_input_ui_spec.lua` — the single prompt in a child Neovim with a UI attached, for what the headless runner (no Insert mode, `complete()` and `getcompletion()` stubbed) cannot show: `<Tab>` really opening the completion popup and completing from it (the mapping used to be an `<expr>` one, under whose textlock `complete()` raises E565 and the `pcall` around it hid that), and a pasted backtick span never reaching the shell through `getcompletion()`. Also which mode the window a callback opens is in: a sheet, a picker, a live_input, a compare or the last field of a form opened from an `on_submit` is typed into (the closing prompt's `stopinsert` used to strand it in Normal mode), a chooser or nothing leaves Normal mode, and a modifiable float the focus goes back to keeps the mode it had. The child is started without a Git-for-Windows `$SHELL` so that a command line really runs there. And a secret prompt (or a sheet with a secret field) in front of a popup: no word of the buffer is offered by `<C-n>`/`<C-p>`/`<C-x><C-n>`/`<C-x><C-p>`, with `'autocomplete'` on or off (a plain prompt does, as the control), while the popup of its own `completion` is cycled with `<C-n>`/`<C-p>` and what it puts in is masked at once |
| `ui.kit` path completion in a big directory | `ui_kit_path_completion_spec.lua` — with `getcompletion()` stubbed (which is what tells the two paths apart): a `"file"`/`"dir"` fragment that more than 300 entries start with (the files among them count for `"dir"`) gets its candidates from one directory listing -- no `getcompletion()`, no `stat`, sorted like it, cut to 300, directories with their slash, dot files only when asked for by name, `"dir"` keeping only directories and answering from the listing alone however few directories hide among the files, or none (an empty list opens no popup) -- while a fragment with few candidates, a pattern, a fragment with a NUL byte (which must not raise E976 out of the mapping), another completion type and a directory that cannot be listed are `getcompletion()`'s as before; with a listing that gives no entry types (a link, a junction) a `stat` is asked once per entry until the menu is full, for `"dir"` at most once per entry of the directory with `getcompletion()` not asked afterwards, and never for a fragment with too few candidates, a directory of unknown type keeps its slash and an entry that cannot be stat'ed (a broken link, stubbed and a real one) is left out as `getcompletion()` leaves it, below the limit and above it; and the list has to be the one the real `getcompletion()` makes (taken before the stub): the same entries in the same order under every combination of `'fileignorecase'` and `'wildignorecase'` (case-blind matching, the characters between the capitals and the small letters, mixed-case names) and for non-ASCII names, with names that fold alike ordered by spelling, not by the order of the listing; where a non-ASCII character is involved Neovim's own folding decides what matches (a dotless i is no "I", the Kelvin sign is a "k"; the regex is anchored -- a name that merely holds the fragment is no match --, literal -- a dot in the fragment is a dot, not "any character" -- and case-exact where Neovim keeps the case, each pinned so that dropping the `^`, the `\V` or the `\C` fails a case), a combining mark after the fragment is not a prefix match, and a name with a combining mark is ordered by its base characters like `getcompletion()` does (`pathcmp()` skips the mark) without sending the list back to it: one such name among many (only that name is taken apart, and a directory of Cyrillic names with no mark at all is asked about marks once, for the whole set, and splits none -- both counted through `vim.fn.split` and `vim.fn.strchars`, since the result is the same either way), a Thai, Devanagari or Arabic directory where half the names carry marks, and Hangul jamo, ZWJ sequences and flags, and a mark behind a format character (a right-to-left mark, a zero-width space), which Neovim's character count keeps as a character of its own where `split()` folds it away; a mark right behind the separator of a path with a directory part belongs to the separator (the name sorts as if it had none), while the same mark at the start of a name of the working directory is a character of its own; a crowd of plain names with five marked ones right behind the fragment (only Neovim's regex keeps those out on Linux and macOS), a matcher that cannot be built (`getcompletion()` answers), and files with marks left out of the list for `"dir"` without being asked about a mark; a fragment that ends inside a character (a line that is not valid UTF-8) is judged by Neovim's regex, not by the bytes (that case differs from the bytes on Linux and macOS only: on Windows the regex always decides), and so is a name written in another encoding than the fragment -- a lone Latin-1 byte and the UTF-8 spelling of the same character match each other for Neovim, and so for the list, checked by what it holds because the order of the two spellings is the bytes' (only on a file system that keeps names that are not valid UTF-8: Linux) (those cases self-skip on a file system that normalizes names) |
| `ui.kit` sort keys of the big-directory list | `ui_kit_marks_order_spec.lua` — `order_by_base_characters`: the keys of names with the common combining marks (U+0300..U+036F) made by patterns are the keys the `split()` version made (rebuilt in the spec) for thousands of names of every kind (umlauts NFC/NFD, Cyrillic, CJK, marks at the edges of the block, several in a row, invalid UTF-8, control characters), the order is `getcompletion()`'s for real files, and it is at least twice as fast as the split. |
| `ui.kit` secret mask | `ui_kit_conceal_spec.lua` — `input.conceal_line`, the mask over a secret's characters (shared by `kit.input` and `kit.sheet`): one mark per character with a base and its combining marks as one, the same marks the old `byteidx()` walk set for any valid text (a deterministic jumble of combining marks, ZWJ sequences and flags compared against it), every byte of text that is not valid UTF-8 still under a mark, and time in proportion to the line instead of its square (30 000 characters took the old walk about nine seconds); a NUL byte in a secret (a paste, `<C-v>000`, a `default`) is masked like any other character -- it used to raise E976 out of the `TextChanged` handler after the marks were cleared and leave the whole secret on screen -- and a title with one still opens a prompt; a `mask` that is not a string (a number, `true`, a table) is the default `*`, from the start and while typing, instead of raising out of `open()` (a prompt with a default) or out of the `TextChanged` handler after the marks were cleared (the secret on screen), while a string the caller chose, an empty one included, is used as it is; a `mask` nvim cannot show (a newline, NUL, tab, escape, an invisible character) is the default `*`, from the start and while typing, instead of raising out of the `TextChanged` handler after the marks were cleared. |
| `ui.kit` the buffer a secret is typed into | `ui_kit_secret_buffer_spec.lua` — what shuts the doors the mask does not cover: a secret prompt and a sheet with a secret field mark their buffer (`ui.kit.surface.SECRET_VAR`, read by `ui.screenkey`; one secret row marks the whole sheet; the question never raises); `<C-n>`, `<C-p>`, `<C-x><C-n>` and `<C-x><C-p>` insert nothing into a secret prompt or a sheet with a secret field (real keys through `nvim_feedkeys`, each with a control that a plain prompt does complete: a runner that cannot show the leak must not pass), the popup of the prompt's own `completion` keeps `<C-n>`/`<C-p>` (`pumvisible()` and the feed stubbed) and `on_back`'s `<C-p>` still goes back, `<C-x>` is a `<Nop>`, `'autocomplete'` is off for the buffer whatever the global value is; the mask is applied again after `TextChangedP`; the re-mask hook is buffer-local, in no group, and leaves no group (`lib_kit_input_<bufnr>`) and no autocmd record behind. The popup itself is `ui_kit_input_ui_spec.lua`'s |
| `ui.kit` prompt hooks | `ui_kit_prompt_hooks_spec.lua` — two `kit.live_input` prompts (and two `kit.compare` pickers) open at once each call their own `on_change` (their own query): the hooks hung under one group name that every new prompt cleared, so the first one's were gone; a compare that marks its first pick has the hook on the new prompt buffer; no autocmd record is left |
| `ui.kit.chooser` title | `ui_kit_printable_title_spec.lua` — `chooser.set_items` spells out the control characters of a title (ESC, BEL, TAB, DEL) instead of drawing them raw, where the terminal would act on them; the canonical chooser took this over from `lib.nvim`'s frozen copy (863952e), which the drift check had caught |
| `ui.kit` one-line text | `ui_kit_oneline_spec.lua` — a prompt's `default` (also a `kit.form` field's, or a number) and a button's label (`kit.input`, `kit.confirm`, `kit.sheet`) with a newline in them used to raise in `nvim_buf_set_lines` and leave the scratch buffer behind; they are flattened to one line now, the answer `kit.confirm` hands back staying the caller's own string, and no buffer is left over |
| `ui.kit` NUL byte in caller text | `ui_kit_nul_spec.lua` — a NUL in text a component measures (a `kit.select` item or a `kit.viewer`/`kit.note` line, a `kit.confirm` question or button, a `kit.live_input` title, a `kit.input` or `kit.sheet` button, a `kit.sheet` title, label and validation message, a `kit.menu` label or title, a `kit.toast` message, a `kit.chip` text) raised E976 out of `strdisplaywidth()`/`split()` and kept the component from opening; it is measured as the SOH that `lib.lua.strings.core.nul_safe` swaps it for (two cells, like the `^@` it is drawn as), widths are compared with the same text written with two plain letters, the sheet's label is read back through its `'statuscolumn'`, and what `kit.confirm` answers stays the caller's own string. `kit.preview`'s gallery measures only its own literals and is not covered |
| `ui.kit` secrets in the last Insert run | `ui_kit_secret_traces_spec.lua` — a prompt with `secret = true` (and a sheet with a secret field) scrubs the `.` register and the redo buffer when it closes: the helper itself (an empty run in a scratch buffer: `.` holds nothing and replays nothing, no buffer or hook is left), and that submit, cancel, back, a close from outside and a raising callback all call it while a prompt or sheet without a secret does not. The whole path in a real Neovim is in `ui_kit_input_ui_spec.lua` (a chain that begins with a secret prompt included: the scrub waits for the `InsertLeave` that ends the run) and `ui_kit_sheet_ui_spec.lua` |
| `ui.kit` Insert mode across a chain | `ui_kit_insert_chain_spec.lua` — the decision a closing prompt takes, with `:stopinsert` counted (this runner never enters Insert mode; the modes themselves are `ui_kit_input_ui_spec.lua`'s): it is not called when the callback opened another window to type into (a prompt, a sheet, a picker, a live_input, a compare, the sheet after a form's last field -- each counts itself with `input.mark_opened()`), it is when the callback opened a chooser or nothing, and a sheet closing over a modifiable float that was there before stops Insert mode instead of taking that float for the next prompt |
| `ui.kit` floats are `winfixbuf` | `ui_kit_winfixbuf_spec.lua` — a float opened by `surface.open` has `winfixbuf` (unless the caller turns it off), so `<C-o>`/`<C-^>` from the jumplist every new float inherits cannot swap the user's file into a sheet's select row, a prompt's button row or a confirm dialog and wipe the component's buffer from under it (E1513 instead; each component still answers `<Esc>` afterwards), and a prompt whose buffer was swapped by force through the API still answers when its window closes |
| `ui.kit.sheet` | `ui_kit_sheet_spec.lua` — the one-float form driven from Normal mode (every key is mapped for `i` and `n`; typing is a buffer write plus the `TextChanged` it would fire, a click is the `<LeftMouse>` mapping with `getmousepos()` stubbed): layout (values only in the buffer, the button row, the labels left to the window's `'statuscolumn'`), the Tab/Down/`<CR>`/`<Esc>` navigation, the button row, a select field (cycling, `kit.select`, a pick moving on), text fields (default, `expand_env`, secret mask, completion `<Tab>`, a paste with a newline, a deleted row), and validation (blank required, the forms `validate` may answer in, a raising validator, checking on leave / on edit / `live`, the message lines and the window growing by them, submit blocked and the focus jumping to the first invalid field) |
| `ui.kit.sheet`, real UI | `ui_kit_sheet_ui_spec.lua` — the same component in a child Neovim with a UI attached, for what a stub cannot show: the label column on screen and the cursor right of it, which mode each row opens in, the red message under a field and the window growing by its row, a secret never on screen, a real click on a row and on `[ Submit ]`/`[ Cancel ]` (a refused click on `[ Submit ]` leaves the first bad field in Insert mode: its `startinsert` was ignored while the click's own `stopinsert` was still pending), a long value wrapping under the value column with the buttons still on screen and clickable, and Insert mode left after the last submit |
| `ui.kit` keymap records | `ui_kit_keymap_records_spec.lua` — every popup component (chooser, confirm, menu, shortlist, picker, compare) is opened and closed repeatedly and `lib.nvim`'s keymap records must not grow: their buffer-local keys are throwaway and pass `record = false`; a control first proves the counter sees a recorded key |
| `ui.kit` autocmd records | `ui_kit_autocmd_records_spec.lua` — the twin of the keymap one for the popups' autocmd hooks (per-window groups): surface, chooser, confirm, menu, shortlist, picker, compare, a secret `kit.input` (its re-mask hook was in a group of its own per prompt) and `kit.live_input` are opened and closed repeatedly and `lib.nvim`'s autocmd records must not grow; a control first proves the counter sees a recorded autocmd and that `record = false` still creates a live one |
| `ui.kit.shortlist`'s preview pane | `ui_kit_shortlist_preview_spec.lua` — the keys are driven through `nvim_feedkeys`, so the mappings themselves are tested: scrolling the preview from the list (`<C-f>`/`<C-p>`, the aliases, half pages), hopping focus (`<Tab>`, the window-cycle keys staying inside the popup), `<CR>` at the cursor line, `q`/`<Esc>` from inside, closing when focus leaves, the read-only preview (yank works, edits do not), the footers and the lit border, `preview_keys` / `hints` / `close_on_leave` (including a bare string as a key list and entries that are not keys), and a preview whose `render` raises (the pane says so instead of keeping the previous item's text, and stays read-only because `Surface:set_lines` puts `modifiable` back) |
| Context menu | `contextmenu_spec.lua` — ported the same way from the standalone `ui.contextmenu` repo |
| Right-click menu | `menu_spec.lua` — `ui.menu`: the default sections and the switches over them, the three opt-out layers for sister-plugin contributions (fake modules through `package.preload`), the user's `extra` rows (plugin/ft/when gates, grouping, `cmd`/`keys`), Copy/Delete Marked acting on the selection after Visual mode has ended, the trigger bindings, and the `<RightMouse>` handler's three cases |
| Sticky context | `context_spec.lua` — a real window over real Lua/Markdown buffers with Neovim's bundled parsers: which scopes are pinned, the heading chain in Markdown and its variants (`markdown.mdx`, registered `rmd`), `headings.max_level` and the per-filetype `max_lines`, the `:UI sticky` command and its completion |
| Sticky context, real grammars | `context_languages_spec.lua` — Go, Java, C#, JavaScript, TypeScript, Kotlin and Bash against their real parsers; each is skipped where the parser is not installed (`:TSInstall go java c_sharp javascript typescript kotlin bash`) |
| Misc widgets | `screenkey_spec.lua` (also: keys typed into a secret `kit.input` prompt or a sheet with a secret field never reach the HUD, the closing key included, nor does the scrub of the last Insert run that follows -- each with a plain prompt or sheet as the control), `winbar_spec.lua`, `zen_spec.lua` (the distraction-free float, the hidden frame, and the restore on every way out), `colorpicker_spec.lua` (the colour arithmetic, and the picker float driven through its own window cursor), `notify_spec.lua` (the `vim.notify` seam, the toasts it opens, the history), `keys_spec.lua` (the mappings under a prefix, as a tree and as a menu) |
| Window picker | `windowpicker_spec.lua` (filtering, autoselect, the hint overlay, picking and cancelling via a real fed keypress), `window_picker_shim_spec.lua` (the `window-picker` compatibility shim that consumers such as neo-tree's `open_with_window_picker` resolve to, delegating to `ui.windowpicker`) |
| Drift guards | `kit_drift_spec.lua` — `lib.nvim` deliberately kept its own frozen copy of `ui.kit`/`ui.contextmenu` (eleven of `lib.nvim`'s own call sites use it, and `lib.nvim` cannot depend on `ui.nvim` without inverting the fleet's dependency direction); this asserts that frozen copy has not silently drifted from this repo's live version. Skips (rather than fails) when no `lib.nvim` checkout is found beside this repo (`$LIB_NVIM_DIR`, `.deps/lib.nvim`, or a `../lib.nvim` sibling) — runs for real both in CI and locally whenever one of those resolves. `scripts/mirror_kit.lua` ports a kit change into that copy with this spec's rename rules (see `docs/modules.md`, "The kit exists twice, on purpose") |
| Source encoding | `source_encoding_spec.lua` — the repository's `lua/`, `TESTS/`, `docs/`, `doc/`, `scripts/` and `README.md` for double-encoded UTF-8: text read as Latin-1 or Windows-1252 and written back as UTF-8, which Lua, stylua and a reviewer all let through. It found the `<Space>` example label of `screenkey_spec.lua` and `docs/health.md` (the open-box glyph U+2423); a second case proves the patterns match built damage and leave clean text alone |
| Regression coverage | `bugfix_regressions_spec.lua` — one `describe` per bug, named for the bug it guards against rather than just the function under test, see below |
| lsp.nvim's internal client | `lsp_internal_client_spec.lua` — `ui.util.lsp.is_internal_client` and the two call sites that used to treat lsp.nvim's own in-process clients (`lsp.nvim-gitsigns`, attached to every gitsigns-tracked buffer regardless of language) as a real language server: the statusline's LSP label (`ui.statusline.utils.primitives.lsp`) and the file-icon-when-attached segment (`ui.statusline.modules.file_icons.devicons.file_icon_segment_lsp`) |

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
to register — `testing run` picks up every `*_spec.lua` under `TESTS/` automatically.
