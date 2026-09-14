-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.utils.idle` -- the CursorHold/CursorHoldI-based idle
--- primitive backing IDEEN-statusline.md's "Idle-Erweiterung nach N
--- Sekunden Inaktivität". The module is re-required fresh in every test
--- (`package.loaded[...] = nil` then `require(...)` again): `is_idle_state`
--- is module-level, and a real `CursorHold`/`CursorMoved` fired by one test
--- would otherwise leak into the next.

---@return { is_idle: fun(): boolean, wrap: fun(fn: fun(): string): fun(): string }
local function fresh_idle()
  package.loaded["ui.statusline.utils.idle"] = nil
  local idle = require("ui.statusline.utils.idle")
  -- Autocmds register lazily, on the first `is_idle()` call -- exactly like
  -- a real statusline redraw runs before any CursorHold could possibly have
  -- fired yet. Calling it once here mirrors that, so a test's own `fire()`
  -- below lands on an autocmd that actually exists.
  idle.is_idle()
  return idle
end

---@param event string|string[]
local function fire(event)
  vim.api.nvim_exec_autocmds(event, {})
end

describe("ui.statusline.utils.idle", function()
  it("starts out not idle", function()
    local idle = fresh_idle()
    assert.is_false(idle.is_idle())
  end)

  it("becomes idle after CursorHold", function()
    local idle = fresh_idle()
    fire("CursorHold")
    assert.is_true(idle.is_idle())
  end)

  it("becomes idle after CursorHoldI too", function()
    local idle = fresh_idle()
    fire("CursorHoldI")
    assert.is_true(idle.is_idle())
  end)

  it("becomes active again on CursorMoved", function()
    local idle = fresh_idle()
    fire("CursorHold")
    assert.is_true(idle.is_idle())

    fire("CursorMoved")
    assert.is_false(idle.is_idle())
  end)

  it("becomes active again on InsertEnter", function()
    local idle = fresh_idle()
    fire("CursorHold")
    fire("InsertEnter")
    assert.is_false(idle.is_idle())
  end)

  describe("wrap()", function()
    it("renders empty while not idle", function()
      local idle = fresh_idle()
      local wrapped = idle.wrap(function()
        return "CLOCK"
      end)
      assert.equals("", wrapped())
    end)

    it("renders the segment's own output once idle", function()
      local idle = fresh_idle()
      fire("CursorHold")
      local wrapped = idle.wrap(function()
        return "CLOCK"
      end)
      assert.equals("CLOCK", wrapped())
    end)

    it("goes back to empty after activity resumes", function()
      local idle = fresh_idle()
      fire("CursorHold")
      local wrapped = idle.wrap(function()
        return "CLOCK"
      end)
      assert.equals("CLOCK", wrapped())

      fire("CursorMoved")
      assert.equals("", wrapped())
    end)
  end)
end)
