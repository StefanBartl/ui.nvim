-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.macro_counter` -- a live keystroke count for the
--- macro currently recording, from IDEEN-statusline.md's "klein, isoliert,
--- schnell" bucket. Drives a real `qa...q` recording via `nvim_feedkeys`
--- rather than mocking `RecordingEnter`/`RecordingLeave` -- those are real
--- Neovim events tied to real recording state, and there is no reason a
--- test can't just trigger the real thing headless.

local macro_counter = require("ui.statusline.modules.macro_counter")

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

describe("ui.statusline.modules.macro_counter", function()
  it("renders empty when nothing is recording", function()
    assert.equals("", macro_counter())
  end)

  it(
    "shows an increasing keystroke count while a real macro records, then goes empty after",
    function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)

      feed("qa")
      assert.equals("a", vim.fn.reg_recording())

      feed("ihello<Esc>")
      local out1 = macro_counter()

      feed("oworld<Esc>")
      local out2 = macro_counter()

      feed("q")
      assert.equals("", vim.fn.reg_recording())
      local out_after = macro_counter()

      pcall(vim.api.nvim_buf_delete, buf, { force = true })

      assert.is_true(out1:find("@a", 1, true) ~= nil, out1)
      local n1 = tonumber(out1:match("\xC2\xB7%s*(%d+)"))
      local n2 = tonumber(out2:match("\xC2\xB7%s*(%d+)"))
      assert.is_not_nil(n1, out1)
      assert.is_not_nil(n2, out2)
      assert.is_true(n2 > n1, ("%d vs %d -- %s / %s"):format(n1, n2, out1, out2))
      assert.equals("", out_after)
    end
  )

  it("resets the count on a fresh recording rather than carrying the last one over", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    feed("qa")
    feed("ihello world<Esc>")
    feed("q")

    feed("qb")
    local out = macro_counter()
    feed("q")

    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(out:find("@b", 1, true) ~= nil, out)
    local n = tonumber(out:match("\xC2\xB7%s*(%d+)"))
    assert.is_not_nil(n, out)
    assert.is_true(n < 5, ("expected a near-zero fresh count, got %d -- %s"):format(n, out))
  end)
end)
