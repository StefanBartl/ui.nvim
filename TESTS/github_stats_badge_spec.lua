-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.github_stats_badge` -- a thin require of
--- github_stats.nvim's own ready-made `github_stats.statusline.status()`.
---
--- It used to be 106 lines that resolved the git remote and reached into
--- `github_stats.analytics` and `github_stats.config`, and this spec used
--- to fake both plus a distinct directory per test, because the slug and
--- count caches were module-local here. All of it moved into
--- github_stats.nvim with the logic (cross-feature report, finding E) and
--- is tested there. What remains is the adapter contract -- the same shape
--- `sandbox_ambient_spec` and `session_status_spec` check.
---
--- github_stats.nvim is not on this suite's runtimepath, so the "installed"
--- cases inject a fake module.

local github_stats_badge = require("ui.statusline.modules.github_stats_badge")

local function uninstall()
  package.loaded["github_stats.statusline"] = nil
end

describe("ui.statusline.modules.github_stats_badge", function()
  after_each(uninstall)

  it("renders empty when github_stats.nvim is not installed", function()
    uninstall()
    assert.equals("", github_stats_badge())
  end)

  it("renders empty outside a tracked repository", function()
    package.loaded["github_stats.statusline"] = {
      status = function()
        return ""
      end,
    }
    assert.equals("", github_stats_badge())
  end)

  it("passes github_stats.nvim's own badge through unchanged", function()
    package.loaded["github_stats.statusline"] = {
      status = function()
        return " 42 views this week "
      end,
    }
    assert.equals(" 42 views this week ", github_stats_badge())
  end)

  -- The adapter must not assume the sibling returns a string: a plugin
  -- mid-refactor returning nil should leave the statusline alone rather
  -- than concatenating nil into it.
  it("renders empty when the sibling returns nothing", function()
    package.loaded["github_stats.statusline"] = {
      status = function()
        return nil
      end,
    }
    assert.equals("", github_stats_badge())
  end)
end)
