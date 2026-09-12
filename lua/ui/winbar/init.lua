---@module 'ui.winbar'
--- Owns `vim.wo.winbar` -- frame, not content. Mirrors the ownership pattern
--- `my.nvim`/`lsp.nvim` already use for `vim.diagnostic.config()`: the
--- content-producing plugin (my.nvim's `hl_config.breadcrumbs`, or any other)
--- keeps building the string and its own refresh timing, and hands the
--- result to `M.set()` when this module is present; it self-applies
--- (`vim.wo.winbar = line` directly) when it isn't, so it keeps working
--- standalone. Neither plugin can assume the other is there.
---
--- What actually moved here from the content side is only the final write --
--- the "where is this drawn, and is the window still valid by the time a
--- debounced call fires" question, which is a frame concern by this
--- repository's own dividing line. Debouncing, skip-rules (which buffers get
--- a winbar at all) and the breadcrumb content itself stay the content
--- layer's job; this module has no opinion on any of that.

local M = {}

--- Set the winbar text for a window (default: the current one).
---
--- Scheduled and re-validated rather than applied immediately: the caller is
--- typically a debounced callback, and the window it was scheduled for can
--- close (or stop being the active one) before the callback runs.
---@param line string
---@param winid? integer
---@return nil
function M.set(line, winid)
  winid = winid or vim.api.nvim_get_current_win()
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(winid) then
      vim.wo[winid].winbar = line
    end
  end)
end

return M
