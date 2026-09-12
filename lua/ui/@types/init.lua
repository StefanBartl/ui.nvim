---@meta
---@module 'ui.@types'
--- Root types. (The `---@meta` above was `--@meta` until the extraction — one
--- dash short, so LuaLS never treated this file as a definition file.)

--- The six statusline layouts `ui.config` can assemble.
---@alias Ui.StatuslineVariant
---| "normal"          # NvChad's own statusline, unmodified
---| "base"            # minimal: cursor, cwd, progress
---| "lspbased"        # LSP-aware breadcrumbs and enhanced modules
---| "custom"          # the older custom breadcrumb implementation
---| "custom_light"    # "custom" assembled through a merge-based setup()
---| "custom_minimal"  # "custom" built on NvChad's gen_block pattern

--- What `ui.setup(opts)` turns on.
---
--- Named after the modules they enable (`keymaps`, `usrcmds`), which is also
--- what those modules are called under `bindings/`. They were `mappings` and
--- `usrcmd` before the extraction, when the directories were.
---@class Ui.Modules
---@field all? boolean # Shorthand for every flag below
---@field keymaps? boolean # Buffer/tab navigation and tabline mappings
---@field usrcmds? boolean # The `:UI` command and theme management

--- What `ui.bindings.keymaps.setup(opts)` turns on.
---@class Ui.Keymaps.Modules
---@field all? boolean
---@field buffers? boolean
---@field tabs? boolean

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
---@field modules Ui.Modules

--- The assembled shape `ui.statusline.render.generate()`/`enable()` consume
--- -- the `ui.statusline` half of what `ui.config.setup()` returns.
---@class Ui.Statusline.Config
---@field order (string|"%=")[] # walked in order; "%=" passes through as the alignment break
---@field modules? table<string, string|fun(): string> # per-key override; a key absent here falls back to `theme`'s module set
---@field theme? string # fallback module-set name (see ui.statusline.themes.*); default "default"
---@field separator_style? string|{left: string, right: string} # passed to the theme's `build()`

return {}
