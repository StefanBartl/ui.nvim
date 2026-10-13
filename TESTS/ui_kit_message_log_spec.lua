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
      assert.equals(2, vim.api.nvim_win_get_config(handle.surf.winid).height)
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
    it("announces the cheatsheet, fold and close in the title, not in an extra row", function()
      handle = message_log.open({
        title = "Recent messages",
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = "one" } },
      })
      local title = vim.api.nvim_win_get_config(handle.surf.winid).title
      local text = type(title) == "table" and title[1] and title[1][1] or tostring(title)
      assert.truthy(text:find("Recent messages", 1, true), "keeps the caller's title")
      assert.truthy(text:find("? keys", 1, true))
      assert.truthy(text:find("<CR> fold", 1, true))
      assert.truthy(text:find("q close", 1, true))
      assert.equals(2, vim.api.nvim_win_get_config(handle.surf.winid).height, "no legend row")
    end)

    it("<CR> on a single-line entry shows a transient inline hint, not a notification", function()
      handle = message_log.open({
        entries = { { time_ms = 0, content = "just one line" }, { time_ms = 0, content = "x\n" } },
      })
      local notified = 0
      local orig = vim.notify
      vim.notify = function()
        notified = notified + 1
      end
      local hint_ns = vim.api.nvim_create_namespace("ui_kit_message_log_hint")
      local function hints()
        return vim.api.nvim_buf_get_extmarks(handle.surf.bufnr, hint_ns, 0, -1, { details = true })
      end
      press("<CR>")
      press("<CR>") -- held key: still one hint, nothing piles up
      local marks = hints()
      vim.notify = orig
      assert.equals(0, notified, "no notification (it would be recorded and shown in this log)")
      assert.equals(1, #marks)
      assert.truthy(marks[1][4].virt_text[1][1]:find("nothing to fold", 1, true))

      handle:set_collapsed(false)
      assert.equals(0, #hints(), "the next redraw drops the hint")

      -- A trailing newline does not make an entry multi-line, same as in the renderer.
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 1, 0 })
      press("<CR>")
      assert.equals(1, #hints())
    end)

    it("the hint goes away on its own", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "one line" } } })
      press("<CR>")
      local hint_ns = vim.api.nvim_create_namespace("ui_kit_message_log_hint")
      assert.equals(1, #vim.api.nvim_buf_get_extmarks(handle.surf.bufnr, hint_ns, 0, -1, {}))
      local gone = vim.wait(3000, function()
        return #vim.api.nvim_buf_get_extmarks(handle.surf.bufnr, hint_ns, 0, -1, {}) == 0
      end)
      assert.is_true(gone)
    end)
  end)

  describe("reading position", function()
    local function stack_entries()
      local content = {}
      for i = 1, 30 do
        content[i] = "frame " .. i
      end
      return {
        { time_ms = 0, content = "first" },
        { time_ms = 0, content = table.concat(content, "\n") },
        { time_ms = 0, content = "newest" },
      }
    end

    ---@return table
    local function open_stack()
      local h = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = stack_entries(),
        load_more = function()
          return { { time_ms = 0, content = "older" } }
        end,
      })
      vim.api.nvim_win_call(h.surf.winid, function()
        vim.fn.winrestview({ topline = 12, lnum = 18 }) -- frame 17 of the long entry
      end)
      return h
    end

    local function view(h)
      return vim.api.nvim_win_call(h.surf.winid, function()
        local v = vim.fn.winsaveview()
        return { lnum = v.lnum, topline = v.topline }
      end)
    end

    it("a live append keeps cursor and view inside the long entry being read", function()
      handle = open_stack()
      local before = view(handle)
      assert.equals(18, before.lnum)
      handle:append({ { time_ms = 0, content = "live" } })
      assert.same(before, view(handle), "same line of the entry, same screen row")
    end)

    it("load_more('older') keeps the same line on the same screen row", function()
      handle = open_stack()
      local before = view(handle)
      handle:load_more("older")
      local after = view(handle)
      assert.equals(before.lnum + 1, after.lnum, "one older entry pushed everything down by one")
      assert.equals(before.topline + 1, after.topline, "and the view moved with it")
    end)

    it("folding the entry puts the cursor on its first line", function()
      handle = open_stack()
      press("zc")
      assert.equals(2, cursor_line(handle))
    end)

    it("a multi-line live entry is followed to its last line, not just its header", function()
      local entries = {}
      for i = 1, 40 do
        entries[i] = { time_ms = 0, content = "line " .. i }
      end
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = entries,
      })
      assert.equals(40, cursor_line(handle))
      handle:append({ { time_ms = 0, content = "a\nb\nc\nd" } })
      assert.equals(
        vim.api.nvim_buf_line_count(handle.surf.bufnr),
        cursor_line(handle),
        "tail -f rests on the last line"
      )
      vim.api.nvim_win_set_cursor(handle.surf.winid, { 1, 0 })
      handle:append({ { time_ms = 0, content = "e\nf" } })
      assert.equals(1, cursor_line(handle), "a reader elsewhere is not moved")
    end)
  end)

  describe("window size", function()
    local cols

    before_each(function()
      cols = vim.o.columns
      vim.o.columns = 200
    end)

    after_each(function()
      vim.o.columns = cols
    end)

    it("grows to a long message instead of cutting it off, and never shrinks", function()
      local long = string.rep("abcdefghij", 12)
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = long } },
      })
      local w = vim.api.nvim_win_get_config(handle.surf.winid).width
      assert.is_true(w >= #long + 8, "wide enough for '[0s ago] ' + the message + the fold mark")
      handle:append({ { time_ms = 0, content = "short" } })
      assert.equals(w, vim.api.nvim_win_get_config(handle.surf.winid).width, "no jitter")
    end)

    it("keeps its default width for short messages and respects an explicit width", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "short" } } })
      local default_w = vim.api.nvim_win_get_config(handle.surf.winid).width
      handle:append({ { time_ms = 0, content = "short again" } })
      assert.equals(default_w, vim.api.nvim_win_get_config(handle.surf.winid).width)
      handle:close()

      handle = message_log.open({
        width = 30,
        entries = { { time_ms = 0, content = string.rep("x", 100) } },
      })
      assert.equals(30, vim.api.nvim_win_get_config(handle.surf.winid).width)
    end)

    it("is capped to the editor and wide enough for the title", function()
      handle = message_log.open({
        title = "A fairly long caller title here",
        entries = { { time_ms = 0, content = string.rep("y", 500) } },
      })
      local cfg = vim.api.nvim_win_get_config(handle.surf.winid)
      assert.is_true(cfg.width <= vim.o.columns - 4)
      assert.is_true(cfg.col + cfg.width + 2 <= vim.o.columns, "stays on screen")
      handle:close()
      handle = message_log.open({
        title = "A fairly long caller title here",
        entries = { { time_ms = 0, content = "x" } },
      })
      local title_w =
        vim.fn.strdisplaywidth("A fairly long caller title here  ? keys | <CR> fold | q close")
      assert.is_true(vim.api.nvim_win_get_config(handle.surf.winid).width >= title_w)
    end)

    it("stays centred as the content grows", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = { { time_ms = 0, content = "one" } },
      })
      for _, n in ipairs({ 5, 12 }) do
        local more = {}
        for i = 1, n do
          more[i] = { time_ms = 0, content = "m" .. i }
        end
        handle:append(more)
        local cfg = vim.api.nvim_win_get_config(handle.surf.winid)
        assert.equals(math.max(0, math.floor((vim.o.lines - cfg.height) / 2 - 1)), cfg.row)
        assert.equals(math.max(0, math.floor((vim.o.columns - cfg.width) / 2)), cfg.col)
      end
    end)

    it("a cursor-relative popup is not re-centred", function()
      handle = message_log.open({
        relative = "cursor",
        entries = { { time_ms = 0, content = "one" } },
      })
      local before = vim.api.nvim_win_get_config(handle.surf.winid)
      local more = {}
      for i = 1, 6 do
        more[i] = { time_ms = 0, content = "m" .. i }
      end
      handle:append(more)
      local after = vim.api.nvim_win_get_config(handle.surf.winid)
      assert.equals(before.relative, after.relative)
      assert.equals(before.row, after.row)
      assert.equals(before.col, after.col)
    end)
  end)

  describe("entry content", function()
    it("a lone CR (a progress bar) keeps only its last frame; \\r\\r\\n is a line break", function()
      handle = message_log.open({
        now_ms = function()
          return 0
        end,
        entries = {
          { time_ms = 0, content = "10%\r20%\r30%" },
          { time_ms = 0, content = "a\r\r\nb\r\r\n" },
          { time_ms = 0, content = "done\r" },
        },
      })
      local got = lines(handle)
      assert.equals("[0s ago] 30%", got[1])
      assert.equals("[0s ago] a", got[2])
      assert.equals("b", got[3])
      assert.equals("[0s ago] done", got[4])
      for _, l in ipairs(got) do
        assert.is_nil(l:find("\r", 1, true))
      end
    end)

    it(
      "the entry list is the caller's entries, not copies: set_entry_collapsed(value, entry)",
      function()
        local multi = { time_ms = 0, content = "head\nbody" }
        handle = message_log.open({
          now_ms = function()
            return 0
          end,
          collapsed_default = true,
          entries = { { time_ms = 0, content = "other" }, multi },
        })
        assert.equals(2, #lines(handle))
        handle:set_entry_collapsed(false, multi)
        assert.equals(3, #lines(handle), "the entry handed to open() can be addressed")
      end
    )
  end)

  describe("cheatsheet keys and focus", function()
    local function gone(win)
      return vim.wait(500, function()
        return not vim.api.nvim_win_is_valid(win)
      end)
    end

    it("? and g? inside the sheet close it, as README says", function()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      local log_win = handle.surf.winid
      for _, key in ipairs({ "?", "g?" }) do
        press("?")
        local sheet = vim.api.nvim_get_current_win()
        assert.are_not.equals(log_win, sheet)
        press(key)
        assert.is_true(gone(sheet))
        vim.wait(300, function()
          return vim.api.nvim_get_current_win() == log_win
        end)
        assert.equals(log_win, vim.api.nvim_get_current_win(), "back on the log")
      end
    end)

    it("after the sheet the log is armed again: leaving it closes the log", function()
      local base = vim.api.nvim_get_current_win()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      local log_win = handle.surf.winid
      press("?")
      press("q")
      vim.wait(300, function()
        return vim.api.nvim_get_current_win() == log_win
      end)
      vim.api.nvim_set_current_win(base)
      assert.is_true(gone(log_win), "dismiss-on-focus-lost works again")
      handle = nil
    end)

    it("with close_on_focus_lost = false the log survives the sheet and a focus change", function()
      local base = vim.api.nvim_get_current_win()
      handle = message_log.open({
        close_on_focus_lost = false,
        entries = { { time_ms = 0, content = "x" } },
      })
      local log_win = handle.surf.winid
      press("?")
      press("q")
      vim.wait(300, function()
        return vim.api.nvim_get_current_win() == log_win
      end)
      assert.is_true(vim.api.nvim_win_is_valid(log_win))
      vim.api.nvim_set_current_win(base)
      vim.wait(200)
      assert.is_true(vim.api.nvim_win_is_valid(log_win), "opted out of dismissal")
    end)

    it("moving to another window while the sheet is up closes the sheet and the log", function()
      local base = vim.api.nvim_get_current_win()
      handle = message_log.open({ entries = { { time_ms = 0, content = "x" } } })
      local log_win = handle.surf.winid
      press("?")
      local sheet = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(base)
      assert.is_true(gone(sheet))
      assert.is_true(gone(log_win))
      handle = nil
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
