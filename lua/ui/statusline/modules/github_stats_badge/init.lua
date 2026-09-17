---@module 'ui.statusline.modules.github_stats_badge'
--- github_stats.nvim's own ready-made statusline component: this week's
--- view count for the repository the current buffer sits in, e.g.
--- "42 views this week" (docs/statusline.md in github_stats.nvim).
---
--- Renders empty when github_stats.nvim is not installed, and empty again
--- for a buffer outside a tracked repository or with no traffic data yet --
--- that plugin's own `status()` already returns "" for every such case,
--- caches both the slug lookup and the count, and never raises, so this is
--- a thin require rather than a reimplementation.
---
--- It used to be the reimplementation: 106 lines here resolving the git
--- remote and reaching into `github_stats.analytics`/`github_stats.config`,
--- with its own TTL cache beside that plugin's own storage layer. Moved
--- into the plugin that owns the data (cross-feature report, finding E),
--- the same shape `sandbox_ambient` and `session_status` already had.

---@return string
return function()
  -- `package.loaded`, not `require`: this render function runs on the very
  -- first statusline redraw too -- a `require` here would pull
  -- github_stats.nvim in before it gets to load on its own lazy trigger
  -- (see the identical comment in filetree_cwd_mode's render function).
  local statusline = package.loaded["github_stats.statusline"]
  if type(statusline) ~= "table" then
    return ""
  end
  return statusline.status() or ""
end
