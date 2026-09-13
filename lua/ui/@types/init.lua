---@meta
---@module 'ui.@types'
--- Root types. (The `---@meta` above was `--@meta` until the extraction — one
--- dash short, so LuaLS never treated this file as a definition file.)

--- The four shipped, generic statusline presets `ui.config` can assemble by
--- name. A fifth possibility -- a fully-built variant table, for a host's
--- own plugin-specific segments -- is not a name in this alias; see
--- `ui.config.setup`'s `opts.variant` and
--- `docs/examples/personal-statusline-example.lua`.
---
--- Was six names (`normal`/`base`/`lspbased`/`custom`/`custom_light`/
--- `custom_minimal`) until the 2026-09-12 preset consolidation: `custom` was
--- the only one with genuine personal-plugin coupling (casedesk.nvim,
--- filetree.nvim) and moved to the example above; `lspbased`/`custom_light`
--- were the same segment set assembled two different ways and are one file
--- now (`lsp`); the rest were renamed for clarity once "normal" could no
--- longer mean "whatever NvChad's own default did."
---@alias Ui.StatuslineVariant
---| "default"  # full-featured, closest to the historical NvChad default
---| "minimal"  # cursor, cwd, progress -- nothing else
---| "lsp"      # LSP-aware breadcrumbs and enhanced modules
---| "blocks"   # "lsp"'s segments, drawn as gen_block chips

--- What `ui.setup(opts)` turns on.
---
--- Named after the modules they enable (`keymaps`, `usrcmds`), which is also
--- what those modules are called under `bindings/`. They were `mappings` and
--- `usrcmd` before the extraction, when the directories were.
---@class Ui.Modules
---@field all? boolean # Shorthand for every flag below
---@field keymaps? boolean|Ui.Keymaps.Keys # turns the keymaps submodule on; `true` (or omitted, under `all`) for every default, a table to remap/drop individual actions -- see `Ui.Keymaps.Keys`
---@field usrcmds? boolean # The `:UI` command and theme management

--- One keymap action's left-hand side, or `false` to not bind it at all.
---@alias Ui.Keymaps.Lhs string|false

--- `ui.bindings.keymaps.setup(opts)`'s own parameter -- `lib.nvim.bindings
--- .keymap.register()`'s `user` table, unwrapped (no extra `all`/group
--- flags on top, no nested `keys` field): absent (`nil`, `{}`, or `true`)
--- binds every action at its shipped default, `false` binds none, and any
--- key present here overrides just that one action -- `{ next =
--- "<C-Right>", close = false }` remaps `next` and drops `close`, leaving
--- `prev`/`move_right`/`move_left`/`move_to_tab`/`toggle_theme`/
--- `theme_picker` at their defaults. Same shape `my.nvim`'s own
--- `bindings/keymaps.lua` uses.
---@class Ui.Keymaps.Keys
---@field next? Ui.Keymaps.Lhs # default "<Tab>" -- next buffer
---@field prev? Ui.Keymaps.Lhs # default "<S-Tab>" -- previous buffer
---@field close? Ui.Keymaps.Lhs # default "<leader>bc" -- close buffer(s), count-aware
---@field move_right? Ui.Keymaps.Lhs # default "<leader>tr" -- move buffer right in vim.t.bufs
---@field move_left? Ui.Keymaps.Lhs # default "<leader>tl" -- move buffer left in vim.t.bufs
---@field move_to_tab? Ui.Keymaps.Lhs # default "<leader>tt" -- move current buffer to a new tab
---@field toggle_theme? Ui.Keymaps.Lhs # default "<leader>ut" -- toggle between the two configured themes
---@field theme_picker? Ui.Keymaps.Lhs # default "<leader>uP" -- open the visual theme picker (live preview)

--- Theme options `:UI theme`/`:UI toggle`/`:UI transparency` read. Not "which
--- colorscheme to boot into" -- that is the host's own init.lua, independent
--- of this plugin. Was `Ui.Base46`, handed through to base46 via `chadrc`;
--- step 6 of the roadmap dropped the `theme` field along with base46 itself.
---@class Ui.Theme
---@field transparency boolean
---@field theme_toggle string[] # The pair `:UI toggle` swaps between

--- The shipped defaults, aggregated in `ui.config.DEFAULTS`.
---@class Ui.Defaults
---@field theme Ui.Theme
---@field statusline { variant: Ui.StatuslineVariant }
---@field tabline Ui.Tabline.Config
---@field modules Ui.Modules

--- The assembled shape `ui.statusline.render.generate()`/`enable()` consume
--- -- the `ui.statusline` half of what `ui.config.setup()` returns.
---@class Ui.Statusline.Config
---@field order (string|"%=")[] # walked in order; "%=" passes through as the alignment break
---@field modules? table<string, string|fun(): string> # per-key override; a key absent here falls back to `theme`'s module set
---@field theme? string # fallback module-set name (see ui.statusline.themes.*); default "default"
---@field separator_style? string|{left: string, right: string} # passed to the theme's `build()`

--- The assembled shape `ui.tabline.render.generate()`/`enable()` consume --
--- the `ui.tabline` half of what `ui.config.setup()` returns. One shipped
--- config (`ui.config.tabline`), not a named-preset choice like
--- `Ui.StatuslineVariant` -- override `order`/`modules` directly via
--- `ui.config.setup({ tabline = {...} })` instead of naming a variant.
---@class Ui.Tabline.Config
---@field order string[] # walked in order; ui.tabline.modules' four keys by default
---@field modules? table<string, fun(cfg: Ui.Tabline.Config): string> # per-key override; a key absent here falls back to the built-in module of the same name
---@field bufwidth? integer # exact buffer-chip width in columns; unset (default) computes one from the available space and buffer count instead
---@field bufwidth_min? integer # lower clamp for the auto-computed width; default 12. Ignored when `bufwidth` is set
---@field bufwidth_max? integer # upper clamp for the auto-computed width; default 24. Ignored when `bufwidth` is set
---@field style? "rounded"|"square"|"divider" # chip-boundary look; default "rounded". An unrecognized value falls back to "rounded"
---@field tree_offset_ft? string # filetype the "tree_offset" module reserves space for; default "filetree" (filetree.nvim)

return {}
