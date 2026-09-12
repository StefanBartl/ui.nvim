# Theme switching

`:UI theme`, `:UI toggle`, `:UI transparency` are plain Neovim now. This note
exists because the previous implementation was not, and the difference is
worth knowing if you ever touch this module again.

## What this used to require, and why it doesn't any more

Until step 6 of `ROADMAP.md`, this plugin depended on NvChad's `base46` for
theme switching. Base46 themes are **not** colorschemes — they are Lua data
tables (`base46/themes/<name>.lua`) that `base46.load_all_highlights()`
compiles into highlight groups at runtime, for every plugin `chadrc.hl_override`
knows about. `vim.cmd.colorscheme(name)` does nothing for a base46 theme:
there is no `colors/<name>.lua` file to load. Switching one meant: mutate
`chadrc`'s in-memory table, reload the `chadrc` module so base46 would see the
change, call `base46.load_all_highlights()` to recompile everything, and
hand-edit `chadrc.lua` on disk with a string replace so the choice survived a
restart — four steps, three of which only exist because base46 does not use
Neovim's own colorscheme mechanism.

None of that exists any more, because base46 doesn't. `M.load_theme(name)` in
`init.lua` is `pcall(vim.cmd.colorscheme, name)` — one line, the way theme
switching normally works in Neovim.

## What changed in what `:UI theme` can target

`M.list_themes()` used to return a fixed NvChad theme list (a hardcoded
fallback of roughly fifty names, or `base46.themes`' own key list). It now
returns `vim.fn.getcompletion("", "color")` — every colorscheme Neovim can
see, built-in or installed via any plugin manager. This is strictly more:
anything the old list could name, plus every other colorscheme the host has
installed, none of it hardcoded here.

## What is deliberately gone: persistence across restarts

The old `persist_theme()` rewrote `chadrc.lua` by finding a
`theme = "..."` line with a Lua pattern and substituting it — fragile (a
malformed or reformatted `chadrc.lua` silently fails to persist) and,
more importantly, out of scope for a UI-frame plugin to be doing at all.
Choosing a colorscheme at startup is the host's own config's job, the same
way it is for any Neovim setup: put `vim.cmd.colorscheme("name")` in your
`init.lua` once you know what you want. `:UI theme` changes the running
session; it does not, and should not, edit files on disk on your behalf.

## Transparency

`ui.theme.transparency` strips `bg` from the groups this plugin's own frame
draws (`Normal`, statusline, tabline, winbar — see that module for the exact
list) and restores the saved value on toggle-off. It is **not** full-UI
transparency: floating windows, popup menus, and other plugins' own chrome
keep whatever background their own highlighting sets. That was base46's job
(recompiling hundreds of groups per theme); doing the same here would make
this plugin a second copy of highlighting that belongs to whichever plugin
owns the float in question.

It re-applies itself after a `:colorscheme` switch (a `ColorScheme` autocmd,
see `transparency.lua`), because the new colorscheme just set its own
backgrounds back on every one of those groups.
