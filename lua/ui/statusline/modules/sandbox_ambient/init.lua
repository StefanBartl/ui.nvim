---@module 'ui.statusline.modules.sandbox_ambient'
--- sandbox.nvim's own ready-made statusline component: an ambient
--- "engine (running/total)" summary, e.g. "docker (2/5)"
--- (docs/statusline.md in sandbox.nvim).
---
--- Renders empty when sandbox.nvim is not installed, and empty again when no
--- engine is configured or reachable -- sandbox.nvim's own `status()`
--- already returns "" for both cases, degrades rather than errors, and
--- caches/rate-limits its own engine polling (stale-while-revalidate, see
--- sandbox.nvim's docs), so this is a thin require rather than a
--- reimplementation.

---@return string
return function()
  local ok, statusline = pcall(require, "sandbox.statusline")
  if not ok then
    return ""
  end
  return statusline.status() or ""
end
