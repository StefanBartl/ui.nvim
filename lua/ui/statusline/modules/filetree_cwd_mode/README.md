# ui.statusline.modules.filetree_cwd_mode

filetree.nvim's `cwd_mode` badge (PROJECT/PKG/LOCK/MANUAL/TREE, or whatever
`indicator.style` renders it as), read via filetree's external-statusline
API rather than its own tree-window badge. Requires
`features.cwd_mode.indicator.enabled = false` in the filetree.nvim spec.
