# `:UI` command module

Runtime UI configuration: colorscheme switching and this plugin's own
transparency toggle. Was Base46-specific through step 5 of `ROADMAP.md`; step
6 replaced that with real `:colorscheme` switching. See
`themes/README.md` for what exactly changed and why.

## Table of content

- [Usage](#usage)
- [Recommended keybindings](#recommended-keybindings)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)

## Usage

### Switch theme

```vim
:UI theme tokyonight      " switch to the tokyonight colorscheme
:UI theme <Tab>           " complete over every colorscheme Neovim can see

:Theme tokyonight         " shortcut, same effect
```

`:UI theme` with no argument shows the active colorscheme
(`vim.g.colors_name`) instead of switching.

### List themes

```vim
:UI themes
```

Lists every colorscheme `getcompletion("", "color")` finds — built-in and
installed by any plugin manager — with `✓` marking the active one.

### Toggle transparency

```vim
:UI transparency          " toggle
:UI transparency on       " enable
:UI transparency off      " disable
```

Strips `bg` from the groups this plugin's own frame draws (editor body,
statusline, tabline, winbar) — not full-UI transparency; see
`ui.theme.transparency` for the exact group list and why it stops there.

### Toggle between two themes

Configure the pair in `lua/ui/config/theme.lua`:

```lua
return {
  theme_toggle = { "tokyonight", "rosepine" },
  transparency = false,
}
```

Then:

```vim
:UI toggle                " switch to the other theme in the pair
```

### Show status

```vim
:UI status
```

```
╭─ UI Status ─────────────────╮
│ Theme:        tokyonight    │
│ Transparenz:  aus           │
│ Toggle:       tokyonight... │
╰─────────────────────────────╯
```

### Help

```vim
:UI help
:UI                        " no argument also shows help
```

## Recommended keybindings

```lua
vim.keymap.set("n", "<leader>tt", ":UI toggle<CR>", { desc = "Toggle Theme" })
vim.keymap.set("n", "<leader>ts", ":UI transparency<CR>", { desc = "Toggle Transparency" })
vim.keymap.set("n", "<leader>th", ":UI themes<CR>", { desc = "List Themes" })
```

## Configuration

`lua/ui/config/theme.lua`:

```lua
return {
  transparency = false,
  theme_toggle = { "tokyonight", "rosepine" },
}
```

There is no `theme` field (which colorscheme to boot into) and no
`hl_override` — those were base46-specific. Pick a startup colorscheme the
normal way, in the host's own `init.lua`.

## Troubleshooting

### Theme not found

```vim
:UI themes              " list every colorscheme Neovim can see
```

If a theme you expect is missing, its plugin is not installed or not yet
loaded (lazy-loaded colorscheme plugins that load on `VeryLazy` or an event
appear only once loaded).

### Transparency does nothing visible

Your terminal emulator itself needs to support transparency — this command
only clears `bg` on Neovim's own highlight groups; the terminal renders
whatever is behind the window.

### Completion doesn't work

1. `require("ui").setup({ all = true })` (or `{ usrcmds = true }`) must have
   run.
2. Tab-complete in command mode, after `:UI theme ` (with the trailing
   space).
