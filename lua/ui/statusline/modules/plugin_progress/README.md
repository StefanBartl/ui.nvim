# ui.statusline.modules.plugin_progress

Statusline component for any plugin running a long operation. Reads
`lib.nvim.progress`'s "statusline" style, which is headless — it draws
nothing itself and instead keeps every in-flight operation's text in one
shared registry; this component is what actually renders it.
