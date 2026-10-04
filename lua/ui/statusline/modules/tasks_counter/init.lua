---@module 'ui.statusline.modules.tasks_counter'
--- "T:7" -- how many open tasks the project in the cwd has, read from the
--- wkdbook task vault (`<area>/ROADMAP/TASKS.md`, or the `tasks/*.md` files
--- when no overview exists). Optionally broken down: "T:7 P1:2 B:1" (two
--- urgent, one blocked).
---
--- Opt-in, not wired into any shipped preset: add "tasks_counter" to a
--- host's own `order` and this module to `modules`. No hard dependency on
--- the nvim-config task engine -- the data source is the vault's Markdown
--- files, pluggable through `source`; without a vault or without an area
--- for the cwd the segment is simply empty.
---
--- It never blocks: the files are read asynchronously (`vim.uv`), the
--- result is cached for `ttl_ms` and dropped on `DirChanged`; a redraw only
--- reads that cache. Options live in `ui.statusline.modules.tasks_counter
--- .config` (`DEFAULTS`, `setup`); the implementation is in `.core`.

---@return string
return function()
  return require("ui.statusline.modules.tasks_counter.core").render()
end
