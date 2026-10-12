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
      5,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "grows with real content (4) plus the legend row"
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
      4,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "height includes the 'more above' hint row and the legend, not just the buffer's own 2 lines"
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
      3,
      vim.api.nvim_win_get_config(handle.surf.winid).height,
      "height shrinks back once the pagination hint is gone (the legend stays)"
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

  it("append() from a fast event context is deferred, not an E5560 error", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      entries = { { time_ms = 0, content = "first" } },
    })
    local fast, err
    local timer = vim.uv.new_timer()
    timer:start(0, 0, function()
      timer:close()
      fast = vim.in_fast_event()
      -- Two appends in one fast event: both must survive, in order.
      err = select(2, pcall(handle.append, handle, { { time_ms = 0, content = "second" } }))
      pcall(handle.append, handle, { { time_ms = 0, content = "third" } })
    end)
    vim.wait(1000, function()
      return #lines(handle) >= 3
    end)
    assert.is_true(fast, "the callback really ran in a fast event")
    assert.is_nil(err)
    local got = lines(handle)
    assert.equals(3, #got)
    assert.truthy(got[1]:match("first$"))
    assert.truthy(got[2]:match("second$"))
    assert.truthy(got[3]:match("third$"))
  end)

  it("a direct append() never overtakes entries still queued from a fast event", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      entries = {},
    })
    handle._pending = { { time_ms = 0, content = "queued" } }
    handle:append({ { time_ms = 0, content = "direct" } })
    vim.wait(1000, function()
      return #handle.entries >= 2
    end)
    assert.equals("queued", handle.entries[1].content)
    assert.equals("direct", handle.entries[2].content)
  end)

  it("a queued append() after the window closed is a harmless no-op", function()
    handle = message_log.open({ entries = {} })
    local errors = {}
    local notify = vim.notify
    vim.notify = function(msg)
      errors[#errors + 1] = msg
    end
    handle._pending = { { time_ms = 0, content = "late" } }
    handle:append({ { time_ms = 0, content = "later" } })
    handle:close()
    local drained = vim.wait(1000, function()
      return not handle._flush_scheduled
    end)
    vim.notify = notify
    assert.is_true(drained, "the scheduled flush ran")
    assert.same({}, errors)
    handle = nil -- already closed, after_each must not double-close
  end)

  ---@param keys string
  local function press(keys)
    vim.api.nvim_feedkeys(vim.keycode(keys), "mx", false)
  end

  ---@param h table
  ---@return integer
  local function cursor_line(h)
    return vim.api.nvim_win_get_cursor(h.surf.winid)[1]
  end

  local function three_multiline()
    return {
      { time_ms = 0, content = "a1\na2\na3" },
      { time_ms = 0, content = "b1\nb2" },
      { time_ms = 0, content = "c1" },
    }
  end

  describe("per-entry expand / collapse", function()
    it("<CR> on one entry opens only that entry; a second <CR> folds it again", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        collapsed_default = true,
        entries = three_multiline(),
      })
      assert.equals(3, #lines(handle), "everything starts folded")

      vim.api.nvim_win_set_cursor(handle.surf.winid, { 1, 0 })
      press("<CR>")
      local got = lines(handle)
      assert.equals(5, #got, "only the first entry (3 lines) opened: 3 + 1 + 1")
      assert.truthy(got[2] == "a2" and got[3] == "a3")
      assert.truthy(got[4]:match("b1"), "the second entry stays folded")

      press("<CR>")
      assert.equals(3, #lines(handle), "the same key folds it again")
    end)

    it("works from any line of an open entry, not just its first", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        collapsed_default = false,
        entries = three_multiline(),
      })
      assert.equals(6, #lines(handle))
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 3, 0 }) -- "a3"
      press("zc")
      assert.equals(4, #lines(handle), "entry a folded from its third line")
      assert.equals(1, cursor_line(handle), "the cursor follows the folded entry to its first line")
    end)

    it("zo / zc are explicit; the cursor stays on the entry when lines shift above it", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        collapsed_default = true,
        entries = three_multiline(),
      })
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 2, 0 }) -- entry b
      press("zo")
      press("zo") -- idempotent
      assert.equals(4, #lines(handle))
      assert.equals(2, cursor_line(handle))
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 1, 0 })
      press("zo") -- entry a opens above b: b moves down, cursor stays on a
      assert.equals(1, cursor_line(handle))
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 4, 0 }) -- b1
      press("zc")
      assert.equals(4, cursor_line(handle), "b is still at line 4 and folded")
    end)

    it("zR / zM / <C-e> act on all entries and forget the per-entry choices", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        collapsed_default = true,
        entries = three_multiline(),
      })
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 1, 0 })
      press("zo")
      press("zM")
      assert.equals(3, #lines(handle), "zM folds the entry that was opened by hand too")
      press("zR")
      assert.equals(6, #lines(handle))
      press("<C-e>")
      assert.equals(3, #lines(handle), "<C-e> flips between all open and all folded")
      press("<C-l>")
      assert.equals(6, #lines(handle))
      press("<C-h>")
      assert.equals(3, #lines(handle))
      press("<BS>")
      assert.equals(3, #lines(handle), "<BS> folds as well (a terminal may send it for <C-h>)")
    end)

    it("the placeholder line is not an entry: toggling it is a harmless no-op", function()
      handle = message_log.open({ entries = {} })
      press("<CR>")
      press("zo")
      assert.same({ "(no messages)" }, lines(handle))
    end)

    it("marks folded and open entries with ▸ / ▾ without touching the buffer text", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        collapsed_default = true,
        entries = { { time_ms = 0, content = "x\ny" }, { time_ms = 0, content = "single" } },
      })
      local function mark_texts()
        local out = {}
        local marks = vim.api.nvim_buf_get_extmarks(
          handle.surf.bufnr,
          vim.api.nvim_create_namespace("ui_kit_message_log_marks"),
          0,
          -1,
          { details = true }
        )
        for _, m in ipairs(marks) do
          out[m[2] + 1] = m[4].virt_text[1][1]
        end
        return out
      end
      assert.same({ "▸ ", "  " }, mark_texts())
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 1, 0 })
      press("<CR>")
      assert.same({ "▾ ", "│ ", "  " }, mark_texts())
      for _, l in ipairs(lines(handle)) do
        assert.is_nil(l:find("[▸▾│]"), "the marks are virtual text, not buffer text")
      end
    end)
  end)

  describe("pagination", function()
    it("keeps the cursor on the entry it was on when older ones are prepended", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = "newer" } },
        load_more = function()
          return { { time_ms = 0, content = "old1" }, { time_ms = 0, content = "old2" } }
        end,
      })
      assert.equals(1, cursor_line(handle))
      press("<C-j>")
      assert.equals(3, #lines(handle))
      assert.equals(3, cursor_line(handle), "still on 'newer', now line 3")
      press("+")
      assert.equals(5, #lines(handle), "'+' pages as well")
    end)

    it("has_more_older = false shows no hint and no extra row", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = "one" }, { time_ms = 0, content = "two" } },
        has_more_older = false,
        load_more = function()
          return {}
        end,
      })
      assert.is_false(handle.has_more_older)
      assert.equals(3, vim.api.nvim_win_get_config(handle.surf.winid).height, "2 lines + legend")
    end)
  end)

  it("CRLF, a trailing newline and a NUL byte do not leak into the buffer", function()
    handle = message_log.open({
      now_ms = function()
        return 0
      end,
      entries = {
        { time_ms = 0, content = "one\r\ntwo\r\n" },
        { time_ms = 0, content = "nul\0inside" },
      },
    })
    local got = lines(handle)
    assert.equals(3, #got, "no empty line from the trailing newline")
    assert.equals("two", got[2], "no stray carriage return")
    assert.is_nil(got[3]:find("%z"), "no NUL in the buffer")
    handle:set_collapsed(true)
    assert.truthy(
      lines(handle)[1]:match("%(%+1 more line%)$"),
      "count excludes the trailing newline"
    )
  end)

  describe("legend", function()
    it("announces the cheatsheet below the last line, with or without a 'newer' hint", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = "one" } },
      })
      local function legend_rows()
        local marks = vim.api.nvim_buf_get_extmarks(
          handle.surf.bufnr,
          handle._arrow_ns,
          0,
          -1,
          { details = true }
        )
        local rows = {}
        for _, m in ipairs(marks) do
          for _, vl in ipairs(m[4].virt_lines or {}) do
            rows[#rows + 1] = vl[1][1]
          end
        end
        return rows
      end
      local rows = legend_rows()
      assert.equals(1, #rows)
      assert.truthy(rows[1]:find("? cheatsheet", 1, true))
      assert.is_nil(table.concat(lines(handle), " "):find("cheatsheet", 1, true), "virtual only")

      handle.has_more_newer = true
      handle:set_collapsed(false)
      rows = legend_rows()
      assert.equals(2, #rows)
      assert.truthy(rows[1]:find("more below", 1, true))
      assert.truthy(rows[2]:find("? cheatsheet", 1, true))
    end)
  end)

  describe("live feed", function()
    it("a cursor on the newest entry follows an append; elsewhere it stays put", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = "one" }, { time_ms = 0, content = "two" } },
      })
      assert.equals(2, cursor_line(handle), "the first draw rests on the newest entry")
      handle:append({ { time_ms = 0, content = "three" } })
      assert.equals(3, cursor_line(handle), "followed")

      vim.api.nvim_win_set_cursor(handle.surf.winid, { 1, 0 })
      handle:append({ { time_ms = 0, content = "four" } })
      assert.equals(1, cursor_line(handle), "the entry being read did not move")
    end)

    it("newest_first starts on line 1 and follows new entries to the top", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        order = "newest_first",
        entries = { { time_ms = 0, content = "one" }, { time_ms = 0, content = "two" } },
      })
      assert.equals(1, cursor_line(handle))
      handle:append({ { time_ms = 0, content = "three" } })
      assert.equals(1, cursor_line(handle))
      assert.truthy(lines(handle)[1]:match("three$"))
    end)
  end)

  describe("closing", function()
    it("q closes the window", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      local win = handle.surf.winid
      press("q")
      assert.is_false(vim.api.nvim_win_is_valid(win))
      handle = nil
    end)

    it("<Esc> closes the window", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      local win = handle.surf.winid
      press("<Esc>")
      assert.is_false(vim.api.nvim_win_is_valid(win))
      handle = nil
    end)

    it("q / <Esc> work with a load_more set and the cheatsheet used before", function()
      handle = message_log.open({
        entries = { { time_ms = 0, content = "x" } },
        load_more = function()
          return {}
        end,
      })
      local win = handle.surf.winid
      press("?")
      press("q") -- closes the cheatsheet only
      vim.wait(200, function()
        return vim.api.nvim_get_current_win() == win
      end)
      assert.is_true(vim.api.nvim_win_is_valid(win), "the log survived the cheatsheet")
      press("<Esc>")
      assert.is_false(vim.api.nvim_win_is_valid(win))
      handle = nil
    end)
  end)

  describe("cheatsheet", function()
    it("? opens it over the log without closing the log; q gives the focus back", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      local log_win = handle.surf.winid
      press("?")
      local sheet_win = vim.api.nvim_get_current_win()
      assert.are_not.equals(log_win, sheet_win, "the sheet took the focus")
      assert.is_true(vim.api.nvim_win_is_valid(log_win), "the log is still there")
      local text = table.concat(
        vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(sheet_win), 0, -1, false),
        "\n"
      )
      assert.truthy(text:find("expand / collapse the entry", 1, true))
      assert.truthy(text:find("load older entries", 1, true))
      assert.truthy(text:find("close", 1, true))

      press("q")
      vim.wait(500, function()
        return vim.api.nvim_get_current_win() == log_win
      end)
      assert.is_false(vim.api.nvim_win_is_valid(sheet_win))
      assert.equals(log_win, vim.api.nvim_get_current_win(), "focus is back on the log")
      assert.is_true(vim.api.nvim_win_is_valid(log_win))
    end)

    it("lists every key that is actually mapped in the log buffer", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      press("?")
      local sheet_buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
      local text = table.concat(vim.api.nvim_buf_get_lines(sheet_buf, 0, -1, false), "\n")
      for _, lhs in ipairs({ "<CR>", "<Tab>", "za", "zo", "zc", "<C-l>", "zR", "<C-h>", "zM" }) do
        assert.truthy(text:find(lhs, 1, true), lhs .. " is documented in the cheatsheet")
      end
      for _, lhs in ipairs({ "<C-e>", "<C-j>", "+", "<C-k>", "-", "?", "q", "<Esc>" }) do
        assert.truthy(text:find(lhs, 1, true), lhs .. " is documented in the cheatsheet")
      end
      press("q")
    end)

    it("extra_cheatsheet_lines are appended; ? again closes the sheet", function()
      handle = message_log.open({
        entries = { { time_ms = 0, content = "x" } },
        extra_cheatsheet_lines = { "custom: something" },
      })
      press("?")
      local sheet_win = vim.api.nvim_get_current_win()
      local sheet_buf = vim.api.nvim_win_get_buf(sheet_win)
      local text = table.concat(vim.api.nvim_buf_get_lines(sheet_buf, 0, -1, false), "\n")
      assert.truthy(text:find("custom: something", 1, true))
      handle:toggle_cheatsheet()
      assert.is_false(vim.api.nvim_win_is_valid(sheet_win))
    end)

    it("closing the log closes its cheatsheet too", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      press("?")
      local sheet_win = vim.api.nvim_get_current_win()
      handle:close()
      assert.is_false(vim.api.nvim_win_is_valid(sheet_win))
      handle = nil
    end)
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
