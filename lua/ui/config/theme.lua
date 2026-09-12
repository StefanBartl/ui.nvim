---@module 'ui.config.theme'
--- What `:UI theme`/`:UI toggle`/`:UI transparency` need as configuration --
--- not "which colorscheme to boot into". This plugin does not apply a
--- startup colorscheme; the host's own init.lua does that, the same way any
--- Neovim config picks one (`vim.cmd.colorscheme(...)`), independent of this
--- plugin entirely.
---
--- Was `ui.config.base46`, and carried a `theme` field NvChad's own
--- chadrc.lua read to bootstrap Base46 at startup. Step 6 of the roadmap
--- dropped that field along with base46 itself: nothing here applies a
--- startup colorscheme any more, so there is nothing for a `theme` field to
--- feed.
---
--- `theme_toggle` used to name two base46 theme keys ("vim_default" was one
--- of them, not a real colorscheme). Real `:colorscheme` switching needs
--- real colorscheme names -- "default" (Neovim's own, always present) and
--- "tokyonight" (already the host's active theme).

return {
  transparency = false,
  theme_toggle = { "default", "tokyonight" },
}
