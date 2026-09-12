---@module 'ui.config.variants'
--- Registry of statusline variants by name: the four shipped presets,
--- registered lazily below, plus whatever a host registers from its own
--- config via `M.register()`. `ui.config.setup({ variant = "name" })` and
--- `:UI variant`/`:UI variants` both read this -- one place answers "what
--- can I switch to by name" instead of two (a name-based require lookup for
--- shipped presets, a raw table for everything else).
---
--- Existed only as the raw-table half before this: `ui.config.setup({
--- variant = <table> })` (see docs/examples/personal-statusline-example.lua)
--- worked, but a table has no name, so it could not be listed or completed
--- over. `M.register(name, variant)` is what lets a host's own statusline
--- module show up in `:UI variant <Tab>` next to the shipped four.

local M = {}

---@alias Ui.Config.VariantEntry table|fun():table

---@type table<string, Ui.Config.VariantEntry>
local _registry = {}

--- The four shipped presets, registered as lazy loaders rather than required
--- eagerly here: picking one must not pull in the segment modules every
--- OTHER preset needs just because this module was loaded.
local BUILTIN = { "default", "minimal", "lsp", "blocks" }
for _, name in ipairs(BUILTIN) do
  _registry[name] = function()
    return require("ui.config.statusline." .. name)
  end
end

---Register a variant under `name` -- a host's own statusline module,
---typically. `variant` is either the built table (the same shape any file
---under `lua/ui/config/statusline/` returns: `{ ui = {...}, setup? = fn }`)
---or a zero-arg function returning one, for lazy loading.
---
---Registering under one of the four shipped names replaces it for the rest
---of the session -- deliberate, not guarded: a host that wants to override
---what "default" means is making an explicit choice, not colliding by
---accident.
---@param name string
---@param variant Ui.Config.VariantEntry
---@return nil
function M.register(name, variant)
  _registry[name] = variant
end

---Remove a registered variant. No-op if `name` was never registered.
---@param name string
---@return nil
function M.unregister(name)
  _registry[name] = nil
end

---Every registered name, sorted -- shipped presets and host-registered ones
---alike. What `:UI variant <Tab>` completes over.
---@return string[]
function M.list()
  local names = {}
  for name in pairs(_registry) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

---Whether `name` is registered (built-in or host-added).
---@param name string
---@return boolean
function M.exists(name)
  return _registry[name] ~= nil
end

---Resolve a registered name to its variant table. `nil` if `name` was never
---registered.
---@param name string
---@return table?
function M.resolve(name)
  local entry = _registry[name]
  if entry == nil then
    return nil
  end
  if type(entry) == "function" then
    return entry()
  end
  return entry
end

return M
