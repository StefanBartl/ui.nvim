---@module 'ui.config.DEFAULTS'
--- Everything this plugin ships as a default, in one place (NEW-07).
---
--- Three groups, and they are read at different times, which is why they are
--- named apart rather than merged into one flat table:
---
---   * `theme` — transparency default and the pair `:UI toggle` swaps
---     between. Read by `ui.config.setup`, and by `ui.bindings.usrcmds.themes`
---     directly for the toggle pair (via `ui.config.last()` when a host
---     override is active, this table otherwise).
---   * `statusline` — which of the four shipped presets is assembled. Read
---     on the same path, one step later.
---   * `tabline` — the buffer/tab bar's `order`/`modules`/`bufwidth`/
---     `tree_offset_ft`. One shipped config, not a choice of presets like
---     `statusline` -- see `ui.config.tabline`'s own doc comment.
---
--- `modules` is the on/off list `ui.setup(opts)` walks. It is here rather than
--- inline in `init.lua` so that "what does this plugin turn on" has the same
--- answer whether you read the code or the defaults.
---
--- These tables are **not** the live configuration, unlike the sibling plugin's
--- registry: nothing mutates them at runtime. `:UI theme` calls `:colorscheme`
--- and reads `vim.g.colors_name` back, not through here — which is also why
--- there is no `reset` to build on top.

---@type Ui.Defaults
return {
  theme = require("ui.config.theme"),

  statusline = {
    -- The variant `ui.config` assembles. `ui.config.STATUSLINE_VARIANT` is
    -- still the switch the code reads; this records the shipped value so a
    -- reader does not have to find that assignment to learn it.
    ---@type Ui.StatuslineVariant
    variant = "default",
  },

  ---@type Ui.Tabline.Config
  tabline = require("ui.config.tabline"),

  --- What `ui.setup(opts)` enables. `all = true` is the shorthand the host
  --- uses; the individual flags exist so one half can be left out.
  modules = {
    all = false,
    keymaps = false,
    usrcmds = false,
    context = false,
  },
}
