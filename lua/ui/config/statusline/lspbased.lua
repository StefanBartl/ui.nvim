---@module 'ui.config.statusline.lspbased'
--- LSP-aware statusline with breadcrumbs and enhanced modules

local notify = require("lib.nvim.notify").create("[ui.config.statusline.lspbased]")

local M = {}

---Setup function called after config assembly
---@param config table
function M.setup(config)
  -- The LSP-aware module set (breadcrumbs, diagnostics, lsp, cursor, progress)
  -- is defined once in custom_light and shared with this variant.
  local ok, cl = pcall(require, "ui.config.statusline.custom_light")
  if not ok then
    notify.error("[statusline.lspbased] Failed to load custom_light: " .. tostring(cl))
    return
  end

  -- Register statusline modules
  if config.ui and config.ui.statusline then
    cl.register_statusline_modules(config.ui.statusline)
  end
end

M.ui = {
  statusline = {
    order = {
      "mode",
      "git",
      "%=",
      "breadcrumbs",
      "%=",
      "diagnostics",
      "lsp",
      "cursor",
      "progress",
      "cwd",
    },

    -- Modules will be registered by setup() function above
    modules = {},
  },
}

return M
