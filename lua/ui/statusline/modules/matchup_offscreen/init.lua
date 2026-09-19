---@module 'ui.statusline.modules.matchup_offscreen'
--- vim-matchup's offscreen-match string, placed as one ordinary segment
--- instead of through vim-matchup's own `method = "status"`, which
--- overwrites `&l:statusline` wholesale for as long as the match stays
--- offscreen and restores the previous value afterward -- harmless for a
--- stock statusline, but it blanks out everything this plugin draws
--- (git/diagnostics/lsp/...) every time the cursor sits on a bracket whose
--- match scrolled out of view.
---
--- vim-matchup ships exactly the escape hatch this needs: `method =
--- "status_manual"` computes the same syntax-highlighted source-line string
--- (gutter stripped, `compact = 1`) but stashes it in the window-local
--- `w:matchup_statusline` instead of assigning `&l:statusline` -- see
--- `s:do_offscreen_statusline()` in vim-matchup's own
--- `autoload/matchup/matchparen.vim`. This module only reads that variable
--- back into a segment; the host config is what switches the method (see
--- `matchup_matchparen_offscreen` in the plugin spec).
---
--- Empty whenever nothing is offscreen -- vim-matchup unlets
--- `w:matchup_statusline` itself in `matchparen.clear()` -- and empty
--- outright without vim-matchup installed, or with a different `method`.
--- The string already carries its own `%#Group#` syntax-highlight markers
--- and ends in `%<%#Normal#` (vim-matchup's own truncation anchor), so it
--- is safe to splice into a larger statusline string unmodified.

---@return string
return function()
  local winid = vim.g.statusline_winid or vim.api.nvim_get_current_win()
  local ok, value = pcall(function()
    return vim.w[winid].matchup_statusline
  end)
  if not ok or not value or value == "" then
    return ""
  end
  return " " .. value
end
