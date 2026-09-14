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
  -- `package.loaded`, not `require`: this render function runs on the very
  -- first statusline redraw too -- a `require` here would pull
  -- sessions.nvim in before it gets to load on its own lazy trigger (see
  -- the identical fix/comment in filetree_cwd_mode's render function).
  local statusline = package.loaded["sessions.statusline"]
  if type(statusline) ~= "table" then
    return ""
  end
  return statusline.component() or ""
end
