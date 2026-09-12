# ui.nvim Configuration System

Central configuration loader with statusline variant selection.

## Table of content

- [ui.nvim Configuration System](#uinvim-configuration-system)
  - [Structure](#structure)
  - [Usage](#usage)
    - [1. Pick a statusline variant](#1-pick-a-statusline-variant)
    - [2. Adjust theme settings](#2-adjust-theme-settings)
    - [3. Host wiring](#3-host-wiring)
  - [Statusline variants](#statusline-variants)
  - [Writing your own variant](#writing-your-own-variant)
  - [API](#api)
  - [Assembly order](#assembly-order)
  - [Troubleshooting](#troubleshooting)
  - [Examples](#examples)

---

## Structure

```
lua/ui/config/
├── init.lua              # Central config loader, M.setup()
├── DEFAULTS.lua          # Everything this plugin ships as a default (NEW-07)
├── theme.lua             # Transparency default + the :UI toggle pair
└── statusline/
    ├── normal.lua        # NvChad's own statusline, unmodified
    ├── base.lua          # Minimal: cursor, cwd, progress
    ├── lspbased.lua      # LSP-aware breadcrumbs
    ├── custom.lua        # Legacy custom breadcrumb implementation
    ├── custom_light.lua  # "custom" assembled through a merge-based setup()
    └── custom_minimal.lua # "custom" built on NvChad's gen_block pattern
```

Note: theme *switching* (`:UI theme`/`:UI toggle`) lives under
`ui.bindings.usrcmds.themes`, not here — this directory only assembles the
statusline/theme *configuration table*, it does not act on it. See
`lua/ui/bindings/usrcmds/themes/README.md` for that half.

## Usage

### 1. Pick a statusline variant

In `lua/ui/config/init.lua`:

```lua
---@type Ui.StatuslineVariant
M.STATUSLINE_VARIANT = "lspbased"  -- change this
```

A setup-time choice, not a runtime one: this is read once when
`ui.config.setup()` runs.

### 2. Adjust theme settings

In `lua/ui/config/theme.lua`:

```lua
return {
  transparency = false,
  theme_toggle = { "default", "tokyonight" },
}
```

This is *not* "which colorscheme to boot into" — this plugin does not apply a
startup colorscheme. It is only what `:UI toggle` and `:UI transparency` read
as their defaults. Picking a starting colorscheme is the host's own
`init.lua`, the same as any Neovim config (`vim.cmd.colorscheme("name")`).

### 3. Host wiring

```lua
-- Currently still routed through NvChad's chadrc.lua (roadmap step 7 has not
-- rewired the host yet):
return require("ui.config").setup()
```

## Statusline variants

| Variant | What it is |
| --- | --- |
| `normal` | NvChad's own statusline, unmodified |
| `base` | Minimal: cursor, cwd, progress |
| `lspbased` | LSP DocumentSymbols-based breadcrumbs, Treesitter fallback, mode-band-colored devicons and diagnostics |
| `custom` | The older custom breadcrumb implementation |
| `custom_light` | `custom`, assembled through a merge-based `setup()` |
| `custom_minimal` | `custom`, built on NvChad's `gen_block` pattern |

## Writing your own variant

```lua
-- lua/ui/config/statusline/myvariant.lua
local M = {}

M.ui = {
  statusline = {
    order = { "mode", "file", "%=", "lsp", "cursor" },
    modules = {
      cursor = function()
        return " Ln %l "
      end,
    },
  },
}

---@param config table
function M.setup(config) end -- optional

return M
```

Then point `M.STATUSLINE_VARIANT` at `"myvariant"` in `init.lua`.

## API

### `ui.config.setup(user_opts?)`

Assembles the complete config.

```lua
local config = require("ui.config").setup({
  theme = { theme_toggle = { "default", "onedark" } }, -- optional override
})
```

Returns a table with `theme` and `ui` keys.

### `ui.config.get_variant()`

Returns `M.STATUSLINE_VARIANT` as a string.

### `ui.config.last()`

Returns the table `M.setup()` last returned, or `nil` before the first call.
`ui.bindings.usrcmds.themes` reads this for the `:UI toggle` pair, so a
`theme` override passed to `M.setup()` reaches that command.

## Assembly order

1. `require("ui").setup({ all = true })` — turns on this plugin's submodules.
2. `require("ui.config").setup()` — loads `ui.config.theme`, merges any
   `user_opts.theme` override.
3. Loads the selected statusline variant, runs its `setup()` if present.
4. Removes diagnostic virtual-text backgrounds (`ui.highlights.diagnostics`).
5. Caches the result (`ui.config.last()`) and returns it.

## Troubleshooting

### Statusline variant fails to load

```
[ui.config] Failed to load statusline variant 'xyz'
```

1. Check `lua/ui/config/statusline/xyz.lua` exists.
2. Check its Lua syntax.
3. `:checkhealth ui` reports whether the named variant module resolves.

### Modules missing

```
attempt to call field 'breadcrumbs' (a nil value)
```

1. Check the variant's `modules = {}` table.
2. Check its `setup()` actually registers what `order` names.

## Examples

### Minimal

```lua
-- config/init.lua
M.STATUSLINE_VARIANT = "normal"

-- config/theme.lua
return { transparency = false, theme_toggle = { "default", "tokyonight" } }
```

### With overrides

```lua
require("ui.config").setup({
  theme = { theme_toggle = { "default", "gruvbox" } },
})
```
