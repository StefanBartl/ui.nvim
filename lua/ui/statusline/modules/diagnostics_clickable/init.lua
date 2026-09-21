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
  -- Neither button was ever claimed for this module's own purposes, so both
  -- fall to the generic "manage this module" menu every plain segment gets
  -- automatically (ui.statusline.render's generic wrap) -- reached here
  -- explicitly since a module with its own click protocol never falls into
  -- that generic path.
  r = function()
    require("ui.statusline.menu").open("diagnostics_clickable")
  end,
  dbl = function()
    require("ui.statusline.menu").open("diagnostics_clickable")
  end,
})
