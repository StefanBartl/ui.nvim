# Changelog

Behavior changes of ui.nvim that a user or a host config can notice. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the version is not tagged yet.

## [Unreleased]

### Changed

- The kit lives only in lib.nvim: every `ui.kit.*` module is a re-export of `lib.nvim.ui.kit.*` (same table, one theme state). `scripts/mirror_kit.lua` and the kit drift spec are gone; `kit.keys` (viewer keys), the status tokens and the viewer hook moved to lib.nvim. Specs that stub a kit module through `package.loaded` use the lib.nvim name.

- `ui.colorpicker`, `ui.keys`, `ui.menu`, `ui.notify`, `ui.vim_ui` (`enable()`), `ui.windowpicker` and `ui.zen` keep their options in a `lib.lua.config.new` store (`ui.util.config`): an unknown key gets a did-you-mean warning and a value of the wrong type (or out of range) falls back to its default instead of being taken as is; each module has `issues()`, and `:checkhealth ui` lists them under "Module options". `ui.notify` takes level names (`min_level = "warn"`, `timeouts = { error = 8000 }`).

### Fixed

- `ui.colorpicker`, `ui.keys`, `ui.notify`: `setup()` wrote into the live config, so an option (or a `groups` label, a per-level timeout) set by an earlier call stayed after a later call left it out; every call now starts from the defaults. `ui.menu`, `ui.windowpicker`: the tables passed to `setup()` are copied instead of held.
- `kit.confirm`: a question of tens of thousands of characters on one line froze the editor (the hard wrap was quadratic); a question is cut at 4000 characters and wrapped in one pass. A replaced dialog is answered on the next loop turn, so an answer that opens a dialog (a `kit.async` coroutine asking again) no longer closes the replacement before it is shown.
- `kit.ask`: a question behind a dialog that closed without the close event is no longer left waiting (slow re-check); a question withdrawn by `abandoned()` is not answered when its wait runs out; a dialog that cannot be built answers the question as cancelled; letter and digit hotkeys are ignored for half a second after it opens.
- `kit.async.input` / `form` / `submit`: leaving through the caller's own `on_back` resumes the coroutine.
- `kit.prompt`: `choices` as a `vim.fn.confirm` string shows the button dialog.
- `kit.confirm`: a button labelled with a single digit owns that digit key (a `1`..`5` scale after `Skip`/`Stop`: `5` picked the fifth button, not the one labelled `5`). `kit.ask` with `choices` passes the button's position as the second argument, as `kit.confirm` does.

### Added

