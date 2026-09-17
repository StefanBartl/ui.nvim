---@module 'ui.highlights.diagnostics'
--- Remove the background from diagnostic virtual text, and keep it removed.
---
--- A `:colorscheme` redefines `DiagnosticVirtualText*` from scratch, which
--- puts the backgrounds straight back. This used to be applied exactly once,
--- from `ui.config.setup()`, so the very first theme switch undid it and
--- nothing put it away again -- including the switches this plugin fires
--- itself (`:UI toggle`, `:UI picker`). Every other highlight module here
--- (`statusline.highlights`, `tabline.highlights`, `theme.transparency`,
--- `kit.theme`, ...) already re-registered on `ColorScheme`; this one was the
--- outlier.
---
--- Split the same way those are: `M.apply()` is idempotent and serves as both
--- the initial call and the `ColorScheme` handler, `M.setup()` wires the two
--- together. The augroup is cleared on create, so calling `setup()` again --
--- `ui.config.setup()` is not once-only -- cannot stack duplicate autocmds.

local M = {}

--- Diagnostic virtual-text groups whose background is cleared. Foreground is
--- deliberately left alone: it carries the severity colour from the theme.
---@type string[]
local GROUPS = {
  "DiagnosticVirtualTextError",
  "DiagnosticVirtualTextWarn",
  "DiagnosticVirtualTextInfo",
  "DiagnosticVirtualTextHint",
}

--- Clear the background on every group in `GROUPS`. Safe to call at any time
--- and any number of times.
---@return nil
function M.apply()
  local hl = require("lib.nvim.ui.hl")

  for _, group in ipairs(GROUPS) do
    hl.set(group, {
      bg = "NONE",
      -- Keep foreground color from theme
      link = nil,
    })
  end
end

--- Apply once now, then re-apply after every colorscheme change.
---@return nil
function M.setup()
  -- Was the one module here with no re-registration at all, then gained a
  -- hand-written one; `hl.persist` is that same pair plus the
  -- `OptionSet background` case, and is now what every highlight module in
  -- this plugin uses.
  require("lib.nvim.ui.hl").persist(M.apply, { name = "ui_highlights_diagnostics" })
end

return M
