---@module 'ui.statusline.modules.recommender_badge'
--- recommender.nvim's own ready-made statusline component: how many alias
--- suggestions are open for the current buffer, e.g.
--- "3 alias suggestions open for this file"
--- (docs/statusline.md in recommender.nvim).
---
--- Renders empty when recommender.nvim is not installed, and empty again
--- when the buffer has nothing to suggest -- recommender.nvim's own
--- `status()` already returns "" for both cases, caches its analysis per
--- buffer against `changedtick`, and never raises, so this is a thin
--- require rather than a reimplementation.
---
--- It used to be the reimplementation: 79 lines here reaching into
--- `recommender.config` and `recommender.analyzers.*`, which would have
--- broken silently the moment either was renamed. Moved into the plugin
--- that owns the data (cross-feature report, finding E), the same shape
--- `sandbox_ambient` and `session_status` already had.

---@return string
return function()
  -- `package.loaded`, not `require`: this render function runs on the very
  -- first statusline redraw too -- a `require` here would pull
  -- recommender.nvim in before it gets to load on its own lazy trigger
  -- (see the identical comment in filetree_cwd_mode's render function).
  local statusline = package.loaded["recommender.statusline"]
  if type(statusline) ~= "table" then
    return ""
  end
  return statusline.status() or ""
end
