---@module 'ui.highlights.diagnostics'
--- Remove background from diagnostic virtual text.

local M = {}

---@return nil
function M.setup()
  local hl = require("lib.nvim.ui.hl")

  -- Remove background from all diagnostic virtual text levels
  local groups = {
    "DiagnosticVirtualTextError",
    "DiagnosticVirtualTextWarn",
    "DiagnosticVirtualTextInfo",
    "DiagnosticVirtualTextHint",
  }

  for _, group in ipairs(groups) do
    hl.set(group, {
      bg = "NONE",
      -- Keep foreground color from theme
      link = nil,
    })
  end
end

return M
