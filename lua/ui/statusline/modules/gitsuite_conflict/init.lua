---@module 'ui.statusline.modules.gitsuite_conflict'
--- gitsuite.nvim's own ready-made statusline component: an ambient
--- merge-conflict indicator for the current buffer, e.g. "MERGE 2"
--- (docs/statusline.md in gitsuite.nvim).
---
--- Renders empty when gitsuite.nvim is not installed, and empty again when
--- the buffer has no conflicts -- gitsuite's own `status()` already returns
--- "" for both cases and is documented safe to call unconditionally on
--- every redraw, so this is a thin require rather than a reimplementation:
--- no caching or error handling happens here because `gitsuite.statusline`
--- already did it on its side (cached by `nvim_buf_get_changedtick`).

---@return string
return function()
  -- `package.loaded`, not `require`: this render function runs on the very
  -- first statusline redraw too -- a `require` here would pull
  -- gitsuite.nvim in before it gets to load on its own lazy trigger (see
  -- the identical fix/comment in filetree_cwd_mode's render function).
  local statusline = package.loaded["gitsuite.statusline"]
  if type(statusline) ~= "table" then
    return ""
  end
  return statusline.status() or ""
end
