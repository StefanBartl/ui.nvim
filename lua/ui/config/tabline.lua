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

  -- Target chip width in columns; also NvChad's own default.
  bufwidth = 21,

  -- "filetree" is `filetree.nvim`'s own filetype (this ecosystem's file
  -- tree), not NvChad's default "NvimTree" -- the tree_offset module reads
  -- this to reserve a blank strip the width of whichever tree window is
  -- open, so the buffer chips do not draw underneath it.
  tree_offset_ft = "filetree",
}
