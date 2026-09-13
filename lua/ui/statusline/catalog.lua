---@module 'ui.statusline.catalog'
--- A plain data list of every statusline segment this plugin ships, so a
--- host can pick modules rather than write them from scratch -- not a new
--- abstraction over `order`/`modules`, just a lookup table both `:UI
--- modules` and `docs/modules.md` read from, so the two can't drift apart.
--- Writing a module by hand stays exactly as possible as before; this only
--- makes "which ones already exist" answerable without reading source.
---
--- Deliberately excludes `ui.statusline.modules.neotest_module` -- already
--- documented elsewhere as dead code with a real bug (calls a function that
--- was never `require`d), unreferenced by any shipped preset. A catalog
--- entry would be an offer to use something that does not work.

---@class Ui.Statusline.CatalogEntry
---@field key string # the `order`/`modules` key this segment renders under
---@field summary string # one-line description, shown by `:UI modules` and in docs/modules.md
---@field builtin boolean # true = part of `ui.statusline.themes.default`, resolves in any preset's `order` with no `modules` entry needed
---@field source string|nil # require path for a standalone module; nil for a builtin one
---@field requires string|nil # a soft dependency this segment renders empty without; nil if it has none
---@field used_by string[] # shipped preset names that include this key by default; empty means opt-in only

---@type Ui.Statusline.CatalogEntry[]
return {
  -- Built into the "default" fallback theme (ui.statusline.themes.default)
  -- -- add the key to any preset's own `order`, no `modules` entry needed
  -- unless you want to override how it renders.
  {
    key = "mode",
    summary = "Current Vim mode, as a filled colour chip.",
    builtin = true,
    used_by = { "default", "minimal", "lsp", "blocks" },
  },
  {
    key = "file",
    summary = "File name and devicon.",
    builtin = true,
    used_by = { "default" },
  },
  {
    key = "git",
    summary = "Branch name plus added/changed/removed counts.",
    requires = "gitsigns.nvim",
    builtin = true,
    used_by = { "default", "minimal", "blocks" },
  },
  {
    key = "lsp_msg",
    summary = "Live LSP progress message (hidden below 120 columns).",
    builtin = true,
    used_by = { "default" },
  },
  {
    key = "diagnostics",
    summary = "Per-severity error/warn/hint/info counts.",
    builtin = true,
    used_by = { "default", "minimal", "lsp", "blocks" },
  },
  {
    key = "lsp",
    summary = "Name of the attached LSP client.",
    builtin = true,
    used_by = { "default", "minimal", "lsp", "blocks" },
  },
  {
    key = "cwd",
    summary = "Current working directory's basename (hidden below 85 columns).",
    builtin = true,
    used_by = { "default", "minimal" },
  },
  {
    key = "cursor",
    summary = "Line/column position; several presets add a row/column scroll-progress bar via ui.statusline.cursor_ctl.",
    builtin = true,
    used_by = { "default", "minimal", "lsp", "blocks" },
  },

  -- Standalone modules -- add the key to your own `order`, and a `modules`
  -- entry calling it (see docs/modules.md for the exact snippet).
  {
    key = "plugin_progress",
    summary = "Whichever plugin is currently running a long operation (lib.nvim.progress).",
    builtin = false,
    source = "ui.statusline.modules.plugin_progress",
    used_by = { "default" },
  },
  {
    key = "plugin_summary",
    summary = 'lazy.nvim\'s own/external plugin count, e.g. "12/48".',
    builtin = false,
    source = "ui.statusline.modules.plugin_summary",
    used_by = {},
  },
  {
    key = "casedesk",
    summary = "Current case's short info (number, company, reply count) plus an SLA badge.",
    requires = "casedesk.nvim",
    builtin = false,
    source = "ui.statusline.modules.casedesk",
    used_by = {},
  },
  {
    key = "filetree_cwd_mode",
    summary = "filetree.nvim's cwd-mode badge (PROJECT/LOCK/MANUAL/...), as a filled capsule.",
    requires = "filetree.nvim",
    builtin = false,
    source = "ui.statusline.modules.filetree_cwd_mode",
    used_by = {},
  },
  {
    key = "undo_depth",
    summary = "Undo steps available on the current branch, plus a glyph if the undo tree has branched.",
    builtin = false,
    source = "ui.statusline.modules.undo_depth",
    used_by = {},
  },
  {
    key = "search_count",
    summary = "[current/total] match position while hlsearch is active.",
    builtin = false,
    source = "ui.statusline.modules.search_count",
    used_by = {},
  },
  {
    key = "breadcrumbs",
    summary = "Repo-relative path + LSP/Treesitter symbol context, mode-band coloured.",
    builtin = false,
    source = "ui.statusline.modules.lsp",
    used_by = {},
  },
}
