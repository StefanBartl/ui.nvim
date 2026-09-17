---@module 'ui.statusline.modules.runtime_analysis_ampel'
--- runtime-analysis.nvim's own ready-made statusline component: one
--- traffic light for whether anything instrumented looks unhealthy today
--- (docs/statusline.md in runtime-analysis.nvim).
---
--- Renders empty when runtime-analysis.nvim is not installed, and empty
--- again when nothing has ever wrapped or started a telemetry instance --
--- that plugin's own `status()` already returns "" for both, caches its
--- on-disk reads, and never raises, so this is a thin require rather than
--- a reimplementation.
---
--- It used to be the reimplementation: 140 lines here deciding what counts
--- as slow, what "today" means and which glyph to show -- that plugin's own
--- opinion about its own data, living in this repository with no test over
--- there to hold it. Moved to where the data is (cross-feature report,
--- finding E), the same shape `sandbox_ambient` and `session_status`
--- already had.

---@return string
return function()
  -- `package.loaded`, not `require`: this render function runs on the very
  -- first statusline redraw too -- a `require` here would pull
  -- runtime-analysis.nvim in before it gets to load on its own lazy
  -- trigger (see the identical comment in filetree_cwd_mode's render).
  local statusline = package.loaded["runtime-analysis.statusline"]
  if type(statusline) ~= "table" then
    return ""
  end
  return statusline.status() or ""
end
