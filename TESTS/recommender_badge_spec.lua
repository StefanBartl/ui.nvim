-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.recommender_badge` -- a thin require of
--- recommender.nvim's own ready-made `recommender.statusline.status()`.
---
--- It used to be 79 lines reaching into `recommender.config` and
--- `recommender.analyzers.*`, and this spec used to assert the wording and
--- the per-buffer caching by injecting fakes for both. Logic and tests
--- moved into recommender.nvim (cross-feature report, finding E), where
--- they run against the real analyzer instead of a stub of it. What
--- remains here is the adapter contract -- the same shape
--- `sandbox_ambient_spec` and `session_status_spec` check.
---
--- recommender.nvim is not on this suite's runtimepath, so the "installed"
--- cases inject a fake module.

local recommender_badge = require("ui.statusline.modules.recommender_badge")

local function uninstall()
  package.loaded["recommender.statusline"] = nil
end

describe("ui.statusline.modules.recommender_badge", function()
  after_each(uninstall)

  it("renders empty when recommender.nvim is not installed", function()
    uninstall()
    assert.equals("", recommender_badge())
  end)

  it("renders empty when there is nothing to suggest", function()
    package.loaded["recommender.statusline"] = {
      status = function()
        return ""
      end,
    }
    assert.equals("", recommender_badge())
  end)

  it("passes recommender.nvim's own badge through unchanged", function()
    package.loaded["recommender.statusline"] = {
      status = function()
        return " 3 alias suggestions open for this file "
      end,
    }
    assert.equals(" 3 alias suggestions open for this file ", recommender_badge())
  end)

  -- The adapter must not assume the sibling returns a string: a plugin
  -- mid-refactor returning nil should leave the statusline alone rather
  -- than concatenating nil into it.
  it("renders empty when the sibling returns nothing", function()
    package.loaded["recommender.statusline"] = {
      status = function()
        return nil
      end,
    }
    assert.equals("", recommender_badge())
  end)
end)
