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

--- Theme options handed through to base46 via `chadrc`.
---@class Ui.Base46
---@field theme string # Active theme name
---@field transparency boolean
---@field theme_toggle string[] # The pair `:UI toggle` swaps between

--- The shipped defaults, aggregated in `ui.config.DEFAULTS`.
---@class Ui.Defaults
---@field base46 Ui.Base46
---@field statusline { variant: Ui.StatuslineVariant }
---@field modules Ui.Modules

return {}
