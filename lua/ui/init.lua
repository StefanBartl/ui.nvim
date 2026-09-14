---@module 'ui'
--- Entry point of ui.nvim: the statusline, tabline and theme layer.
---
--- `M.setup(opts)` turns on this plugin's own submodules selectively rather
--- than loading everything unconditionally -- `{ all = true }` turns both on
--- with every default; `{ keymaps = true, usrcmds = true }` does the same
--- without the shorthand.
---
--- What it deliberately does NOT do is assemble the configuration. That is
--- `ui.config.setup()`, whose return value NvChad consumes through `chadrc`,
--- and it runs on a different schedule: `chadrc` is read while NvChad boots,
--- this is called afterwards. Folding the two together would mean the
--- keymaps had to exist before the theme did.
---
--- The shipped values live in `ui.config.DEFAULTS`.

local notify = require("lib.nvim.notify").create("[ui]")

local M = {}

--- Enable the selected submodules.
---
--- `opts.keymaps` turns the keymaps submodule on at all -- pass `true` (or
--- rely on `opts.all`) for every shipped keymap at its default, or a
--- `Ui.Keymaps.Keys` table (`{ next = "<C-Right>", close = false }`) to
--- remap or drop individual ones; either form is handed straight to
--- `ui.bindings.keymaps.setup()`, which is the thing that actually knows
--- what "default" means for each action -- see that module's own doc
--- comment.
---
--- `opts.menu` is the odd one out here, opt-OUT rather than opt-in: pass
--- `false` to disable `ui.contextmenu`'s renderer/trigger (`open`/
--- `bind_buffer`) -- omitting it, or `opts.all`, leaves the menu at its
--- already-working default rather than needing to ask for it.
---@param opts Ui.Modules|nil
---@return nil
function M.setup(opts)
  opts = opts or {}

  -- Each of the three below is pcall'd on its own: they wire up unrelated
  -- submodules, so one failing (a bad opts.keymaps table, a submodule's own
  -- setup error) must not also skip the other two.
  if opts.all or opts.keymaps then
    local ok, err = pcall(require("ui.bindings.keymaps").setup, opts.keymaps)
    if not ok then
      notify.error("keymaps setup failed: " .. tostring(err))
    end
  end

  if opts.all or opts.usrcmds then
    local ok, err = pcall(require("ui.bindings.usrcmds").setup)
    if not ok then
      notify.error("usrcmds setup failed: " .. tostring(err))
    end
  end

  -- Opt-OUT, unlike keymaps/usrcmds above: the context-menu renderer/trigger
  -- already work today with no setup call at all, so there is nothing for
  -- `opts.all`/an absent `opts.menu` to turn on here -- only an explicit
  -- `menu = false` does anything, per the semantics decided in
  -- `PLAN-ui-kit-migration.md` (data builders always available, only
  -- render/trigger gated). See `ui.contextmenu.set_enabled`'s own doc
  -- comment.
  if opts.menu == false then
    local ok, err = pcall(require("ui.contextmenu").set_enabled, false)
    if not ok then
      notify.error("contextmenu set_enabled(false) failed: " .. tostring(err))
    end
  end
end

return M
