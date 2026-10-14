---@module 'ui.statusline.modules.terminal_count'
--- terminal.nvim's terminals in the statusline: the name of the terminal the cursor is in with the
--- project's terminal count, or just the count when the cursor is elsewhere.
---
---   in terminal "build", 3 terminals     -> "build (3)"
---   in terminal "build", the only one    -> "build"
---   elsewhere, 2 terminals               -> "2 terminals"
---   no terminal, or terminal.nvim absent -> ""
---
--- terminal.nvim ships the data (`terminal.summary()`, documented in its docs/commands.md: registry
--- only, no multiplexer is asked, safe on every redraw) and this module formats it, so unlike the
--- thin requires next to it the wording lives here.

---@return string
return function()
  -- `package.loaded`, not `require`: this render function runs on the very first statusline
  -- redraw too -- a `require` here would pull terminal.nvim in before it gets to load on its own
  -- lazy trigger (see the identical comment in sandbox_ambient).
  local terminal = package.loaded["terminal"]
  if type(terminal) ~= "table" or type(terminal.summary) ~= "function" then
    return ""
  end
  local ok, summary = pcall(terminal.summary)
  if not ok or type(summary) ~= "table" or (summary.count or 0) < 1 then
    return ""
  end
  if summary.current then
    return summary.count > 1 and ("%s (%d)"):format(summary.current, summary.count)
      or summary.current
  end
  return ("%d terminal%s"):format(summary.count, summary.count == 1 and "" or "s")
end
