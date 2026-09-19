-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.zen` -- the distraction-free box: the float, the hidden frame, and
--- the restore on every way out.

local zen = require("ui.zen")

describe("ui.zen", function()
  after_each(function()
    zen.close()
    vim.cmd("silent! %bwipeout!")
  end)

  local function open_buffer()
    vim.cmd("new")
    local buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two", "three" })
    vim.api.nvim_win_set_cursor(0, { 2, 1 })
    return buf, vim.api.nvim_get_current_win()
  end

  it("is closed by default", function()
    assert.is_false(zen.is_open())
    assert.is_nil(zen.win())
  end)

  it("opens the current buffer in a centred float and hides the frame", function()
    vim.o.laststatus = 2
    vim.o.showtabline = 2
    vim.wo.number = true
    local buf, origin = open_buffer()
    local win = zen.open()
    assert.is_true(zen.is_open())
    assert.equals(win, vim.api.nvim_get_current_win())
    assert.equals(buf, vim.api.nvim_win_get_buf(win))
    local wcfg = vim.api.nvim_win_get_config(win)
    assert.equals("editor", wcfg.relative)
    assert.equals(math.min(120, vim.o.columns), wcfg.width)
    assert.equals(0, vim.o.laststatus)
    assert.equals(0, vim.o.showtabline)
    assert.is_false(vim.wo[win].number)
    assert.equals("no", vim.wo[win].signcolumn)
    assert.same({ 2, 1 }, vim.api.nvim_win_get_cursor(win))
    assert.is_true(vim.api.nvim_win_is_valid(origin))
  end)

  it("restores the frame and hands the cursor back on close", function()
    vim.o.laststatus = 2
    vim.o.showtabline = 2
    local _, origin = open_buffer()
    local win = zen.open()
    vim.api.nvim_win_set_cursor(win, { 3, 0 })
    zen.close()
    assert.is_false(zen.is_open())
    assert.equals(2, vim.o.laststatus)
    assert.equals(2, vim.o.showtabline)
    assert.equals(origin, vim.api.nvim_get_current_win())
    assert.same({ 3, 0 }, vim.api.nvim_win_get_cursor(origin))
    assert.is_false(vim.api.nvim_win_is_valid(win))
  end)

  it("restores when the zen window is closed any other way", function()
    vim.o.laststatus = 2
    open_buffer()
    local win = zen.open()
    vim.api.nvim_win_close(win, true)
    vim.wait(50, function()
      return not zen.is_open() and vim.o.laststatus == 2
    end)
    assert.is_false(zen.is_open())
    assert.equals(2, vim.o.laststatus)
  end)

  it("does not close a new session opened before the deferred teardown runs", function()
    vim.o.laststatus = 2
    open_buffer()
    local winA = zen.open()
    -- Close externally, matching :q/<C-w>c: WinClosed fires synchronously
    -- and schedules its own restore, but does not run it yet.
    vim.api.nvim_win_close(winA, true)
    -- Reopen before the event loop drains the scheduled teardown -- the
    -- stale callback used to re-read the shared module state and tear
    -- down whichever session was current by the time it finally ran.
    local winB = zen.open()
    assert.is_true(zen.is_open())
    assert.not_equals(winA, winB)
    -- No condition: wait out the full interval so the loop is actually
    -- processed and any pending vim.schedule callback gets to run.
    vim.wait(80)
    assert.is_true(zen.is_open(), "a stale scheduled teardown closed the new session")
    assert.equals(winB, zen.win())
  end)

  it("toggles, and setup() changes the width live", function()
    open_buffer()
    assert.is_true(zen.toggle())
    assert.is_true(zen.is_open())
    zen.setup({ width = 0.5 })
    local wcfg = vim.api.nvim_win_get_config(zen.win())
    assert.equals(math.floor(vim.o.columns * 0.5 + 0.5), wcfg.width)
    assert.is_false(zen.toggle())
    assert.is_false(zen.is_open())
    zen.setup({ width = 120 })
  end)
end)
