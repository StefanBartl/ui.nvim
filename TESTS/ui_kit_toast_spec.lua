-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.toast`: the ephemeral, auto-dismissing corner message that stacks
--- several live toasts downward from the top-right corner.

local toast = require("ui.kit.toast")

describe("ui.kit.toast", function()
  after_each(function()
    toast.clear()
  end)

  it("stacks a second bordered toast below the first without overlapping its border", function()
    -- Regression: reflow() advanced `row` by only `height + 1` for every
    -- toast, as if it were borderless. A bordered toast's true footprint is
    -- `height + 2` rows (border above and below the content), so the second
    -- toast's top border used to land exactly on the first one's bottom
    -- border -- cutting it off instead of leaving a gap below it.
    local first = toast.open({ message = "first", timeout = 0 })
    local second = toast.open({ message = "second", timeout = 0 })

    local row1 = vim.api.nvim_win_get_config(first.winid).row
    local height1 = vim.api.nvim_win_get_config(first.winid).height
    local row2 = vim.api.nvim_win_get_config(second.winid).row

    -- A bordered box occupies `height + 2` rows; the next one must start at
    -- least one row after that to leave a visible gap between the two.
    assert.is_true(
      row2 >= row1 + height1 + 2 + 1,
      ("second toast (row %d) overlaps the first one's border (row %d, height %d)"):format(
        row2,
        row1,
        height1
      )
    )
  end)
end)
