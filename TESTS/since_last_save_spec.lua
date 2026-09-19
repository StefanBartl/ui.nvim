-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns
-- luacheck: ignore 122 -- `os.time` is read-only in luacheck's stdlib model
-- the way `vim` (declared writable in .luacheckrc) is not; every mock of it
-- below is a controlled reassignment for a real test, not an accident.

--- `ui.statusline.modules.since_last_save` -- a duration since the buffer
--- became modified, escalating from muted to DiagnosticWarn to
--- DiagnosticError the longer it sits unsaved, from IDEEN-statusline.md's
--- "'Seit letztem Save'-Indikator, der mit der Zeit wächst".

local since_last_save = require("ui.statusline.modules.since_last_save")

---@generic T
---@param seconds integer
---@param fn fun(): T
---@return T
local function with_advanced_time(seconds, fn)
  local original = os.time
  ---@diagnostic disable-next-line: duplicate-set-field
  os.time = function()
    return original() + seconds
  end
  local ok, result = pcall(fn)
  os.time = original
  if not ok then
    error(result, 0)
  end
  return result
end

describe("ui.statusline.modules.since_last_save", function()
  it("renders empty when the buffer is not modified", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = false

    local out = since_last_save()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.equals("", out)
  end)

  it("renders empty for a non-file buftype even when modified", function()
    local buf = vim.api.nvim_create_buf(true, true) -- scratch: buftype nofile
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = true

    local out = since_last_save()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.equals("", out)
  end)

  it("shows a muted duration right after becoming modified", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = true

    local out = since_last_save()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("%#Comment#", 1, true) ~= nil, out)
    assert.is_true(out:find("0s", 1, true) ~= nil, out)
  end)

  it("escalates to DiagnosticWarn past the default 60s threshold", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = true
    since_last_save() -- seeds the clock at "now"

    local out = with_advanced_time(90, since_last_save)

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("%#DiagnosticWarn#", 1, true) ~= nil, out)
    assert.is_nil(out:find("DiagnosticError", 1, true))
  end)

  it("escalates to DiagnosticError past the default 300s threshold", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = true
    since_last_save() -- seeds the clock at "now"

    local out = with_advanced_time(400, since_last_save)

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("%#DiagnosticError#", 1, true) ~= nil, out)
  end)

  it("respects custom warn_after_seconds/critical_after_seconds", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = true
    since_last_save({ warn_after_seconds = 5, critical_after_seconds = 10 })

    local out = with_advanced_time(6, function()
      return since_last_save({ warn_after_seconds = 5, critical_after_seconds = 10 })
    end)

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("%#DiagnosticWarn#", 1, true) ~= nil, out)
  end)

  it("resets the clock once the buffer is saved (modified goes back to false)", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = true
    since_last_save()

    local critical_out = with_advanced_time(400, since_last_save)
    assert.is_true(critical_out:find("DiagnosticError", 1, true) ~= nil, critical_out)

    vim.bo[buf].modified = false
    assert.equals("", since_last_save())

    vim.bo[buf].modified = true
    local out = since_last_save()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("%#Comment#", 1, true) ~= nil, out)
    assert.is_nil(out:find("DiagnosticError", 1, true))
  end)

  it(
    "degrades to the documented defaults instead of crashing on wrong-type opts (ERR-22)",
    function()
      -- `elapsed >= critical_after` used to run on `opts.field or default`,
      -- which only caught an ABSENT value -- a wrong type (a realistic
      -- slip: `warn_after_seconds = "60"`, a string that reads like the
      -- number it should have been) reached that comparison unguarded and
      -- threw "attempt to compare number with string" on every redraw of a
      -- modified buffer.
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].modified = true

      local ok, out = pcall(since_last_save, {
        warn_after_seconds = "not-a-number",
        critical_after_seconds = "also-not-a-number",
      })

      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      assert.is_true(ok, tostring(out))
      -- Falls back to the documented defaults (60/300), same as an absent
      -- opts table -- muted at 0s elapsed, not a thrown error.
      assert.is_true(out:find("%#Comment#", 1, true) ~= nil, out)
    end
  )

  it("does not throw when a tracked buffer is deleted", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].modified = true
    since_last_save()

    assert.has_no.errors(function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
