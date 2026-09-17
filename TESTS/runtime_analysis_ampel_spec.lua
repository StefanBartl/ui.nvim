-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.runtime_analysis_ampel` -- a thin require of
--- runtime-analysis.nvim's own ready-made
--- `runtime-analysis.statusline.status()`.
---
--- It used to be 140 lines that decided what counts as slow, what "today"
--- means and which glyph to show, and this spec faked
--- `runtime-analysis.telemetry` to drive all of it. That interpretation is
--- the other plugin's opinion about its own data; it moved there with its
--- tests (cross-feature report, finding E). What remains is the adapter
--- contract -- the same shape `sandbox_ambient_spec` and
--- `session_status_spec` check.
---
--- runtime-analysis.nvim is not on this suite's runtimepath, so the
--- "installed" cases inject a fake module.

local ampel = require("ui.statusline.modules.runtime_analysis_ampel")

local function uninstall()
  package.loaded["runtime-analysis.statusline"] = nil
end

describe("ui.statusline.modules.runtime_analysis_ampel", function()
  after_each(uninstall)

  it("renders empty when runtime-analysis.nvim is not installed", function()
    uninstall()
    assert.equals("", ampel())
  end)

  it("renders empty when there is nothing instrumented to watch", function()
    package.loaded["runtime-analysis.statusline"] = {
      status = function()
        return ""
      end,
    }
    assert.equals("", ampel())
  end)

  it("passes runtime-analysis.nvim's own glyph through unchanged", function()
    package.loaded["runtime-analysis.statusline"] = {
      status = function()
        return " \240\159\148\180 "
      end,
    }
    assert.equals(" \240\159\148\180 ", ampel())
  end)

  -- The adapter must not assume the sibling returns a string: a plugin
  -- mid-refactor returning nil should leave the statusline alone rather
  -- than concatenating nil into it.
  it("renders empty when the sibling returns nothing", function()
    package.loaded["runtime-analysis.statusline"] = {
      status = function()
        return nil
      end,
    }
    assert.equals("", ampel())
  end)
end)
