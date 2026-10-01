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

  it("max_entries caps growth, dropping the oldest entries on append()", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      max_entries = 2,
      entries = { { time_ms = 0, content = "one" } },
    })
    handle:append({ { time_ms = 0, content = "two" } })
    handle:append({ { time_ms = 0, content = "three" } })
    local got = lines(handle)
    assert.equals(2, #got, "capped at max_entries")
    assert.truthy(got[1]:match("two$"), "oldest entry was dropped")
    assert.truthy(got[2]:match("three$"), "newest entry kept")
  end)

  it("max_entries trimming never sets has_more_older on its own", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      max_entries = 1,
      entries = { { time_ms = 0, content = "one" } },
    })
    assert.is_false(handle.has_more_older, "no load_more configured -- never true to begin with")
    handle:append({ { time_ms = 0, content = "two" } }) -- triggers _trim()
    assert.is_false(
      handle.has_more_older,
      "trimming must not invent a 'more above' hint load_more() can never satisfy"
    )

    pcall(handle.close, handle)
    local calls = {}
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      max_entries = 1,
      entries = { { time_ms = 0, content = "a" }, { time_ms = 0, content = "b" } },
      load_more = function(direction)
        calls[#calls + 1] = direction
        return {} -- immediately exhausted
      end,
    })
    handle:load_more("older")
    assert.is_false(handle.has_more_older, "load_more('older') reported nothing left")
    handle:append({ { time_ms = 0, content = "c" } }) -- triggers _trim() again
    assert.is_false(
      handle.has_more_older,
      "a later cap-triggered trim must not resurrect a hint load_more already exhausted"
    )
  end)

  it("auto-resizes the window to its content height, floored at 2 rows", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      entries = { { time_ms = 0, content = "only one line" } },
    })
    assert.equals(
      2,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "one content line still floors at 2 rows (lib.nvim.window.tag.find()'s own height > 1 requirement)"
    )
    handle:append({
      { time_ms = 0, content = "two" },
      { time_ms = 0, content = "three" },
      { time_ms = 0, content = "four" },
    })
    assert.equals(
      4,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "grows with real content once past the 2-row floor"
    )
  end)

  it("reserves an extra row for the pagination hint so it isn't scrolled out of view", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      entries = { { time_ms = 0, content = "one" }, { time_ms = 0, content = "two" } },
      load_more = function()
        return {}
      end,
    })
    -- has_more_older starts true whenever load_more is configured -- the
    -- "more above" virt_line is a real rendered row, so the window must be
    -- content (2) + 1 for the hint, not just content.
    assert.equals(
      3,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "height includes the 'more above' hint row, not just the buffer's own 2 lines"
    )
    -- The extra row alone isn't enough -- Neovim's default viewport does
    -- NOT reveal virt_lines_above on line 1 on its own (discovered live-
    -- testing this exact popup: the row rendered blank until manually
    -- scrolled with <C-k>). `topfill` is the view field that actually
    -- reveals it.
    vim.api.nvim_win_call(handle.surf.winid, function()
      assert.equals(
        1,
        vim.fn.winsaveview().topfill,
        "topfill reveals the hint instead of leaving it scrolled out"
      )
    end)

    -- Once load_more reports nothing left, the hint (and its row) go away.
    handle:load_more("older")
    assert.equals(
      2,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "height shrinks back once the pagination hint is gone"
    )
    vim.api.nvim_win_call(handle.surf.winid, function()
      assert.equals(0, vim.fn.winsaveview().topfill, "topfill resets once the hint is gone")
    end)
  end)

  it("does not auto-resize when the caller passed an explicit height", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      height = 5,
      entries = { { time_ms = 0, content = "one" } },
    })
    assert.equals(5, vim.api.nvim_win_get_config(handle.surf.winid).height)
    handle:append({
      { time_ms = 0, content = "two" },
      { time_ms = 0, content = "three" },
    })
    assert.equals(
      5,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "explicit height is never overridden"
    )
  end)

  it(
    "max_entries does not apply to load_more('older') -- paging into history is never trimmed back out",
    function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        max_entries = 2,
        entries = { { time_ms = 0, content = "b" }, { time_ms = 0, content = "c" } },
        load_more = function()
          return { { time_ms = 0, content = "a" } }
        end,
      })
      handle:load_more("older")
      local got = lines(handle)
      assert.equals(3, #got, "pagination is exempt from max_entries")
      assert.truthy(got[1]:match("a$"))
      assert.truthy(got[2]:match("b$"))
      assert.truthy(got[3]:match("c$"))
    end
  )

  it(
    "two concurrently-open instances share a module-level namespace without cross-interference",
    function()
      local a = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, level = vim.log.levels.ERROR, content = "err" } },
      })
      local b = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = "plain" } },
      })
      assert.equals(a._hl_ns, b._hl_ns, "namespace is shared across instances, not per-bufnr")

      local marks_a =
        vim.api.nvim_buf_get_extmarks(a.surf.bufnr, a._hl_ns, 0, -1, { details = true })
      assert.equals(1, #marks_a, "the error highlight landed on a's own buffer")

      local marks_b =
        vim.api.nvim_buf_get_extmarks(b.surf.bufnr, b._hl_ns, 0, -1, { details = true })
      assert.equals(
        0,
        #marks_b,
        "b has no highlight and is unaffected by a's, despite the shared namespace"
      )

      pcall(a.close, a)
      pcall(b.close, b)
    end
  )

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
