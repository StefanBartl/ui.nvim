---@module 'ui.slots.util'
--- Small helpers the kinds share.

local M = {}

--- A message to the user, with the module prefix.
---@param msg string
---@param level integer|nil  # default WARN
function M.notify(msg, level)
  vim.notify("[ui.slots] " .. msg, level or vim.log.levels.WARN)
end

--- Say which placeholders in a text were not known (nothing when the list is
--- empty).
---@param unknown string[]
---@param where string
function M.warn_unknown(unknown, where)
  if #unknown > 0 then
    M.notify(("%s: unknown placeholder %s"):format(
      where,
      table.concat(
        vim.tbl_map(function(name)
          return "{" .. name .. "}"
        end, unknown),
        ", "
      )
    ))
  end
end

return M
