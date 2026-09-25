# ui.menu

The right-click menu: what your sister plugins contribute, a set of general
sections (Code, Clipboard, File, Delete, Tools), rows of your own — and the two
triggers that open it. Drawn by [`ui.contextmenu`](../contextmenu/README.md), so
no third-party menu plugin is needed.

Off until asked for, because it takes over the global `<RightMouse>` (and
sets `'mousemodel'` to `"extend"`, which is what makes a right click there
start Visual mode — see "The selection"):

```lua
require("ui").setup({
  menu = {
    integrations = { lsp = false },        -- see "Sister plugins" below
    hints = { save = "<C-s>" },            -- show a mapping next to an entry
    entries = { delete_file = true },      -- destructive ones are off by default
  },
})
-- or, without ui.setup:
require("ui.menu").setup({ ... })
```

`menu = false` (the older switch) still means "no `ui.contextmenu` rendering at
all"; `menu = true` keeps meaning "leave it at its default" and does **not**
bind anything. Only a table turns `ui.menu` on.

## What it shows

Per open, top to bottom:

1. **Integrations** — one fly-out per installed sister plugin (below).
2. **Your own rows** — one section per `section` name (`extra`, below).
3. **Code** (Format, Code Actions, Inspect), **Clipboard** (Copy All, Copy
   Marked, Paste), **File** (Save, Save All), **Delete** (Delete Marked; Delete
   All and Delete File are **off** by default), **Tools** (terminal, colour
   picker, Unicode table, Git Actions).

A section with no entry left shows no heading; "Integrations" never appears
empty. `sections = { file = false }` drops a whole section, `entries = { save =
false }` one entry, `hints = { save = "<C-s>" }` puts a mapping next to it.
Unicode Table needs `emojis.nvim`, Git Actions needs `gitsuite.nvim`; without
them the row is simply absent.

## Sister plugins: three opt-outs, all default on

A plugin contributes when **all** of these hold:

| Layer | Switch | Who decides |
| --- | --- | --- |
| 1. installed | its `<plugin>.integrations.menu` module `require`s | nobody — not installed means not shown, silently |
| 2. ui.nvim's side | `menu = { integrations = { <name> = false } }`, or `integrations = false` for none | you, in the ui.nvim spec |
| 3. the plugin's side | its `integrations.ui_menu = false` (or the plugin's own `menu` group off): its module's `enabled()` returns false, or `submenu()` returns nil | you, in that plugin's own setup |

Every listed plugin implements `integrations.ui_menu` (markdown.nvim, open.nvim,
dap.nvim, cascade.nvim, fileops.nvim, images.nvim, spotlight.nvim,
color_my_ascii.nvim, lsp.nvim, gopath.nvim, filetree.nvim); ui.nvim asks each
module's `enabled()` first.

Known names: `markdown`, `open`, `dap`, `cascade`, `fileops`, `images`,
`spotlight`, `color_my_ascii`, `lsp`, `gopath`, `filetree`. A plugin whose
`submenu()` raises is skipped; it cannot take the menu down.

### The contract a plugin implements

```lua
-- <plugin>/integrations/menu.lua
local M = {}
function M.enabled() return require("myplugin.config").get().integrations.ui_menu ~= false end  -- optional; false = do not compose me
function M.submenu(label) ... return { name = "  My plugin", items = { ... } } end             -- nil = nothing to show
return M
```

No dependency on ui.nvim: the items are plain tables (`name`, `cmd`, `rtxt`,
`icon`, `items`). ui.nvim owns the wiring, the plugin owns whether it takes part.

### Another contributor of your own

```lua
require("ui").setup({ menu = { contributors = {
  { name = "mytool", module = "mytool.menu", ft = { "lua" } },
} } })
-- or at runtime, e.g. from a plugin's setup:
require("ui.menu").register_contributor({ name = "mytool", module = "mytool.menu" })
```

## Rows of your own

One line per row; the section name is what groups them:

```lua
menu = { extra = {
  { plugin = "harpoon", label = "Harpoon: add file", cmd = "lua require('harpoon'):list():add()",
    section = "Harpoon", hint = "<leader>ha" },
  { plugin = "neotest", label = "Run nearest test", keys = "<leader>tn", section = "Test", ft = "lua" },
  { label = "Reload config", cmd = function() vim.cmd("source $MYVIMRC") end },
} }
```

| Field | Meaning |
| --- | --- |
| `label` | the row text (required) |
| `cmd` | an Ex command string, or a function |
| `keys` | instead of `cmd`: keys fed with remapping — `"<leader>ha"` runs that mapping |
| `section` | heading it is grouped under; rows sharing a name share one section (default `Custom`) |
| `plugin` | module name(s) that must be installed, else the row is not shown |
| `ft` | only in buffers of these filetypes |
| `when` | `fun(buf): boolean`, evaluated at open time |
| `icon`, `hint` | leading glyph; right-aligned text (usually the mapping) |
| `enabled` | `false` keeps it configured but hidden |

`require("ui.menu").add({ ... })` appends one at runtime.

## First open and lazy plugins

A contributor's menu module lives inside its plugin, so `require`ing it loads
the whole plugin: measured in one real setup, the first open took ~1.1 s (two
plugins took ~0.4 s each). `prewarm` (default on) loads those modules in idle
slices after startup — those not tied to a filetype and not switched off — so
the first right click takes ~80 ms instead. `prewarm = false` keeps a lazy
plugin unloaded until the first open, at that price. A plugin that opted out only on its own side
(`integrations.ui_menu = false` in its setup) is still loaded by `prewarm`, because
ui.nvim can only read that switch after the plugin is loaded; name it in
`menu = { integrations = { <name> = false } }` as well to keep it unloaded. A `plugin = "..."` gate on
one of your own rows is checked the same way (by `require`), so it loads a lazy
plugin the first time the menu opens.

## The selection

The Visual selection is captured when the menu is **built**. By the time an entry
runs the menu has closed and Visual mode is over, so asking then always answered
"no selection" — "Copy Marked" copied the whole buffer.

- A right click **inside** the selection keeps it; Copy/Delete Marked act on
  exactly what was marked.
- A right click **elsewhere** ends it and moves the cursor to the pointer, with a
  left click. Replaying a right click would start a new Visual selection under
  `'mousemodel' = "extend"` (which `ui.contextmenu.setup` sets) from the old
  cursor to the pointer.
- Clicks on the tab bar and the statusline are replayed natively — those have
  their own menus (`ui.tabline.menu`, `ui.statusline.menu`) and no second one
  opens on top. A click on a window's winbar is replayed natively too (its own
  handler answers a right click; a left click would run its navigate action)
  and the menu opens for that window's buffer.

## Triggers

| Option | Default | |
| --- | --- | --- |
| `mouse` | `true` | `<RightMouse>` (normal and visual): menu at the pointer |
| `key` | `false` | bind this key to the same menu at the cursor (`"<A-b>"`, say). No global key is taken unasked |
| `renderer` | `"kit"` | `ui.contextmenu` renderer; `"auto"` prefers nvzone/menu when installed |
| `native_popup` | `false` | `true` keeps Neovim's own right-click popup. With `mouse = false` `'mousemodel'` is left alone regardless |
| `prewarm` | `true` | load the sister plugins' menu modules one per idle tick after startup (see below) |

## API

`require("ui.menu")`: `setup(opts)`, `items(buf?)` (the item list),
`open({ buf?, mouse? })`, `on_right_click()` (the handler, for your own binding),
`register_contributor(spec)`, `add(entry)`, `config()`.

Files: `config.lua` (defaults), `contributors.lua` (sister plugins + your rows),
`sections.lua` (the general sections), `selection.lua`, `icons.lua`.
Tested in [`TESTS/menu_spec.lua`](../../../TESTS/menu_spec.lua).