- `kit.confirm`: every button has a hotkey that picks it at once, marked in the button. `y`/`n` go to Yes/No (also a label that starts with the word, e.g. `Yes, delete`), then the `&` letters, then the first free letter of each label (on a collision the next free letter, earlier buttons first), else the digit (shown as a superscript). New theme token `hotkey` (`KitHotkey`, an underline). The focus still starts on `default`; `<CR>` still confirms it.
- `kit.sidebar` (`ui.kit.sidebar`, re-export of `lib.nvim.ui.kit.sidebar`): a themed split panel on the left, right or bottom -- fixed width/height (`winfixwidth`/`winfixheight`), `winhighlight` from the kit theme, a winbar title, `show`/`hide`/`toggle`, found again by the buffer variable `ui_kit_sidebar`; a newer sidebar at the same position hides the older one and brings it back once when it closes; `close_all()` is the one cleanup.
- `kit.history` (`ui.kit.history`, re-export of `lib.nvim.ui.kit.history`): a back/forward trail of positions with a `CLEAR` sentinel for patches -- `new({ state, keys, max?, dedupe? })`, `go`/`back`/`forward`/`step`/`patch`; pure data, no UI.
- `kit.create_on_missing` (`ui.kit.create_on_missing`, re-export of `lib.nvim.ui.kit.create_on_missing`): the dialog for a path that does not exist -- Create (the file, or for a trailing separator the directory, with its missing parents via `lib.nvim.fs.create_entry`, then `:edit`) / Open in filetree (shows the deepest existing directory; only for a loaded, set-up filetree.nvim or an own `filetree` function) / Cancel; `on_done` gets exactly one result (`created`/`exists`/`filetree`/`cancelled`/`error`).
- `kit.confirm` / `kit.ask` options: `default` (focused button), `choices` as a `vim.fn.confirm` string with `&` hotkeys (plus `y`/`n` for Yes/No and the digits 1-9), `<C-c>` cancels, focus moving elsewhere cancels (`keep_on_focus_lost`; `kit.ask` keeps by default), `kind = danger|warn|info`, `legend = true`.
- `kit.async`: `run`, `await`, `confirm`, `ask`, `input`, `form`, `select`, `submit` -- coroutines over the callback components, so a flow of several questions reads as straight code and the editor keeps running while it waits. `kit.sync` is deprecated: it waits in `vim.wait()`, Neovim does not run typed keys during it, and the dialog returned after its timeout (ten minutes by default) without ever seeing them. It warns once per session.
- Statusline segment `showcmd` (`ui.statusline.modules.showcmd`, opt-in): the pending key sequence, e.g. `2d`, drawn through Neovim's own `%S` item. While the key is in the active `order`, `'showcmdloc'` is `"statusline"`; a variant switch without it, the menu's "Remove" and `render.disable()` hand the earlier value back. Tagged `essential`, so `responsive` mode keeps it in a narrow window (it takes no columns while idle).
- Statusline segment `idle_git_log` (`ui.statusline.modules.idle_git_log`, opt-in): the last one to three commits of the buffer's repo, shown only while the editor is idle (`CursorHold`). Options `max_count` (1..3) and `subject_width` (display columns per subject). git runs at most once per repo and idle phase, asynchronously through `lib.nvim.git.log_async` (argv, no shell, no lazy fetch in a partial clone); a buffer outside any repo starts no process.
- Statusline segment `idle_breadcrumbs` (`ui.statusline.modules.idle_breadcrumbs`, opt-in): a drop-in for `breadcrumbs` that, while idle, gets a wider budget (`idle_width_frac`, default 0.65 of the statusline's width) and no fixed path cap. An overlong line is cut at the breadcrumb, never at the mode chip.
- `ui.statusline.utils.idle.phase()`: a counter of active -> idle transitions, the cache key for "once per idle phase". `idle.wrap(fn)` now passes its arguments (e.g. `opts`) on to `fn`.

### Fixed

- `kit.confirm` answers exactly once whichever way it ends: closed from outside, replaced by another dialog, `close()`; a waiting `kit.ask` no longer hangs on it. The answer of an externally closed float is delivered on the next loop turn, so an error in the handler is reported.
- `kit.confirm`: a long question is wrapped, many or wide buttons are packed into several rows and a label wider than the window is cut, so the buttons stay in the visible window (a 200 character question left the first button at column 95 of a 76 column window).
- `kit.ask` waits for every modal kit dialog (input, select, picker, sheet, compare), not only a confirm, and no longer polls; it takes the options of `kit.confirm` (`choices`).
- `kit.picker` drops its per-instance `lib_kit_picker_<winid>` augroup when it closes, on every close path; before, one empty group stayed behind for each picker opened.

### Changed

- `:UI variant`, `:UI tabline-style` and `:UI kit-preset` without a name open a choice (`ui.kit.select`, or the installed `vim.ui.select` override) with the current value marked and preselected; a pick switches, a cancel changes nothing, an error while switching is reported like the named form's. `:UI tabline-style` reports an error instead while the tabline is not enabled (no pick could switch it). Before, they only printed the current value and a "Use :UI ... <name> to switch" hint. With a name they switch as before.
- `:UI` and `:Theme` are lib.nvim composer verbs (`834591a`): one route per subcommand, `<Tab>` completion as before, and the option float (cheatsheet key set in the composer's `help.keymap`, no default; a bare `:UI`).
  - `:Theme a b` is no longer refused for the second word; the handler takes the first word and ignores the rest.
  - A bare `:UI` opens the option float instead of printing the help text.
  - `:UI help` prints a help text generated from the routes (rows and texts of the float); the hand-kept box is gone.
  - The argument types `UI_THEME`, `UI_VARIANT`, `UI_TABLINE_STYLE`, `UI_KIT_PRESET`, `UI_SLOT_WORD` and `UI_STICKY_WORD` are registered by `setup()` of `ui.bindings.usrcmds`, not as a side effect of `require`.
  - The argument tables of the routes are built per route (the two sticky routes and the on/off toggles no longer share tables).
- A kit surface opened with an explicit `enter = true` that is not modifiable ends Insert mode (`e23b4cd`): `kit.viewer`, `kit.chooser`/`kit.select`, `kit.confirm`, `kit.message_log` and the side-by-side view of `kit.compare`, opened from an Insert-mode mapping, now stand in Normal mode, so `q`/`<Esc>` close them on the first press. A modifiable surface and one opened with the default `enter` keep the mode.
- The `kit.picker` prompt resumes Insert mode, at the column it had, when the focus comes back from a window a caller key opened (`e23b4cd`). A window that is typed into and closes from Insert mode (a `kit.input`, a nested `kit.picker`) counts too: the prompt resumes once that window's Insert mode is over, ahead of any key typed after it. A prompt left from Normal mode stays in Normal mode.
