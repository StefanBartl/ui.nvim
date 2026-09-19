---@module 'window-picker'
--- Compatibility shim for consumers that hardcode `require("window-picker")`
--- -- neo-tree's `open_with_window_picker` command chief among them
--- (`neo-tree.sources.common.commands`'s `use_window_picker`, which does
--- exactly `pcall(require, "window-picker")` then `picker.pick_window({})`).
--- Delegates to `ui.windowpicker`, which is where this plugin's own
--- configuration, defaults and tests live; this file exists only so a
--- call site written against `s1n7ax/nvim-window-picker`'s API keeps
--- working with that plugin uninstalled.

local windowpicker = require("ui.windowpicker")

local M = {}

---@param opts table|nil  Forwarded as-is; every known caller passes `{}`.
---@return integer|nil
function M.pick_window(opts)
  return windowpicker.pick(opts)
end

---@param opts table|nil
function M.setup(opts)
  windowpicker.setup(opts)
end

return M
