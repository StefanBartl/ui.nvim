-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.github_stats_badge` -- a personal view-count badge
--- for the repo the current buffer sits in, from IDEEN-statusline.md's
--- "Segmente, die dieses Ökosystem einzigartig machen" bucket.
--- github_stats.nvim is not on this suite's runtimepath (a soft dependency,
--- same contract as casedesk/filetree_cwd_mode), so the "installed" tests
--- inject fake `github_stats.config`/`github_stats.analytics` modules the
--- same way TESTS/primitives_separators_spec.lua fakes "filetree".
---
--- Every test uses its own fake directory: `resolve_slug`'s cache is keyed
--- by directory and `views_this_week`'s by slug, both module-local and
--- process-lifetime, so reusing one across tests would leak one test's mock
--- into the next.

local badge = require("ui.statusline.modules.github_stats_badge")

---@param buf integer
---@param dir string
local function set_buf_in_dir(buf, dir)
  vim.api.nvim_buf_set_name(buf, dir .. "/file.lua")
end

describe("ui.statusline.modules.github_stats_badge", function()
  it("renders empty when github_stats.nvim is not installed", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_in_dir(buf, "/tmp/gh_badge_not_installed")

    assert.equals("", badge())

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("renders empty when the repo is not one github_stats.nvim tracks", function()
    package.loaded["github_stats.config"] = {
      get_repos = function()
        return { "StefanBartl/some-other-repo" }
      end,
    }

    local original_systemlist = vim.fn.systemlist
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function()
      return { "git@github.com:StefanBartl/ui.nvim.git" }
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_in_dir(buf, "/tmp/gh_badge_untracked")

    local out = badge()

    vim.fn.systemlist = original_systemlist
    package.loaded["github_stats.config"] = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.equals("", out)
  end)

  it("shows the view count when the repo is tracked and has views this week", function()
    package.loaded["github_stats.config"] = {
      get_repos = function()
        return { "StefanBartl/ui.nvim" }
      end,
    }
    package.loaded["github_stats.analytics"] = {
      query_metric = function(query)
        assert.equals("StefanBartl/ui.nvim", query.repo)
        assert.equals("views", query.metric)
        assert.equals("7d", query.time_range)
        return { total_count = 42 }, nil
      end,
    }

    local original_systemlist = vim.fn.systemlist
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function()
      return { "https://github.com/StefanBartl/ui.nvim.git" }
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_in_dir(buf, "/tmp/gh_badge_tracked")

    local out = badge()

    vim.fn.systemlist = original_systemlist
    package.loaded["github_stats.config"] = nil
    package.loaded["github_stats.analytics"] = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(out:find("42", 1, true) ~= nil, out)
  end)

  it("renders empty when the tracked repo has zero views", function()
    -- A distinct slug from the other tests in this file, deliberately --
    -- `views_this_week`'s cache (github_stats_badge/init.lua's
    -- `stats_cache`) is keyed by slug alone, not by (slug, test), and lives
    -- for STATS_TTL_SECONDS. Reusing "StefanBartl/ui.nvim" here would let
    -- this test see the OTHER test's cached count (42) instead of calling
    -- its own mocked `query_metric` (which returns 0) -- exactly the
    -- order-dependent failure this file used to have.
    package.loaded["github_stats.config"] = {
      get_repos = function()
        return { "StefanBartl/ui-zero-views.nvim" }
      end,
    }
    package.loaded["github_stats.analytics"] = {
      query_metric = function()
        return { total_count = 0 }, nil
      end,
    }

    local original_systemlist = vim.fn.systemlist
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function()
      return { "https://github.com/StefanBartl/ui-zero-views.nvim.git" }
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_in_dir(buf, "/tmp/gh_badge_zero_views")

    local out = badge()

    vim.fn.systemlist = original_systemlist
    package.loaded["github_stats.config"] = nil
    package.loaded["github_stats.analytics"] = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.equals("", out)
  end)

  it("caches the git remote lookup per directory instead of shelling out every render", function()
    package.loaded["github_stats.config"] = {
      get_repos = function()
        return { "StefanBartl/ui.nvim" }
      end,
    }
    package.loaded["github_stats.analytics"] = {
      query_metric = function()
        return { total_count = 7 }, nil
      end,
    }

    local calls = 0
    local original_systemlist = vim.fn.systemlist
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function()
      calls = calls + 1
      return { "https://github.com/StefanBartl/ui.nvim.git" }
    end

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_in_dir(buf, "/tmp/gh_badge_cache_check")

    badge()
    badge()
    badge()

    vim.fn.systemlist = original_systemlist
    package.loaded["github_stats.config"] = nil
    package.loaded["github_stats.analytics"] = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.equals(1, calls)
  end)
end)
