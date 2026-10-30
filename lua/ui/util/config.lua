---@module 'ui.util.config'
--- The config store of a ui.nvim module: `lib.lua.config.new` with this
--- plugin's defaults for `name` and `notify`.
---
--- Every `setup()` of a module built on it starts from a fresh copy of the
--- module's DEFAULTS (an option an earlier call set and a later one leaves out
--- is back at its default), an unknown key gets a did-you-mean hint, a value
--- of the wrong type is left out so the default applies, and both are reported
--- once through `notify` and kept for `:checkhealth ui` (`issues()`).

local M = {}

--- The modules whose options go through this store, each exposing
--- `issues()`. `:checkhealth ui` asks the loaded ones.
---@type string[]
M.MODULES = {
  "ui.colorpicker",
  "ui.keys",
  "ui.menu",
  "ui.notify",
  "ui.vim_ui",
  "ui.windowpicker",
  "ui.zen",
}

---@param name string  module name, the prefix of every message (`"ui.zen"`)
---@param defaults table
---@param spec? Lib.Config.Spec  `name` and `notify` are filled in unless given
---@return Lib.Config.Instance
function M.new(name, defaults, spec)
  local full = {}
  for key, value in pairs(spec or {}) do
    full[key] = value
  end
  full.name = full.name or name
  full.notify = full.notify
    or function(message)
      require("lib.nvim.notify").create("[" .. name .. "]").warn(message)
    end
  return require("lib.lua.config").new(defaults, full)
end

return M
