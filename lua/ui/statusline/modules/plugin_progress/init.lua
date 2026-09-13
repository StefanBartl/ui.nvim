---@module 'ui.statusline.modules.plugin_progress'
--- Statusline component for any plugin running a long operation.
---
--- `lib.nvim.progress`'s "statusline" style is headless: it draws nothing and
--- instead keeps the text of every in-flight operation in one shared registry.
--- That registry is not per-plugin, so neither is this component — it shows
--- whatever is currently running in replacer.nvim, reposcope.nvim, sandbox.nvim,
--- github_stats.nvim, filetree.nvim, language.nvim, buffer-ctx.nvim, or the
--- `:MyReposUpdate`/`:MyPlugins clone`/`:MyPlugins remove` usercmds. Each entry
--- already carries its own plugin title (e.g. "[reposcope] updating 34
--- repositories"), so concurrent operations stay distinguishable without this
--- component knowing about any of them. A new plugin needs no change here,
--- only `progress_style = "statusline"` in its spec (see
--- lua/plugins/personal/init.lua) — or, for a usercmd, `style = "statusline"`
--- passed directly to `lib.nvim.progress.create` (see
--- lua/bindings/usrcmds/plugin_repos/init.lua, lua/bindings/usrcmds/update_repos/init.lua).

--- Operations can overlap — a `:Reposcope update` still running while a
--- `:Replace` starts. Rendering only the first would silently hide the rest, so
--- all of them are shown, oldest first (the registry's own order).
local SEPARATOR = " · "

return function()
  local ok, sl = pcall(require, "lib.nvim.progress.styles.statusline")
  if not ok then
    return ""
  end

  local active = sl.active() -- string[], oldest first
  if #active == 0 then
    return ""
  end

  -- St_LspProgress: blue while running.
  return " %#St_LspProgress#󰥩 " .. table.concat(active, SEPARATOR) .. " "
end
