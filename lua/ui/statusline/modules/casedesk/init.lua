---@module 'ui.statusline.modules.casedesk'
--- casedesk.nvim's own ready-made statusline component: the current case's
--- short number, company and reply count, plus an SLA badge when a clock
--- is urgent (docs/statusline.md in casedesk.nvim).
---
--- Renders empty when casedesk.nvim is not installed, and empty again when
--- the focused buffer is not inside a known case -- that plugin's own
--- `status()` already returns "" for both, caches by buffer name and a
--- coarse time bucket, and never raises, so this is a thin require rather
--- than a reimplementation.
---
--- It used to be the reimplementation: 169 lines here reaching into
--- `casedesk.resolve`, `casedesk.meta`, `casedesk.sla` and
--- `casedesk.config`, and re-stating four of that plugin's own design
--- decisions -- which priorities get a badge, that it stays hidden until
--- urgent, where the overdue line falls, which highlight groups to reuse.
--- Moved to where those decisions belong (cross-feature report, finding
--- E), the same shape `sandbox_ambient` and `session_status` already had.

---@return string
return function()
  -- `package.loaded`, not `require`: this render function runs on the very
  -- first statusline redraw too -- a `require` here would pull
  -- casedesk.nvim in before it gets to load on its own lazy trigger (see
  -- the identical comment in filetree_cwd_mode's render function).
  local statusline = package.loaded["casedesk.statusline"]
  if type(statusline) ~= "table" then
    return ""
  end
  return statusline.status() or ""
end
