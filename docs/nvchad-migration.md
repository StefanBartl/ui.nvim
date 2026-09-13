# NvChad migration & credits

This plugin's statusline/tabline/theme layer started as a port out of
[NvChad](https://nvchad.com) — the layout, the preset shapes, and a good deal
of the original implementation this repository's own code has since replaced
symbol by symbol trace back to it. No NvChad code or symbol remains a runtime
dependency as of step 7 below, but the debt is real and worth naming: this
plugin would not look the way it does, or exist at all, without NvChad having
shown what a statusline/tabline/theme layer for Neovim could be first.

This page is the decision record of how the decoupling actually happened,
step by step. It stays here rather than in the README because it describes
what changed and when — a changelog, not a description of the plugin's
current state.

## The coupling, counted at the start (2026-09-08, before step 3)

| Symbol | Calls | Guarded | What it provided |
| --- | ---: | ---: | --- |
| `nvchad.stl.utils` | 21 | 14 | Statusline primitives: separator glyphs, the mode table |
| `nvconfig` | 3 | **0** | NvChad's resolved UI configuration, read for separator style |
| `nvchad.tabufline` | 3 | 3 | Buffer/tab movement for the tabline keymaps |
| `base46` | 4 | 4 | Theme loading and the transparency toggle |
| `base46.themes` | 1 | 1 | The theme list `:UI theme` completes over |

None of these five symbols appear in this plugin's own code any more, under
any name, as of step 6. This table describes history, not a current
dependency.

An earlier version of this section claimed "exactly two symbols" and made a
point of the number. It was wrong: the measurement counted `require("x")`
with a single regex and never matched `pcall(require, "x")`, which is the
form most of this code uses — precisely because most of these calls are
already guarded. Three symbols were invisible to it.

## Step 1–2 (2026-09-08): extraction

Roughly 4,500 lines of statusline, tabline and theme code that ran in one
config against NvChad moved into this repository.

## Step 3 (2026-09-08): statusline primitives ported

`nvchad.stl.utils` was ported into this plugin's own
`ui.statusline.utils.primitives`, and every statusline variant got its own
`separator_style` literal instead of reading `nvconfig`. Neither symbol was
required by this plugin's code any more after this step, and every
statusline variant module loaded and assembled with NvChad entirely absent
from the runtimepath.

Step 3 alone did not mean this plugin rendered without NvChad, and the "five
symbols, 32 call sites" count above was never the whole coupling.
`ui.config.setup()` only ever returned a config table; something else had to
turn `{order, modules}` into `vim.o.statusline`. Before step 4 that something
was entirely NvChad's: `nvchad.init` set `vim.o.statusline =
"%!v:lua.require('nvchad.stl.<theme>')()"`, and `nvchad.stl.<theme>` called
`nvchad.stl.utils.generate()`.

## Step 4 (2026-09-08): its own render entrypoint

`ui.statusline.render.generate()` is the same walk as NvChad's own, own code,
own tests, and `enable()`/`render()`/`disable()` are the `vim.o.statusline`
wiring around it. Every `order` key a variant's own `modules` does not cover
falls back to `ui.statusline.themes.default` — the one theme any of the
shipped layouts actually needs.

Proving it end to end (`TESTS/statusline_render_spec.lua`) surfaced one real
bug along the way: `custom.lua`'s `cursor` module called `get_separators()`
with no argument, indexing a nil table — silent under NvChad's own
`generate()`, which does not `pcall` a module call, and only reachable with
the cursor-progress mode active. Fixed in the same commit.

What step 4 did **not** mean, at the time: that this plugin rendered without
NvChad *that day*, for a user of the reference host it was extracted from.
Nothing outside this plugin's own tests called `enable()` yet — the host's
`chadrc.lua` still handed its config to NvChad's own renderer. That gap is
what step 7 closed.

## Step 5 (2026-09-08): `nvchad.tabufline` replaced

The same shape of gap showed up one level down. `nvchad.tabufline` never
appeared as a `require()` at the three call sites that needed it — what
those sites called for was `close_buffer()`/`move_buf()`, but what made this
plugin's own `next()`/`prev()` do anything at all was `vim.t.bufs`, kept
current by autocmds that lived entirely in NvChad's own
`nvchad/tabufline/lazyload.lua`. `ui.bindings.keymaps.tabufline.state` ports
the bookkeeping and the two functions. A rendered tabline (`vim.o.tabline`)
is separate, larger scope and was not ported — still "Planned scope > Tabline".

## Step 6 (2026-09-12): `base46` replaced

The last symbol on the list, and the point where the open palette question
got decided. Three options were weighed — depend on a colorscheme library,
read the active colorscheme's own highlight groups, ship a palette — and the
second won on every axis that mattered, the same technique lualine's "auto"
theme already relies on: `DiagnosticError` / `DiagnosticHint` /
`DiagnosticInfo` / `DiagnosticOk` / `Comment` are close to universally
defined, because built-in LSP diagnostics need them. The third option
survives only as `ui.theme.palette`'s fallback layer, for a colorscheme that
leaves one of those groups undefined.

The only place this plugin ever read a *raw color value* out of base46 was
`filetree_cwd_mode`'s cwd-mode badge (`base46.get_theme_tb("base_30")`) —
everything else base46 touched was theme *switching*, not color data.
Switching is now a real `pcall(vim.cmd.colorscheme, name)`
(`ui.bindings.usrcmds.themes`), and the theme list is
`getcompletion("", "color")` — every colorscheme Neovim can see, not a fixed
~50-name NvChad set.

One deliberate scope cut alongside it: the old code persisted a theme choice
by string-replacing a line in `chadrc.lua` on disk. That is gone, on
purpose — choosing a startup colorscheme is the host's own `init.lua`, the
same as any Neovim config, not something a UI-frame plugin should be
rewriting files for.

## Same day, full-repo audit (2026-09-12)

Seven bugs found and fixed: a swapped transparency on/off, a git-status
guard checking a field gitsigns never sets, a missing separator fallback, one
shared highlight group across every window's file icon, a config-update
function that dropped valid fields after a bad one, a path cache missing
part of its key, and a tabufline close reading the wrong buffer's option —
see the commit for the full list.

The statusline layouts went from six to four: `custom` (the only one with
real personal-plugin coupling — `casedesk.nvim`, `filetree.nvim`) moved to
[docs/examples/personal-statusline-example.lua](examples/personal-statusline-example.lua)
instead of staying a shipped preset, because a preset that assumes plugins
only its own author has is not a preset. `lspbased`/`custom_light` (the same
segment set, assembled two different ways) became one file, `lsp`.
`ui.config.setup()` gained `opts.variant`, a way to hand it a fully-built
statusline table directly — the mechanism a host now uses for exactly the
kind of plugin-specific statusline `custom` used to be.

## Winbar ownership split (2026-09-12, third round)

`ui.winbar.set(line, winid)` is the one thing about a winbar that is
actually a frame concern — the scheduled, window-validity-checked write. A
content plugin (my.nvim's `hl_config.breadcrumbs`) keeps everything else
(debouncing, skip-rules, the string itself) and hands the result over when
this module is present, same shape as the `vim.diagnostic.config()`
contribute/apply split lsp.nvim/my.nvim already had.

Separately, `ui.config.variants` is now the one registry both the four
shipped presets and any host-registered variant live in; `:UI variant
{name}`/`:UI variants` switch and list against it, and switching is a
genuine runtime operation — `ui.config.setup()` +
`ui.statusline.render.enable()` — not just a boot-time constant, because
this plugin has owned its own render entrypoint since step 4.

## Two visual bugs found on the first live restart (2026-09-12, fifth round)

`ui.statusline.utils.primitives.separators`' `"default"` and `"round"`
styles (and, on closer look, `"arrow"`) turned out to be empty strings —
`git log -p` shows this table has been that way since its very first commit
in this repo, the original wkdnvchad extraction, not a regression from
anything done that day. Every statusline variant using anything but
`"block"` had been rendering with no separator caps at all since day one.
Restored the standard Powerline codepoints (U+E0B0/B2/B4/B6) as explicit byte
escapes, so an editor/encoding pass can't drop them again silently.

Separately, `filetree.nvim`'s `cwd_mode` has six modes, not five — the
accent-color map was missing `"follow"`, the inert default most sessions
spend most of their time in, so it fell through to a fallback color by
accident rather than a documented choice.

## Step 7 (2026-09-13): the host itself goes NvChad-free

`chadrc.lua` is gone from the reference host this plugin was extracted from;
it calls `require("ui").setup(...)`/`require("ui.config").setup(...)`
directly from its own startup phase, and NvChad itself is no longer
installed there at all.

That did not make this plugin a NvChad replacement. `ui.nvim` only ever
covered the frame — statusline, tabline, theme assembly — the same scope
[scope.md](scope.md) always named. Everything else NvChad's own plugin
bundle also installed (Mason, which-key, Treesitter, Telescope, gitsigns,
nvim-web-devicons, and more) needed its own, separate, direct plugin spec in
that host once NvChad stopped providing it — this plugin has no opinion on
any of those and does not install or configure them. "NvChad-free" describes
this plugin's own statusline/tabline/theme code and, now, that one reference
host's setup — not a claim that installing `ui.nvim` alone reproduces what a
NvChad install gives you.
