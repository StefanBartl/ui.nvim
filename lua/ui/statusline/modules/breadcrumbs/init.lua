---@module 'ui.statusline.modules.breadcrumbs'
--- The `breadcrumbs` segment as a ready-made module: repo-relative path +
--- LSP/Tree-sitter symbol context, coloured by the current mode band.
---
--- `ui.statusline.modules.lsp` is the API behind it (a table of helpers),
--- not a segment itself -- `ui.statusline.render.generate()` only renders a
--- function or a string, so the catalog entry `breadcrumbs` points here and
--- "Add module" / a saved layout gets something it can actually call. This
--- is the module docs/modules.md points the `breadcrumbs` key at.

---@return string
return function()
  local lsp = require("ui.statusline.modules.lsp")
  local band = lsp.mode_band_group()
  local content = lsp.render_breadcrumbs_inherit_lspfirst(band)
  if not content or content == "" then
    return ""
  end
  return lsp.hl_open(band) .. content
end
