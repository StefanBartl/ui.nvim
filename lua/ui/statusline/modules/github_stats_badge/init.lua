---@module 'ui.statusline.modules.github_stats_badge'
--- "👁 42 this week" -- github_stats.nvim's view count for the CURRENT
--- repo, this week, shown only when the current buffer sits inside one of
--- the repos github_stats.nvim actually tracks. Personal, low-utility by
--- design (IDEEN-statusline.md's own framing: "kein Nutzen für irgendjemand
--- anderen, aber genau deshalb charmant für ein privates Setup") -- empty
--- everywhere else, including when github_stats.nvim is not installed.

local primitives = require("ui.statusline.utils.primitives")
local nerd_font = require("lib.nvim.ui.nerd_font")

local dir_to_slug = require("lib.lua.memo.lru").new(64)

-- github_stats.nvim already memoizes the JSON read behind a query
-- (storage.lua's own "Memoized results of read_metric_history" cache), but
-- nothing upstream caches the *decision* of which repo a buffer belongs to,
-- and nothing caches the final view count either -- both would otherwise
-- redo real work (a `git remote get-url` shell-out, a query_metric call) on
-- every statusline redraw, which fires on nearly every event.

-- Resolved once: neither `vim.g.have_nerd_font` nor a glyph's rendered
-- width changes mid-session, and this module renders on nearly every
-- redraw. nf-fa-eye (U+F06E).
local EYE = nerd_font.glyph("f06e", "")

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

  -- `package.loaded` rather than `require`: this render path runs on the
  -- very first statusline redraw, so a `require` here would pull
  -- github_stats.nvim in before it gets to load on its own lazy trigger
  -- (see the identical fix/comment in filetree_cwd_mode's render function).
  local analytics = package.loaded["github_stats.analytics"]
  if type(analytics) ~= "table" then
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
  -- `package.loaded`, not `require` -- see the comment in `views_this_week`.
  local config = package.loaded["github_stats.config"]
  if type(config) ~= "table" then
    return ""
  end

  local buf_path = vim.api.nvim_buf_get_name(primitives.stbufnr())
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

  -- The icon used to be a raw U+1F441 emoji with no check of any kind.
  -- Emoji are commonly East-Asian-Wide, so it rendered two cells and
  -- shifted every segment after it. `nerd_font.glyph` is the shared probe
  -- that answers both questions at once: is a Nerd Font declared, and is
  -- the glyph one cell wide.
  --
  -- `""` as its fallback is deliberate, and safe only because the empty
  -- case is handled right here rather than concatenated blindly -- which
  -- is the trap that module's own doc warns about.
  if EYE == "" then
    return (" %d views this week "):format(count)
  end
  return (" %s %d this week "):format(EYE, count)
end
