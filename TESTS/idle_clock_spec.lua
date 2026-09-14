-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.idle_clock` -- wall-clock time shown only while
--- idle, from IDEEN-statusline.md's "Idle-Erweiterung nach N Sekunden
--- Inaktivität" ("Uhrzeit" is its own first example payload). Built on
--- `ui.statusline.utils.idle`, covered on its own in TESTS/idle_spec.lua --
--- this file only checks that idle_clock wires into it and formats time
--- correctly, not the idle state machine itself.

---@return fun(): string
local function fresh_idle_clock()
  package.loaded["ui.statusline.utils.idle"] = nil
  package.loaded["ui.statusline.modules.idle_clock"] = nil
  local idle_clock = require("ui.statusline.modules.idle_clock")
  -- ui.statusline.utils.idle registers its autocmds lazily, on the first
  -- is_idle() call -- one throwaway render here (same as a real statusline's
  -- first-ever redraw, which always runs before any CursorHold could fire)
  -- so a test's own event fire below lands on an autocmd that exists yet.
  idle_clock()
  return idle_clock
end

describe("ui.statusline.modules.idle_clock", function()
  it("renders empty before the editor has gone idle", function()
    local idle_clock = fresh_idle_clock()
    assert.equals("", idle_clock())
  end)

  it("renders HH:MM once the editor is idle", function()
    local idle_clock = fresh_idle_clock()
    vim.api.nvim_exec_autocmds("CursorHold", {})

    local out = idle_clock()

    assert.is_not_nil(out:match("^%s%d%d:%d%d%s$"), out)
  end)

  it("hides again once activity resumes", function()
    local idle_clock = fresh_idle_clock()
    vim.api.nvim_exec_autocmds("CursorHold", {})
    assert.is_true(#idle_clock() > 0)

    vim.api.nvim_exec_autocmds("CursorMoved", {})
    assert.equals("", idle_clock())
  end)
end)
