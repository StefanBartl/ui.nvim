-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

-- `kit.confirm` answers exactly once, whichever way its float goes away: confirmed, cancelled,
-- closed from outside (`nvim_win_close`, `:only`), replaced by a second dialog, or `confirm.close()`.
-- The module header promises "answers" on every path; a waiting `kit.ask` depends on it.
local function spec()
  local kit = require("ui.kit")
  local confirm = require("ui.kit.confirm")
  local api = vim.api

  local function close_all()
    confirm.close()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end

  ---@param opts? table
  ---@return table calls, Ui.Kit.Surface surf
  local function open(opts)
    local calls = {}
    local o = vim.tbl_extend("force", { question = "Q?" }, opts or {})
    o.on_answer = function(v)
      calls[#calls + 1] = v == nil and "nil" or v
    end
    local surf = kit.confirm(o)
    assert(surf, "the dialog opened")
    return calls, surf
  end

  local function eq(actual, expected, msg)
    assert(
      vim.deep_equal(actual, expected),
      ("%s: expected %s, got %s"):format(msg, vim.inspect(expected), vim.inspect(actual))
    )
  end

  -- confirmed / cancelled keep working, once each
  local calls = open()
  confirm.confirm()
  eq(calls, { true }, "confirm -> true, once")
  calls = open()
  confirm.cancel()
  eq(calls, { false }, "cancel -> false, once")
  calls = open({ choices = { "a", "b" } })
  confirm.cancel()
  eq(calls, { "nil" }, "cancel with choices -> nil, once")

  -- closed from outside: the float vanishes without confirm/cancel
  local surf
  calls, surf = open()
  api.nvim_win_close(surf.winid, true)
  eq(calls, { false }, "float closed from outside -> false, once")
  eq(confirm.is_open(), false, "and the dialog is no longer open")

  calls, surf = open({ choices = { "a", "b" } })
  api.nvim_win_close(surf.winid, true)
  eq(calls, { "nil" }, "float closed from outside with choices -> nil, once")

  -- replaced by a second dialog: the first one is answered as cancelled
  local first = open()
  local second = open({ question = "second" })
  eq(first, { false }, "a replaced dialog is answered as cancelled")
  eq(second, {}, "and the new one is still waiting")
  confirm.confirm()
  eq(second, { true }, "the new one answers on its own")
  eq(first, { false }, "the replaced one does not answer twice")

  -- confirm.close() ends the dialog and answers as cancelled
  calls = open()
  confirm.close()
  eq(calls, { false }, "close() -> false, once")
  confirm.close()
  eq(calls, { false }, "close() on a closed dialog is a no-op")

  -- confirming from inside a callback that opens the next dialog does not answer the next one
  local outer = {}
  local inner
  kit.confirm({
    question = "outer",
    on_answer = function(v)
      outer[#outer + 1] = v
      inner = open({ question = "inner" })
    end,
  })
  confirm.confirm()
  eq(outer, { true }, "the outer dialog answered once")
  eq(inner, {}, "the dialog opened in the callback is untouched")
  close_all()
end

describe("ui.kit.confirm answers", function()
  it("answers exactly once on every way a dialog goes away", function()
    spec()
  end)
end)
