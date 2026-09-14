-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.sandbox_ambient` -- a thin require of sandbox.nvim's
--- own ready-made `sandbox.statusline.status()`. sandbox.nvim is not on this
--- suite's runtimepath (a soft dependency, same contract as
--- recommender_badge/github_stats_badge), so the "installed" tests inject a
--- fake `sandbox.statusline` module.

local sandbox_ambient = require("ui.statusline.modules.sandbox_ambient")

local function uninstall()
  package.loaded["sandbox.statusline"] = nil
end

describe("ui.statusline.modules.sandbox_ambient", function()
  it("renders empty when sandbox.nvim is not installed", function()
    uninstall()
    assert.equals("", sandbox_ambient())
  end)

  it("renders empty when no engine is configured or reachable", function()
    package.loaded["sandbox.statusline"] = {
      status = function()
        return ""
      end,
    }

    local out = sandbox_ambient()

    uninstall()
    assert.equals("", out)
  end)

  it("passes sandbox.nvim's own ambient summary through unchanged", function()
    package.loaded["sandbox.statusline"] = {
      status = function()
        return "docker (2/5)"
      end,
    }

    local out = sandbox_ambient()

    uninstall()
    assert.equals("docker (2/5)", out)
  end)
end)
