---@module 'ui.util.soft_require'
--- Single place that `pcall`s `require()` for a foreign, optional plugin.
---
--- None of nvim-web-devicons, nvzone/menu, casedesk.nvim, recommender.nvim,
--- runtime-analysis.nvim, sandbox.nvim, sessions.nvim, github_stats.nvim,
--- filetree.nvim or lazy.nvim are hard dependencies of ui.nvim -- their
--- absence is the ordinary standalone case, not an error. Routing every
--- soft-dependency call site through here means there is exactly one place
--- that decides what "soft dependency present" means, and one place a health
--- check can ask.
---
--- The sibling `my.nvim` grew the same module out of its `rules.nvim` pass
--- (`PRIN-07`); this is the matching half, and the cross-feature report's C4.
---
--- The reason it is worth more than tidiness: `nvim-treesitter.ts_utils` was
--- probed exactly this way from the statusline's Tree-sitter breadcrumb
--- fallback, nvim-treesitter deleted that module upstream, and the probe
--- answered "absent" forever. The feature went quiet in every session with
--- no error anywhere. A `pcall` scattered across twelve files cannot be
--- audited; `M.report()` below can, and `:checkhealth ui` prints it.
---
--- No memoization: `require()` already consults `package.loaded`, so a
--- second call is a table lookup once a module has loaded, and a lazily
--- loaded plugin can turn from absent to present later in the same session.
--- A cache of our own would either duplicate that lookup or freeze a "not
--- loaded yet" miss as "never available".

local M = {}

--- The foreign modules this plugin probes, for `M.report()`. Kept as data
--- rather than discovered by grepping at runtime: a module that no longer
--- exists upstream is exactly the case this is meant to surface, and a
--- discovered list would simply stop mentioning it.
---
--- `optional_for` is what degrades when the module is missing -- the health
--- output is only useful if it says what the user loses.
---@type { mod: string, optional_for: string }[]
M.PROBED = {
  { mod = "nvim-web-devicons", optional_for = "file icons in the statusline and tabline" },
  { mod = "menu", optional_for = "nvzone/menu as the context-menu renderer" },
  { mod = "lazy", optional_for = "the plugin-count segment" },
  { mod = "casedesk.sla", optional_for = "the casedesk SLA badge" },
  { mod = "casedesk.config", optional_for = "the casedesk segment" },
  { mod = "runtime-analysis.telemetry", optional_for = "the runtime-analysis traffic light" },
  { mod = "sandbox.statusline", optional_for = "the sandbox engine summary" },
  { mod = "sessions.statusline", optional_for = "the session-status segment" },
  { mod = "github_stats.analytics", optional_for = "the github-stats view badge" },
  { mod = "filetree", optional_for = "the filetree cwd-mode segment" },
  {
    mod = "my.hl_config.breadcrumbs.ctx.providers.lsp_symbols",
    optional_for = "LSP symbols in the breadcrumb (Tree-sitter only without it)",
  },
}

--- The module, or nil when it is not installed.
---
--- The `type(mod) == "table"` check is not redundant with `ok`: a module
--- that returns a boolean or nothing at all still loads successfully, and
--- every caller here goes on to index the result.
---@param name string # module path, e.g. "nvim-web-devicons"
---@return table|nil
function M.try(name)
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then
    return mod
  end
  return nil
end

--- Which of `M.PROBED` currently resolve. Consumed by `ui.health`.
---
--- A miss is not a failure -- it is the standalone case -- so this returns
--- data rather than notifying. Reading it is also the only way to notice a
--- soft dependency that has rotted away upstream rather than being
--- deliberately uninstalled.
---@return { mod: string, optional_for: string, present: boolean }[]
function M.report()
  local out = {}
  for i, entry in ipairs(M.PROBED) do
    out[i] = {
      mod = entry.mod,
      optional_for = entry.optional_for,
      present = M.try(entry.mod) ~= nil,
    }
  end
  return out
end

return M
