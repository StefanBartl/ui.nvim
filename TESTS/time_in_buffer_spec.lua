-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns
-- luacheck: ignore 122 -- `os.time` is read-only in luacheck's stdlib model
-- the way `vim` (declared writable in .luacheckrc) is not; every mock of it
-- below is a controlled reassignment for a real test, not an accident.

--- `ui.statusline.modules.time_in_buffer` -- elapsed time since a buffer was
--- first entered this session, from IDEEN-statusline.md's "klein, isoliert,
--- schnell" bucket. `os.time()` has one-second resolution, so every test
--- past the first mocks it forward rather than sleeping real seconds.

local time_in_buffer = require("ui.statusline.modules.time_in_buffer")

describe("ui.statusline.modules.time_in_buffer", function()
  it("shows 0s immediately after a buffer is first rendered", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    local out = time_in_buffer()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("0s", 1, true) ~= nil, out)
  end)

  it("formats minutes once enough time has passed", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    time_in_buffer() -- seeds entered_at for this buffer

    local original = os.time
    ---@diagnostic disable-next-line: duplicate-set-field
    os.time = function()
      return original() + 125 -- 2m5s later
    end
    local out = time_in_buffer()
    os.time = original

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("2m", 1, true) ~= nil, out)
  end)

  it("formats hours plus minutes once past an hour", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    time_in_buffer()

    local original = os.time
    ---@diagnostic disable-next-line: duplicate-set-field
    os.time = function()
      return original() + 3725 -- 1h2m5s later
    end
    local out = time_in_buffer()
    os.time = original

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("1h2m", 1, true) ~= nil, out)
  end)

  it("does not restart the clock on a later BufEnter for the same buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    time_in_buffer() -- seeds + registers the BufEnter/BufDelete autocmds

    local original = os.time
    ---@diagnostic disable-next-line: duplicate-set-field
    os.time = function()
      return original() + 60
    end
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    local out = time_in_buffer()
    os.time = original

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    -- Had the second BufEnter reset the clock, this would read "0s" instead.
    assert.is_true(out:find("1m", 1, true) ~= nil, out)
  end)

  it("does not throw when a tracked buffer is deleted", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    time_in_buffer()

    assert.has_no.errors(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
