-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.history`: the back/forward trail (a re-export of `lib.nvim.ui.kit.history`, whose
--- TESTS/ui_kit_history_spec.lua covers every branch). This pins the ui.nvim names: the module,
--- `kit.history`, and the go / CLEAR / back / forward round trip a consumer relies on.

local history = require("ui.kit.history")

describe("ui.kit.history", function()
  it("is lib.nvim's module under both names", function()
    assert.equals(require("lib.nvim.ui.kit.history"), history)
    assert.equals(history, require("ui.kit").history)
  end)

  it("goes, clears and steps back and forward", function()
    local st = { mode = "structure", id = "root" }
    local h = history.new({ state = st, keys = { "mode", "id", "fn" } })
    assert.is_true(h:go(st, { id = "a", fn = "f" }))
    assert.is_true(h:go(st, { fn = history.CLEAR }))
    assert.is_nil(st.fn)
    assert.equals(3, h:len())
    assert.is_true(h:back(st))
    assert.equals("f", st.fn)
    assert.is_true(h:back(st))
    assert.equals("root", st.id)
    assert.is_nil(st.fn)
    assert.is_false(h:back(st))
    assert.is_true(h:forward(st, 2))
    assert.equals("a", st.id)
    assert.is_nil(st.fn)
  end)

  it("drops forward history on a new move; a no-op move is no stop", function()
    local st = { id = "root" }
    local h = history.new({ state = st, keys = { "id" } })
    h:go(st, { id = "a" })
    h:back(st)
    assert.is_false(h:go(st, { id = "root" }))
    assert.is_true(h:can_forward())
    h:go(st, { id = "b" })
    assert.is_false(h:can_forward())
    assert.equals(2, h:len())
  end)
end)
