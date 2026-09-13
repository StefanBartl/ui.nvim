---@module 'ui.statusline.modules.github_stats_badge'
--- "👁 42 diese Woche" -- github_stats.nvim's view count for the CURRENT
--- repo, this week, shown only when the current buffer sits inside one of
--- the repos github_stats.nvim actually tracks. Personal, low-utility by
--- design (IDEEN-statusline.md's own framing: "kein Nutzen für irgendjemand
--- anderen, aber genau deshalb charmant für ein privates Setup") -- empty
--- everywhere else, including when github_stats.nvim is not installed.

local dir_to_slug = require("lib.lua.memo.lru").new(64)

-- github_stats.nvim already memoizes the JSON read behind a query
-- (storage.lua's own "Memoized results of read_metric_history" cache), but
-- nothing upstream caches the *decision* of which repo a buffer belongs to,
-- and nothing caches the final view count either -- both would otherwise
-- redo real work (a `git remote get-url` shell-out, a query_metric call) on
-- every statusline redraw, which fires on nearly every event.
local STATS_TTL_SECONDS = 60
---@type table<string, { count: integer, expires_at: integer }>
local stats_cache = {}

--- The "owner/repo" slug for the git remote a directory belongs to, or
--- `false` (cached, so a non-repo directory is not re-shelled-out to on
--- every render either) when there is none.
---@param dir string
---@return string|false
local function resolve_slug(dir)
  local cached = dir_to_slug:get(dir)
  if cached ~= nil then
    return cached
  end

  local out = vim.fn.systemlist({ "git", "-C", dir, "remote", "get-url", "origin" })
  local slug = false
  if vim.v.shell_error == 0 and out[1] then
    -- Matches both "git@github.com:owner/repo.git" and
    -- "https://github.com/owner/repo(.git)?". The repo half is captured
    -- greedily, not as "no dots" -- this ecosystem's own repos are named
    -- "*.nvim", and a `[^/%.]+`-style capture would truncate "ui.nvim" to
    -- "ui" at its first dot, matching nothing github_stats.nvim tracks.
    local owner, repo = out[1]:match("github%.com[:/]([^/]+)/(.+)$")
    if owner and repo then
      slug = owner .. "/" .. repo:gsub("%.git$", "")
    end
  end

  dir_to_slug:put(dir, slug)
  return slug
end

--- This week's view count for `slug`, cached for `STATS_TTL_SECONDS` --
--- GitHub's own traffic API (and github_stats.nvim's background fetch of it)
--- does not update more often than that anyway.
---@param slug string
---@return integer|nil # nil on any error or "nothing to show"
local function views_this_week(slug)
  local now = os.time()
  local cached = stats_cache[slug]
  if cached and cached.expires_at > now then
    return cached.count
  end

  local ok, analytics = pcall(require, "github_stats.analytics")
  if not ok then
    return nil
  end

  local stats, err = analytics.query_metric({ repo = slug, metric = "views", time_range = "7d" })
  if err or not stats then
    return nil
  end

  stats_cache[slug] = { count = stats.total_count, expires_at = now + STATS_TTL_SECONDS }
  return stats.total_count
end

---@return string
return function()
  local ok_gh, config = pcall(require, "github_stats.config")
  if not ok_gh then
    return ""
  end

  local buf_path = vim.api.nvim_buf_get_name(0)
  if buf_path == "" then
    return ""
  end

  local slug = resolve_slug(vim.fn.fnamemodify(buf_path, ":h"))
  if not slug or not vim.tbl_contains(config.get_repos(), slug) then
    return ""
  end

  local count = views_this_week(slug)
  if not count or count == 0 then
    return ""
  end

  return " \xF0\x9F\x91\x81 " .. count .. " diese Woche "
end
