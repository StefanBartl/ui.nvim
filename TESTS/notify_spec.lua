-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.notify` -- the vim.notify seam, the toasts it opens, the history.

local notify = require("ui.notify")
local toast = require("ui.kit.toast")

describe("ui.notify", function()
  local original

  before_each(function()
    original = vim.notify
    notify.clear_history()
    toast.clear()
  end)

  after_each(function()
    notify.disable()
    vim.notify = original
    toast.clear()
    notify.setup({ min_level = vim.log.levels.INFO, history_size = 200 })
  end)

  it("is off by default and enable()/disable() swap vim.notify in and out", function()
    assert.is_false(notify.is_enabled())
    notify.enable()
    assert.is_true(notify.is_enabled())
    assert.equals(notify.handler, vim.notify)
    notify.disable()
    assert.is_false(notify.is_enabled())
    assert.equals(original, vim.notify)
  end)

  it("records every notification and toasts the ones at or above min_level", function()
    notify.enable()
    vim.notify("hello", vim.log.levels.INFO)
    vim.notify("careful", vim.log.levels.WARN, { title = "Disk" })
    vim.notify("noise", vim.log.levels.DEBUG)
    local h = notify.history()
    assert.equals(3, #h)
    assert.equals("hello", h[1].msg)
    assert.equals(vim.log.levels.WARN, h[2].level)
    assert.equals("Disk", h[2].title)
    assert.equals(2, toast.active())
  end)

  it("accepts string levels and non-string messages", function()
    notify.enable()
    vim.notify({ a = 1 }, "error")
    local h = notify.history()
    assert.equals(vim.log.levels.ERROR, h[1].level)
    assert.truthy(h[1].msg:find("a = 1"))
  end)

  it("trims the history to history_size", function()
    notify.setup({ history_size = 3, min_level = vim.log.levels.ERROR })
    notify.enable()
    for i = 1, 5 do
      vim.notify("m" .. i)
    end
    local h = notify.history()
    assert.equals(3, #h)
    assert.equals("m3", h[1].msg)
    assert.equals(0, toast.active())
  end)

  it("renders the history newest first and opens it in a viewer", function()
    notify.enable()
    vim.notify("first")
    vim.notify("second\nline two", vim.log.levels.WARN)
    local lines = notify.history_lines()
    assert.truthy(lines[1]:find("WARN"))
    assert.truthy(lines[1]:find("second"))
    assert.truthy(lines[2]:find("line two"))
    assert.truthy(lines[3]:find("first"))
    local surf = notify.show_history()
    assert.is_not_nil(surf)
    assert.is_true(vim.api.nvim_win_is_valid(surf.winid))
    local shown = vim.api.nvim_buf_get_lines(surf.bufnr, 0, -1, false)
    assert.equals(#lines, #shown)
    surf:close()
  end)

  it("toggles", function()
    assert.is_true(notify.toggle())
    assert.is_false(notify.toggle())
    assert.equals(original, vim.notify)
  end)

  it("does not recurse without bound when showing a toast itself fails", function()
    notify.enable()
    local orig_open = toast.open
    local open_calls = 0
    -- Simulate a toast float that cannot be created (e.g. no room to open
    -- a window) reporting its own failure back through vim.notify -- the
    -- exact re-entrant path that used to recurse until the stack blew.
    toast.open = function(_)
      open_calls = open_calls + 1
      vim.notify("could not open a toast float", vim.log.levels.ERROR)
      return nil
    end
    local ok = pcall(vim.notify, "trigger", vim.log.levels.WARN)
    toast.open = orig_open
    assert.is_true(ok, "vim.notify must not raise even when show() itself fails")
    -- Exactly one nested attempt: the guard stops the second (re-entrant)
    -- call from trying to open its own toast.
    assert.equals(1, open_calls)
  end)

  it("keeps the true original handler across a foreign wrapper disable/enable cycle", function()
    notify.enable()
    local ours = vim.notify
    -- Another plugin wraps vim.notify after we enabled -- still calling
    -- through to us, which disable() cannot fully unhook from.
    local wrapper_calls = 0
    vim.notify = function(...)
      wrapper_calls = wrapper_calls + 1
      ours(...)
    end
    notify.disable()
    assert.is_false(notify.is_enabled())
    -- vim.notify was left as the wrapper (disable() could not restore
    -- through it), but the handler itself must now be inert: a call
    -- reaching M.handler through the wrapper must not grow the history.
    local before = #notify.history()
    vim.notify("still routed through the wrapper", vim.log.levels.INFO)
    assert.equals(1, wrapper_calls)
    assert.equals(before, #notify.history(), "disabled handler must not record")
    -- The true original (from before enable()) must still be recoverable.
    vim.notify = original
    notify.enable()
    notify.disable()
    assert.equals(original, vim.notify)
  end)
end)
