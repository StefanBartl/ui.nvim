---@module 'ui.statusline.modules.recommender_badge'
--- "N Alias-Vorschläge für diese Datei offen" -- recommender.nvim's own
--- count of repeated dotted chains it would suggest aliasing in the CURRENT
--- buffer, without opening its suggestion float or typing `:Recommender`.
--- From IDEEN-statusline.md's "Segmente, die dieses Ökosystem einzigartig
--- machen" bucket -- corrected 2026-09-14 after the original idea (a
--- perf/security scanner with a `:RecommenderCheck` command) turned out not
--- to match what recommender.nvim actually does.
---
--- Renders empty when recommender.nvim is not installed, and empty again
--- when the buffer has zero suggestions at the plugin's own configured
--- analyzer/threshold/custom_aliases/blacklist (`recommender.config.get()`)
--- -- a badge with nothing to act on is just clutter.
---
--- The analysis result is cached per buffer, keyed by
--- `nvim_buf_get_changedtick` -- re-running the analyzer on every statusline
--- redraw would rescan the whole buffer for no reason between edits.

local Autocmd = require("lib.nvim.bindings.autocmd")
local primitives = require("ui.statusline.utils.primitives")

---@type table<integer, { tick: integer, count: integer }>
local cache = {}

Autocmd.create({ "BufDelete", "BufWipeout" }, function(args)
  cache[args.buf] = nil
end, {
  group = Autocmd.group("UiStatuslineRecommenderBadge", true),
  desc = "ui.statusline: forget a deleted buffer's recommender_badge cache",
})

---@param buf integer
---@return integer|nil # nil on any error (unknown analyzer, soft dep gone mid-session, ...)
local function suggestion_count(buf)
  -- `package.loaded`, not `require`: this runs from the render function on
  -- every statusline redraw, including the very first one -- a `require`
  -- here would pull recommender.nvim in before it gets to load on its own
  -- lazy trigger (see the identical fix/comment in filetree_cwd_mode's
  -- render function). The analyzer submodule below is only reached once
  -- `recommender.config` is confirmed already loaded, so that `require` is
  -- not a fresh eager-load of the plugin itself.
  local config = package.loaded["recommender.config"]
  if type(config) ~= "table" then
    return nil
  end

  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local cached = cache[buf]
  if cached and cached.tick == tick then
    return cached.count
  end

  local cfg = config.get()
  local ok_analyzer, analyzer =
    pcall(require, "recommender.analyzers." .. (cfg.analyzer or "regex"))
  if not ok_analyzer then
    return nil
  end

  local suggestions
  vim.api.nvim_buf_call(buf, function()
    suggestions = analyzer.analyze(cfg.threshold, cfg.custom_aliases, cfg.blacklist)
  end)

  local count = #suggestions
  cache[buf] = { tick = tick, count = count }
  return count
end

---@return string
return function()
  local count = suggestion_count(primitives.stbufnr())
  if not count or count == 0 then
    return ""
  end

  local label = count == 1 and "Alias-Vorschlag" or "Alias-Vorschläge"
  return (" %d %s für diese Datei offen "):format(count, label)
end
