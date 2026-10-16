# Changelog

Behavior changes of ui.nvim that a user or a host config can notice. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); the version is not tagged yet.

## [Unreleased]

### Changed

- `:UI` and `:Theme` are lib.nvim composer verbs (`834591a`): one route per subcommand, `<Tab>` completion as before, and the option float (cheatsheet key set in the composer's `help.keymap`, no default; a bare `:UI`).
  - `:Theme a b` is no longer refused for the second word; the handler takes the first word and ignores the rest.
  - A bare `:UI` opens the option float instead of printing the help text.
  - `:UI help` prints a help text generated from the routes (rows and texts of the float); the hand-kept box is gone.
  - The argument types `UI_THEME`, `UI_VARIANT`, `UI_TABLINE_STYLE`, `UI_KIT_PRESET`, `UI_SLOT_WORD` and `UI_STICKY_WORD` are registered by `setup()` of `ui.bindings.usrcmds`, not as a side effect of `require`.
  - The argument tables of the routes are built per route (the two sticky routes and the on/off toggles no longer share tables).
