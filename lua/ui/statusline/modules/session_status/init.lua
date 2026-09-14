---@module 'ui.statusline.modules.session_status'
--- sessions.nvim's own ready-made statusline component: the active session
--- name, with a dirty marker appended when the window/buffer layout has
--- changed since the last save or load (docs/statusline.md in sessions.nvim).
---
--- Renders empty when sessions.nvim is not installed, and empty again when
--- no session is active -- sessions.nvim's own `component()` already
--- returns "" for both cases and is documented safe to call unconditionally
--- on every redraw, so this is a thin require rather than a
--- reimplementation: no caching or error handling happens here because
--- `sessions.statusline` already did it on its side.

---@return string
return function()
  local ok, statusline = pcall(require, "sessions.statusline")
  if not ok then
    return ""
  end
  return statusline.component() or ""
end
