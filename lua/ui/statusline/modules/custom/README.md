# ui.statusline.modules.custom

Helper functions for the custom NvChad/`ui` statusline; `breadcrumbs/` is
its one submodule (LSP/Treesitter-aware winbar breadcrumbs).

**Currently unreferenced.** None of the 6 live statusline variant files
(`ui/config/statusline/*.lua`) require this tree or
`modules/helpers/path.lua` — noted 2026-08-16 while triaging
`unreferenced-module` findings, left in place rather than deleted pending a
closer look at whether it should be wired back in or retired.
