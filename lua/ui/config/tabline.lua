---@module 'ui.config.tabline'
--- Shipped tabline defaults -- `ui.config.setup()`'s `ui.tabline` half,
--- alongside `ui.config.statusline`'s variant selection. One config, not a
--- choice of presets: the four built-in modules
--- (`ui.tabline.modules`) already are the only shipped `order`; a host
--- wanting different segments overrides `order`/`modules` directly (see
--- `ui.config.setup`'s `user_opts.tabline`), the same "bring your own"
--- shape the statusline's `opts.variant` table form uses.
---
---@type Ui.Tabline.Config
return {
  order = { "tree_offset", "buffers", "tabs", "btns" },

  -- `bufwidth` deliberately left unset: `ui.tabline.modules.buffers` then
  -- computes a chip width from the available space and the open-buffer
  -- count instead of a fixed 21 columns (NvChad's own default, and this
  -- plugin's own behaviour before this became configurable) -- a fixed
  -- width leaves a leftover strip too narrow for one more chip whenever the
  -- buffer count doesn't divide the bar evenly. Set `bufwidth` here to pin
  -- the old fixed-width behaviour back; `bufwidth_min`/`bufwidth_max`
  -- (default 12/24) bound the auto-computed width instead.

  -- "filetree" is `filetree.nvim`'s own filetype (this ecosystem's file
  -- tree), not NvChad's default "NvimTree" -- the tree_offset module reads
  -- this to reserve a blank strip the width of whichever tree window is
  -- open, so the buffer chips do not draw underneath it.
  tree_offset_ft = "filetree",

  -- `style` deliberately left unset too -- `ui.tabline.modules.buffers`
  -- falls back to "rounded" (a cap between every pair of chips, square only
  -- where the visible run actually meets an edge). Set to "square" for
  -- chips flush against each other with no boundary decoration, or
  -- "divider" for a plain vertical bar between them instead of rounding.
}
