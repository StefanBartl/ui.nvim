---@module 'ui'
--- Entry point of ui.nvim: the statusline, tabline and theme layer.
---
--- `M.setup(opts)` turns on this plugin's own submodules selectively rather
--- than loading everything unconditionally -- `{ all = true }` is what a host
--- normally passes.
---
--- What it deliberately does NOT do is assemble the configuration. That is
--- `ui.config.setup()`, whose return value NvChad consumes through `chadrc`,
--- and it runs on a different schedule: `chadrc` is read while NvChad boots,
--- this is called afterwards. Folding the two together would mean the
--- keymaps had to exist before the theme did.
---
--- The shipped values live in `ui.config.DEFAULTS`.

local M = {}

--- Enable the selected submodules.
---@param opts Ui.Modules|nil
---@return nil
function M.setup(opts)
  opts = opts or {}

  if opts.all or opts.keymaps then
    require("ui.bindings.keymaps").setup({ all = true })
  end

  if opts.all or opts.usrcmds then
    require("ui.bindings.usrcmds").setup()
  end
end

return M
