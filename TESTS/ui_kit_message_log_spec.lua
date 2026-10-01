-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.message_log`: a scrollable, time-ordered, paginated, collapsible
--- entry list popup. Covers: initial render + "Ns ago" formatting, collapsed
--- mode (first-line-only + toggle), newest_first/newest_last ordering,
--- load_more appending/prepending and hiding its own arrow once empty,
--- append() for a live feed, and on_close firing.

local message_log = require("ui.kit.message_log")

---@param handle table
---@return string[]
local function lines(handle)
  return vim.api.nvim_buf_get_lines(handle.surf.bufnr, 0, -1, false)
end

describe("ui.kit.message_log", function()
  local handle

  after_each(function()
    if handle then
      pcall(handle.close, handle)
      handle = nil
    end
  end)

  it("renders initial entries oldest-first by default, with a relative time label", function()
    handle = message_log.open({
      now_ms = function()
        return 10000
      end,
      entries = {
        { time_ms = 8000, content = "first" },
        { time_ms = 9500, content = "second" },
      },
    })
    local got = lines(handle)
    assert.equals(2, #got)
    assert.truthy(got[1]:match("^%[2s ago%] first$"))
    assert.truthy(got[2]:match("^%[0s ago%] second$"))
  end)

  it("order = newest_first reverses the render order without touching storage", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      order = "newest_first",
      entries = {
        { time_ms = 0, content = "old" },
        { time_ms = 0, content = "new" },
      },
    })
    local got = lines(handle)
    assert.equals("[0s ago] new", got[1])
    assert.equals("[0s ago] old", got[2])
  end)

  it("an empty entry list shows a placeholder instead of a blank buffer", function()
    handle = message_log.open({ entries = {} })
    assert.same({ "(no messages)" }, lines(handle))
  end)

  it("collapsed mode shows only the first content line, with a count marker", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      collapsed_default = true,
      entries = { { time_ms = 0, content = "line one\nline two\nline three" } },
    })
    local got = lines(handle)
    assert.equals(1, #got)
    assert.truthy(got[1]:match("^%[0s ago%] line one%s+… %(%+2 more lines%)$"))

    handle:set_collapsed(false)
    got = lines(handle)
    assert.equals(3, #got)
    assert.equals("line two", got[2])
    assert.equals("line three", got[3])

    handle:set_collapsed(true)
    assert.equals(1, #lines(handle))
  end)

  it("append() adds to the end without discarding what was already loaded", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      entries = { { time_ms = 0, content = "one" } },
    })
    handle:append({ { time_ms = 0, content = "two" } })
    local got = lines(handle)
    assert.equals(2, #got)
    assert.truthy(got[2]:match("two$"))
  end)

  it("load_more('older') prepends and stops offering more once empty", function()
    local calls = {}
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      entries = { { time_ms = 0, content = "newer" } },
      load_more = function(direction)
        calls[#calls + 1] = direction
        if #calls == 1 then
          return { { time_ms = 0, content = "older" } }
        end
        return {}
      end,
    })
    handle:load_more("older")
    local got = lines(handle)
    assert.equals(2, #got)
    assert.truthy(got[1]:match("older$"))
    assert.truthy(got[2]:match("newer$"))

    -- Second call reports nothing left; must not error and must not duplicate.
    handle:load_more("older")
    assert.equals(2, #lines(handle))
    assert.same({ "older", "older" }, calls)
  end)

  it("on_close fires when the window is closed", function()
    local closed = false
    handle = message_log.open({ entries = {} })
    handle:on_close(function()
      closed = true
    end)
    handle:close()
    assert.is_true(closed)
    handle = nil -- already closed, after_each must not double-close
  end)
end)
