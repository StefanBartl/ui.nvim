-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.windowpicker` -- pick a window by letter: filtering, autoselect,
--- the hint overlay, and picking/cancelling via a real (fed) keypress.

local windowpicker = require("ui.windowpicker")

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(keys, "n", false)
end

describe("ui.windowpicker", function()
  after_each(function()
    windowpicker.setup({
      chars = "FJDKSLA;CMRUEIWOQP",
      include_current_win = false,
      autoselect_one = true,
      include_unfocusable_windows = false,
      filetype = { "neo-tree", "neo-tree-popup", "notify" },
      buftype = { "terminal", "quickfix" },
    })
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
  end)

  it("returns nil when nothing qualifies", function()
    vim.cmd("only")
    vim.bo.filetype = "neo-tree" -- the one window is also the current one, excluded twice over
    assert.is_nil(windowpicker.pick())
  end)

  it("autoselects the only qualifying window without reading a key", function()
    vim.cmd("only")
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p") -- back to the origin, which is now excluded as "current"
    -- No feed() call at all: if this reached getchar() the test would hang.
    assert.equals(other, windowpicker.pick())
  end)

  it("shows a hint on each candidate and picks the one whose letter is pressed", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local second = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local third = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)

    windowpicker.setup({ include_current_win = true, autoselect_one = false })
    local wins_before = vim.api.nvim_tabpage_list_wins(0)

    -- Candidates are enumerated in `nvim_tabpage_list_wins` order, so the
    -- second candidate here is the second-listed window, not necessarily
    -- `second` -- assert against that order instead of assuming it.
    local target = wins_before[2]
    feed("J") -- second letter in the default "FJDKSLA;..." order
    local picked = windowpicker.pick()
    assert.equals(target, picked)
    assert.is_true(vim.api.nvim_win_is_valid(origin))
    assert.is_true(vim.api.nvim_win_is_valid(second))
    assert.is_true(vim.api.nvim_win_is_valid(third))
  end)

  it("cleans up every hint overlay after picking", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })

    local wins_before = vim.api.nvim_list_wins()
    feed("F")
    windowpicker.pick()
    local wins_after = vim.api.nvim_list_wins()
    assert.same(#wins_before, #wins_after)
  end)

  it("returns nil when the pressed key matches no hint", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })

    feed("Z") -- not in "FJDKSLA;CMRUEIWOQP"
    assert.is_nil(windowpicker.pick())
  end)

  it("excludes the current window by default", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)

    assert.equals(other, windowpicker.pick()) -- autoselects: origin excluded, one left
  end)

  it("excludes windows by filetype and buftype", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.bo.filetype = "neo-tree"
    vim.api.nvim_set_current_win(origin)

    -- The only other window is filtered out by filetype, so nothing qualifies.
    assert.is_nil(windowpicker.pick())
  end)

  it("setup() overrides the shipped defaults", function()
    windowpicker.setup({ chars = "AB" })
    assert.equals("AB", windowpicker.config().chars)
  end)
end)
