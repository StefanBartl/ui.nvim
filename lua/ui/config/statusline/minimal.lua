---@module 'ui.config.statusline.minimal'
--- Minimal generic preset: cursor, cwd, and progress. Was "base".
---
--- Naming note: this is a preset NAME (`Ui.StatuslineVariant`), unrelated to
--- the "minimal" fallback module-SET name some `Ui.Statusline.Config.theme`
--- values reference (`ui.statusline.themes.*`, of which only "default" is
--- actually ported -- see `ui.statusline.render`'s doc comment). Same word,
--- two different, never-compared namespaces; this preset does not set
--- `theme = "minimal"` anywhere, and does not need to.

local M = {}

M.ui = {
  statusline = {
    order = { "mode", "git", "%=", "cwd", "%=", "diagnostics", "lsp", "cursor", "progress" },

    modules = {
      --- @return string
      cursor = function()
        local ok_r, renderer = pcall(require, "ui.statusline.cursor_ctl.renderer")
        local ok_p, pct = pcall(require, "ui.statusline.cursor_ctl.progress_calculators")

        if not ok_r then
          return " Ln %l, Col %v "
        end

        local parts = { renderer.cursor_classic() }

        if ok_p then
          parts[#parts + 1] = renderer.pct_token(pct.compute_row_pct(), "R")
        end

        return table.concat(parts, "")
      end,

      --- @return string
      cwd = function()
        return vim.fn.getcwd()
      end,

      --- @return string
      progress = function()
        return "" -- Progress is integrated in cursor module
      end,
    },
  },
}

return M
