-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.terminal_count` -- formats terminal.nvim's `terminal.summary()`.
--- terminal.nvim is not on this suite's runtimepath (a soft dependency, same contract as
--- sandbox_ambient), so the "installed" tests inject a fake `terminal` module.

local terminal_count = require("ui.statusline.modules.terminal_count")

local function uninstall()
  package.loaded["terminal"] = nil
end

---@param summary table|fun():table
local function render(summary)
  package.loaded["terminal"] = {
    summary = type(summary) == "function" and summary or function()
      return summary
    end,
  }
  local out = terminal_count()
  uninstall()
  return out
end

describe("ui.statusline.modules.terminal_count", function()
  it("renders empty when terminal.nvim is not loaded", function()
    uninstall()
    assert.equals("", terminal_count())
  end)

  it("renders empty for a terminal.nvim without summary() (an older version)", function()
    package.loaded["terminal"] = {}
    local out = terminal_count()
    uninstall()
    assert.equals("", out)
  end)

  it("renders empty when there is no terminal", function()
    assert.equals("", render({ count = 0, visible = 0 }))
  end)

  it("names the current terminal with the count", function()
    assert.equals("build (3)", render({ count = 3, visible = 1, current = "build" }))
  end)

  it("names the current terminal alone when it is the only one", function()
    assert.equals("main", render({ count = 1, visible = 1, current = "main" }))
  end)

  it("counts the terminals when the cursor is elsewhere", function()
    assert.equals("2 terminals", render({ count = 2, visible = 1 }))
    assert.equals("1 terminal", render({ count = 1, visible = 0 }))
  end)

  it("renders empty when summary() raises or answers nonsense", function()
    assert.equals(
      "",
      render(function()
        error("boom")
      end)
    )
    assert.equals(
      "",
      render(function()
        return "x"
      end)
    )
  end)
end)
