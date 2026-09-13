---@module 'ui.statusline.modules.diagnostics_clickable'
--- The catalog's plain `diagnostics` segment (`ui.statusline.utils.primitives
--- .diagnostics`), wrapped so a left click jumps to the next diagnostic in
--- the current buffer -- `vim.diagnostic.goto_next()`, the same jump `]d`
--- already runs, just reachable by mouse too.

local primitives = require("ui.statusline.utils.primitives")
local clickable = require("ui.statusline.utils.clickable")

return clickable.wrap(primitives.diagnostics, {
  l = function()
    vim.diagnostic.goto_next()
  end,
})
