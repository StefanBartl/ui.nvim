# ui.statusline.modules.plugin_summary

Statusline segment: how many plugins lazy.nvim manages, split into "own"
(the personal `StefanBartl/*.nvim` repos declared in `plugins.personal` —
the same canonical list `:MyPlugins clone`/`remove` use) and "external"
(everything else). The split is explicit by construction, so it can never
silently drift out of sync with the plugin list.
