---@module 'ui.statusline.modules.search_count'
--- "[7/23]" -- current/total match position while `hlsearch` is active.
--- `searchcount()` already computes this on every search; Vim's own
--- command-line echo is normally the only place it shows, and that message
--- clears itself as soon as anything else is echoed. Not wired into any
--- shipped preset -- opt in by adding "search_count" to a host's own
--- `order` and this module to `modules`.

---@return string
return function()
  if vim.v.hlsearch == 0 then
    return ""
  end

  -- `timeout` caps how long searchcount may scan for a match count on a
  -- large buffer -- a short timeout degrading to "" is preferable to a
  -- statusline redraw stalling on a pathological search pattern.
  local ok, result = pcall(vim.fn.searchcount, { maxcount = 0, timeout = 100 })
  if not ok or type(result) ~= "table" or not result.total or result.total == 0 then
    return ""
  end

  -- `incomplete ~= 0` means the count above hit the timeout or a maxcount
  -- cap rather than finishing a real scan -- "+" says the total may be
  -- higher than shown, rather than presenting a capped number as exact.
  local total = tostring(result.total) .. ((result.incomplete ~= 0) and "+" or "")
  return " %#St_Lsp#[" .. result.current .. "/" .. total .. "] "
end
