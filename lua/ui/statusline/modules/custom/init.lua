---@module 'ui.statusline.modules.custom'
--- Module with helper function for custom nvchad/ui/statusline

--- CDX: unused -- revival target. This subtree (init.lua, breadcrumbs/
--- helpers.lua, breadcrumbs/render.lua) has zero requires in lua/ or the
--- plugin repos (README.md: "currently unreferenced ... pending a closer
--- look"). Before wiring it in: breadcrumbs/render.lua calls M.repo_relative
--- / M.symbol_context / M.ellipsize_middle / M.stl_escape on its own module
--- table but never requires breadcrumbs/helpers.lua where those live, so
--- render_breadcrumbs() would nil-call. See docs/ROADMAP/CDX/config-cdx-triage.md §2.

local M = {}

return M
