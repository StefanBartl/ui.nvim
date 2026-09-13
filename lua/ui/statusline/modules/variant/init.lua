---@module 'ui.statusline.modules.variant'
--- A segment with no plain-text equivalent in the catalog: the active
--- statusline variant's name, and a left click that opens a quick-switch
--- menu over every registered variant (`ui.config.variants.list()`), then
--- runs the existing `:UI variant <name>` command -- the runtime switch this
--- already has, not a second code path that could drift from it.

local clickable = require("ui.statusline.utils.clickable")

---@return string
local function render()
  local name = require("ui.config").get_variant()
  return " %#St_Lsp#" .. (name or "?") .. " "
end

--- Plain `vim.ui.select`, same reasoning as `git_clickable`'s branch switcher:
--- switching variants re-renders the whole statusline, not something to fire
--- per row on a live preview.
---@return nil
local function open_quick_switch()
  local variants = require("ui.config.variants")
  local names = variants.list()
  if #names == 0 then
    return
  end

  vim.ui.select(names, { prompt = "Statusline variant" }, function(choice)
    if choice then
      vim.cmd("UI variant " .. choice)
    end
  end)
end

return clickable.wrap(render, {
  l = open_quick_switch,
})
