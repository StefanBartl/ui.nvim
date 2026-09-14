---@module 'ui.kit.config'
--- Static defaults for ui.kit. The runtime theme registry lives in
--- theme.lua; this only holds the initial active-preset choice.

local M = {}

M.defaults = {
  default = "rounded", -- active preset when a call passes no theme
}

return M
