---@meta
---@module 'ui.contextmenu.@types'

---One nvzone/menu-shaped entry: either a leaf action (`cmd`), a nested
---fly-out (`items`), or a separator (`name = "separator"`, no other field).
---@class Ui.ContextMenu.Item
---@field name string                Label, or the literal `"separator"`
---@field cmd? function|string       Leaf action: a callback, or an Ex command string
---@field items? Ui.ContextMenu.Item[]  Nested fly-out entries (mutually exclusive with `cmd`)
---@field rtxt? string               Right-aligned hint text (usually a default keymap)
---@field icon? string               Leading glyph, drawn in a column of its own -- NOT part of `name`
---@field icon_hl? string            Highlight group for the icon (kit renderer)
---@field hl? string                 Optional highlight group override (nvzone/menu)
---@field __heading? boolean         Group heading marker (see `heading`); not a row

---Options for `require("ui.contextmenu").bind_buffer(bufnr, get_items, opts)`.
---@class Ui.ContextMenu.BindOpts
---@field keymap? string     Trigger key (default `"<RightMouse>"`)
---@field modes? string[]    Modes to bind in (default `{ "n", "v" }`)
---@field mouse? boolean     Pass `{ mouse = true }` to `menu.open` (default `true`)
---@field desc? string       Keymap description (default `"Context menu"`)

---@alias Ui.ContextMenu.ItemsProvider fun(): Ui.ContextMenu.Item[]

---Presentation extras for `entry` / `submenu`. `icon` is a field rather than
---something a caller prefixes onto the label on purpose: the kit renderer
---gives icons a column, so labels stay aligned whether or not an entry has
---one.
---@class Ui.ContextMenu.ItemOpts
---@field icon? string     Leading glyph (one display cell)
---@field icon_hl? string  Highlight group for the icon
---@field hl? string       Highlight group for the label

---Which component draws the menu. `"auto"` (the default) prefers nvzone/menu
---when installed and falls back to `ui.kit.menu`.
---@alias Ui.ContextMenu.Renderer "auto"|"kit"|"nvzone"

---Options for `require("ui.contextmenu").open(items, opts)`.
---@class Ui.ContextMenu.OpenOpts
---@field mouse? boolean   Anchor at the mouse pointer (default `true`)
---@field title? string    Menu title (kit renderer only; nvzone/menu has none)
---@field theme? any       `Ui.Kit.ThemeArg` (kit renderer only)
---@field group_style? "box"|"header"|"plain"  How a group is drawn; default `"box"` (kit renderer only)
---@field submenu_marker? string  Glyph marking a nested entry (kit renderer only)
---@field relative? "editor"|"cursor"|"win"|"mouse"  Explicit anchor; overrides `mouse` (kit renderer only)
---@field win? integer     Anchor window when `relative = "win"` (kit renderer only) -- e.g. to open the menu beside a plugin's own window instead of at the pointer
---@field anchor? "NW"|"NE"|"SW"|"SE"  Which corner of the menu sits at (row, col) (kit renderer only)
---@field row? integer     Explicit row, paired with `relative`/`win` (kit renderer only)
---@field col? integer     Explicit column (kit renderer only)
---@field hover? boolean   Follow the mouse without a click (kit renderer only); default true

--- `ui.contextmenu` module surface.
---@class Ui.ContextMenu
---@field setup fun(opts?: { renderer?: Ui.ContextMenu.Renderer, native_popup?: boolean })  Sets `'mousemodel' = "extend"` by default, turning off Neovim's own built-in PopUp menu; `native_popup = true` opts back into it.
---@field renderer fun(): Ui.ContextMenu.Renderer
---@field entry fun(available: any, label: string, fn: function, rtxt?: string, opts?: Ui.ContextMenu.ItemOpts): Ui.ContextMenu.Item|nil
---@field heading fun(title: string): Ui.ContextMenu.Item
---@field group fun(out: Ui.ContextMenu.Item[], ...: Ui.ContextMenu.Item|nil): boolean
---@field submenu fun(label: string, items: Ui.ContextMenu.Item[], opts?: Ui.ContextMenu.ItemOpts): Ui.ContextMenu.Item|nil
---@field open fun(items: Ui.ContextMenu.Item[]|string, opts?: Ui.ContextMenu.OpenOpts): Ui.Kit.Surface|nil  Returns the surface (kit renderer only -- nil for nvzone/menu, which exposes no equivalent handle)
---@field bind_buffer fun(bufnr: integer, get_items: Ui.ContextMenu.ItemsProvider, opts?: Ui.ContextMenu.BindOpts)
