-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.session_status` -- a thin require of sessions.nvim's
--- own ready-made `sessions.statusline.component()`. sessions.nvim is not on
--- this suite's runtimepath (a soft dependency, same contract as
--- recommender_badge/github_stats_badge), so the "installed" tests inject a
--- fake `sessions.statusline` module.

local session_status = require("ui.statusline.modules.session_status")

local function uninstall()
  package.loaded["sessions.statusline"] = nil
end

describe("ui.statusline.modules.session_status", function()
  it("renders empty when sessions.nvim is not installed", function()
    uninstall()
    assert.equals("", session_status())
  end)

  it("renders empty when no session is active", function()
    package.loaded["sessions.statusline"] = {
      component = function()
        return ""
      end,
    }

    local out = session_status()

    uninstall()
    assert.equals("", out)
  end)

  it("passes sessions.nvim's own component text through unchanged", function()
    package.loaded["sessions.statusline"] = {
      component = function()
        return "main *"
      end,
    }

    local out = session_status()

    uninstall()
    assert.equals("main *", out)
  end)
end)
