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
---
--- `opts.keymaps` is either `true` (every default keymap, same as before) or
--- a `Ui.Keymaps.Modules` table for per-group (`buffers`/`tabs`) or per-key
--- (`keys.next = false`, `keys.close = "<leader>x"`, ...) control -- see that
--- type's own doc comment.
---@param opts Ui.Modules|nil
---@return nil
function M.setup(opts)
  opts = opts or {}

  if opts.all or opts.keymaps then
    local keymaps_opts = opts.keymaps
    if keymaps_opts == true or opts.all then
      keymaps_opts = vim.tbl_deep_extend(
        "force",
        { all = true },
        type(keymaps_opts) == "table" and keymaps_opts or {}
      )
    end
    require("ui.bindings.keymaps").setup(keymaps_opts)
  end

  if opts.all or opts.usrcmds then
    require("ui.bindings.usrcmds").setup()
  end
end

return M
