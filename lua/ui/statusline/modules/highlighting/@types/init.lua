---@meta
---@module 'ui.statusline.modules.highlighting.@types'

---@class Ui.UI.Stl.Modules.Highlighting
---@field stl_strip_hl fun(s: string): string
--- Strips embedded statusline highlight sequences
--- ("%#Group#" and "%*") from a string, so the content
--- can be re-wrapped with the module's own groups.
---
---@field hl_open fun(group: string): string
--- Opens a statusline highlight group without a trailing
--- reset ("%*") -- used when a highlight band should carry
--- on across several modules.
---
---@field hl_wrap fun(group: string, s: string): string
--- Wraps a string fully in a statusline highlight group,
--- reset included. Empty or nil strings yield "".
---
---@field mode_band_group fun(): string
--- Resolves the current mode-band highlight group from the
--- current Vim mode. Return format: "St_<Name>mode"
--- (e.g. "St_Normalmode", "St_Insertmode").

-- Type Usage:
-- ---@type Ui.UI.Stl.Modules.Highlighting
-- local hl_module = require("lib.lua.lazy").require("ui.statusline.modules.highlighting")

return {}
