# ui.menu

The right-click menu: what your sister plugins contribute, a set of general
sections (Code, Clipboard, File, Delete, Tools), rows of your own — and the two
triggers that open it. Drawn by [`ui.contextmenu`](../contextmenu/README.md), so
no third-party menu plugin is needed.

Off until asked for, because it takes over the global `<RightMouse>`:

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
| 3. the plugin's side | the plugin's `submenu()` returns nil, or its module's `enabled()` returns false | you, in that plugin's own setup — plugins name it `integrations.ui_menu = false` (markdown.nvim: `menu = { enable = false }`) |

Known names: `markdown`, `open`, `dap`, `cascade`, `fileops`, `images`,
`spotlight`, `color_my_ascii`, `lsp`, `gopath`, `filetree`. A plugin whose
`submenu()` raises is skipped; it cannot take the menu down.

### The contract a plugin implements

```lua
-- <plugin>/integrations/menu.lua
local M = {}
function M.enabled() return require("myplugin.config").get().integrations.ui_menu ~= false end  -- optional
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
  opens on top.

## Triggers

| Option | Default | |
| --- | --- | --- |
| `mouse` | `true` | `<RightMouse>` (normal and visual): menu at the pointer |
| `key` | `"<A-b>"` | same menu at the cursor; `false` for none |
| `renderer` | `"kit"` | `ui.contextmenu` renderer; `"auto"` prefers nvzone/menu when installed |
| `native_popup` | `false` | `true` keeps Neovim's own right-click popup |

## API

`require("ui.menu")`: `setup(opts)`, `items(buf?)` (the item list),
`open({ buf?, mouse? })`, `on_right_click()` (the handler, for your own binding),
`register_contributor(spec)`, `add(entry)`, `config()`.

Files: `config.lua` (defaults), `contributors.lua` (sister plugins + your rows),
`sections.lua` (the general sections), `selection.lua`, `icons.lua`.
Tested in [`TESTS/menu_spec.lua`](../../../TESTS/menu_spec.lua).
