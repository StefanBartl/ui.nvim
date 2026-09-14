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

  it("does not redrawstatus on a CursorMoved that doesn't change idle state", function()
    -- bug: the active-again autocmd used to write is_idle_state and call
    -- vim.cmd("redrawstatus") unconditionally on every CursorMoved/
    -- CursorMovedI event -- i.e. on every single cursor step, not just the
    -- idle->active transition. That forces a full, synchronous statusline
    -- redraw (re-running every module's render function) on every keystroke
    -- while already active, purely to reconfirm a boolean that hadn't
    -- changed.
    local idle = fresh_idle()
    assert.is_false(idle.is_idle()) -- already not idle

    local redraw_count = 0
    local orig_cmd = vim.cmd
    vim.cmd = function(c)
      if c == "redrawstatus" then
        redraw_count = redraw_count + 1
      end
      return orig_cmd(c)
    end
    local ok = pcall(function()
      fire("CursorMoved")
      fire("CursorMovedI")
    end)
    vim.cmd = orig_cmd
    assert.is_true(ok)

    assert.equals(0, redraw_count)
  end)

  it("redraws exactly once per actual idle<->active transition", function()
    local idle = fresh_idle()

    local redraw_count = 0
    local orig_cmd = vim.cmd
    vim.cmd = function(c)
      if c == "redrawstatus" then
        redraw_count = redraw_count + 1
      end
      return orig_cmd(c)
    end
    local ok = pcall(function()
      fire("CursorHold") -- not idle -> idle: 1 redraw
      fire("CursorHold") -- already idle: no redraw
      fire("CursorMoved") -- idle -> not idle: 1 redraw
      fire("CursorMoved") -- already not idle: no redraw
    end)
    vim.cmd = orig_cmd
    assert.is_true(ok)

    assert.equals(2, redraw_count)
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
