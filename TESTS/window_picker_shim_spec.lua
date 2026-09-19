-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `window-picker` -- the compatibility shim consumers that hardcode
--- `require("window-picker")` (neo-tree's `open_with_window_picker`
--- chief among them) resolve to. Delegates to `ui.windowpicker`.

local shim = require("window-picker")
local windowpicker = require("ui.windowpicker")

describe("window-picker (compat shim)", function()
  after_each(function()
    windowpicker.setup({ chars = "FJDKSLA;CMRUEIWOQP", autoselect_one = true })
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
  end)

  it("pick_window() delegates to ui.windowpicker.pick()", function()
    vim.cmd("only")
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p")
    -- Autoselect path, matching how neo-tree calls this with `{}` and no
    -- other window is left once the current one is excluded.
    assert.equals(other, shim.pick_window({}))
  end)

  it("setup() delegates to ui.windowpicker.setup()", function()
    shim.setup({ chars = "AB" })
    assert.equals("AB", windowpicker.config().chars)
  end)
end)
