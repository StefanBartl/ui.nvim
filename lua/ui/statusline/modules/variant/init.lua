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

-- Right click, not `dbl`: Neovim's click protocol calls this function once
-- per physical click (`clicks` names which one it was), not once per
-- completed gesture -- the first click of a double click still fires with
-- clicks == 1 before the second arrives with clicks == 2 (the "map both
-- <LeftMouse> and <2-LeftMouse> and BOTH fire" gotcha, here in the
-- statusline click protocol's own numbering). A `dbl` handler here would
-- have opened `ui.statusline.menu` on top of the `vim.ui.select`
-- quick-switch `open_quick_switch` (this module's own `l`) just opened for
-- that same gesture's first click. Right click reaches the same menu
-- without that collision, so double click is left to just run `l` again --
-- redundant with a plain second click, never two floats fighting over one
-- gesture.
return clickable.wrap(render, {
  l = open_quick_switch,
  r = function()
    require("ui.statusline.menu").open("variant")
  end,
})
