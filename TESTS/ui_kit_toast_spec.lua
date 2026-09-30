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

  describe("width", function()
    local saved_columns

    before_each(function()
      saved_columns = vim.o.columns
      vim.o.columns = 200
      toast.setup({ width = "40%", min_width = 40, padding = 1 })
    end)

    after_each(function()
      vim.o.columns = saved_columns
      toast.setup({ width = "40%", min_width = 40, padding = 1 })
    end)

    ---@param surf table
    ---@return integer
    local function width_of(surf)
      return vim.api.nvim_win_get_config(surf.winid).width
    end

    it("never gets narrower than min_width for a short message", function()
      local s = toast.open({ message = "0123456789", timeout = 0 })
      assert.equals(40, width_of(s))
    end)

    it("grows with the text up to 40% of the editor width", function()
      local s = toast.open({ message = string.rep("x", 60), timeout = 0 })
      assert.equals(60 + 2, width_of(s)) -- text + 1 column padding each side
      local long = toast.open({ message = string.rep("y", 500), timeout = 0 })
      assert.equals(80, width_of(long)) -- 40% of 200
    end)

    it("wraps text that exceeds the maximum instead of cutting it", function()
      local s = toast.open({ message = string.rep("z", 200), timeout = 0 })
      local lines = vim.api.nvim_buf_get_lines(s.bufnr, 0, -1, false)
      assert.is_true(#lines > 1)
      for _, line in ipairs(lines) do
        assert.is_true(vim.fn.strdisplaywidth(line) <= 80)
      end
      assert.equals(200, #table.concat(lines):gsub(" ", ""))
    end)

    it("pads the text inside the chip", function()
      local s = toast.open({ message = "hi", timeout = 0 })
      assert.equals(" hi ", vim.api.nvim_buf_get_lines(s.bufnr, 0, 1, false)[1])
    end)

    it("takes columns and percentages for width and min_width", function()
      toast.setup({ width = 50, min_width = "10%" })
      local s = toast.open({ message = "hi", timeout = 0 })
      assert.equals(20, width_of(s)) -- 10% of 200
      local long = toast.open({ message = string.rep("x", 300), timeout = 0 })
      assert.equals(50, width_of(long))
    end)

    it("reports the text budget callers should wrap to", function()
      assert.equals(80 - 2, toast.inner_width())
    end)

    it("ignores invalid setup values", function()
      toast.setup({ width = "wide", min_width = -3, padding = "x" })
      assert.equals(80 - 2, toast.inner_width())
    end)

    it("follows a resize", function()
      local s = toast.open({ message = string.rep("x", 500), timeout = 0 })
      assert.equals(80, width_of(s))
      vim.o.columns = 100
      vim.api.nvim_exec_autocmds("VimResized", {})
      assert.equals(40, width_of(s)) -- 40% of 100
    end)

    it("keeps the chip inside a very narrow editor", function()
      vim.o.columns = 30
      local s = toast.open({ message = "hello", timeout = 0 })
      assert.is_true(width_of(s) <= 30 - 2 * 2 - 2)
    end)

    it("is configurable through ui.setup({ toast = ... })", function()
      require("ui").setup({ toast = { width = 60, min_width = 25 } })
      local short = toast.open({ message = "hi", timeout = 0 })
      assert.equals(25, width_of(short))
      local long = toast.open({ message = string.rep("x", 300), timeout = 0 })
      assert.equals(60, width_of(long))
    end)

    it("sits above picker-class floats (theme zindex.toast), not at the popup level", function()
      local s = toast.open({ message = "hi", timeout = 0 })
      local z = vim.api.nvim_win_get_config(s.winid).zindex
      -- snacks' picker layout is 52 and its windows 54; the popup default was 50,
      -- which hid every toast behind an open picker.
      assert.is_true(z > 54, "toast zindex " .. tostring(z) .. " is not above a snacks picker")
      assert.equals(require("ui.kit.theme").resolve().zindex.toast, z)
    end)

    it("right-aligns each toast to its own width", function()
      local narrow = toast.open({ message = "a", timeout = 0 })
      local wide = toast.open({ message = string.rep("x", 70), timeout = 0 })
      local function right_edge(surf)
        local c = vim.api.nvim_win_get_config(surf.winid)
        return c.col + c.width
      end
      assert.equals(right_edge(narrow), right_edge(wide))
    end)
  end)
end)
