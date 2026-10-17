# Changelog

Behavior changes of ui.nvim that a user or a host config can notice. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the version is not tagged yet.

## [Unreleased]

### Added

- Statusline segment `showcmd` (`ui.statusline.modules.showcmd`, opt-in): the pending key sequence, e.g. `2d`, drawn through Neovim's own `%S` item. While the key is in the active `order`, `'showcmdloc'` is `"statusline"`; a variant switch without it, the menu's "Remove" and `render.disable()` hand the earlier value back. Tagged `essential`, so `responsive` mode keeps it in a narrow window (it takes no columns while idle).

### Fixed

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
