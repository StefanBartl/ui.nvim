---@module 'ui.util.lsp'
--- Single place that knows lsp.nvim's own in-process clients (no process, no
--- language -- e.g. `lsp.nvim-gitsigns`, which attaches to every buffer
--- gitsigns tracks, regardless of filetype) are not language servers.
---
--- ui.nvim must not depend on lsp.nvim, so this does not import it; the
--- `"lsp.nvim-"` prefix is the contract lsp.nvim documents at
--- `lua/lsp/core/util.lua`'s `M.INTERNAL_PREFIX` and commits to keeping
--- stable for exactly this reason -- any consumer, in or out of the plugin,
--- can rely on the name alone.

local M = {}

---@type string
M.INTERNAL_CLIENT_PREFIX = "lsp.nvim-"

--- Is `client` one of lsp.nvim's own in-process clients rather than a real
--- language server?
---@param client vim.lsp.Client|table
---@return boolean
function M.is_internal_client(client)
  return type(client.name) == "string" and vim.startswith(client.name, M.INTERNAL_CLIENT_PREFIX)
end

return M
