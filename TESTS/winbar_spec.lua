-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.winbar`: owns the final vim.wo.winbar write, nothing else. See the
--- module's own doc comment for why the content side (my.nvim's
--- hl_config.breadcrumbs) keeps everything but this one step.

describe("ui.winbar", function()
  local winbar = require("ui.winbar")

  it("sets the current window's winbar by default", function()
    winbar.set("hello")
    vim.wait(50)
    assert.equals("hello", vim.wo.winbar)
    vim.wo.winbar = ""
  end)

  it("targets an explicit window id", function()
    vim.cmd("split")
    local other = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p")
    local original = vim.api.nvim_get_current_win()
    assert.is_not.equals(other, original)

    winbar.set("explicit", other)
    vim.wait(50)
    assert.equals("explicit", vim.wo[other].winbar)
    assert.is_not.equals("explicit", vim.wo[original].winbar)

    vim.api.nvim_win_close(other, true)
  end)

  it("does not throw when the target window closed before the scheduled write runs", function()
    vim.cmd("split")
    local closing = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p")

    winbar.set("too late", closing)
    vim.api.nvim_win_close(closing, true)

    assert.has_no.errors(function()
      vim.wait(50)
    end)
  end)
end)
