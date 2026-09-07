---@module 'ui.config.statusline.base'
--- Minimal custom statusline with cursor, cwd, and progress

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
