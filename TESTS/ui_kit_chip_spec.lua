-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.chip`: the persistent editor-corner status indicator (mount once,
--- update in place via refresh, unmount) -- as opposed to `kit.toast`'s
--- ephemeral, auto-dismissing message. Covers: visibility driven by an empty
--- vs. non-empty `text`, `refresh` picking up a changed provider, custom vs.
--- highlight-group colour, `pulse` reverting after its duration, and
--- `unmount` actually closing the window.

local chip = require("ui.kit").chip

--- The one floating window a spec's own `chip.mount` produced -- specs run
--- sequentially and each cleans up in `after_each`, so at most one is ever
--- live at a time except in the "two chips" test, which looks up its own
--- pair by highlight instead of calling this.
---@return integer|nil
local function chip_window()
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(w).relative == "editor" then
      return w
    end
  end
  return nil
end

---@param win integer|nil
---@return string
local function first_line(win)
  if not win then
    return ""
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
end

---@param win integer|nil
---@return string[]
local function all_lines(win)
  if not win then
    return {}
  end
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

---@param win integer|nil
---@return { fg?: integer, bg?: integer }
local function normal_hl(win)
  if not win then
    return {}
  end
  local winhl = vim.api.nvim_get_option_value("winhighlight", { win = win })
  local group = winhl:match("NormalFloat:([%w_]+)")
  if not group then
    return {}
  end
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  return ok and hl or {}
end

describe("ui.kit.chip", function()
  after_each(function()
    -- Every test below mounts under one of these two ids; unmounting both,
    -- always, keeps a failure in one test from leaking a window into the
    -- next (chip state is module-level, not reset between specs).
    chip.unmount("spec_a")
    chip.unmount("spec_b")
  end)

  it("stays invisible while text is empty and appears once it isn't", function()
    local visible = false
    chip.mount({
      id = "spec_a",
      text = function()
        return visible and "hello" or ""
      end,
    })
    assert.is_false(vim.tbl_contains(chip.active(), "spec_a"), "empty text: not active")

    visible = true
    chip.refresh("spec_a")
    assert.is_true(vim.tbl_contains(chip.active(), "spec_a"), "non-empty text: active")
  end)

  it("hides again once refresh sees empty text, without erroring", function()
    local text = "on"
    chip.mount({
      id = "spec_a",
      text = function()
        return text
      end,
    })
    assert.is_true(vim.tbl_contains(chip.active(), "spec_a"))

    text = ""
    chip.refresh("spec_a")
    assert.is_false(vim.tbl_contains(chip.active(), "spec_a"))
  end)

  it("an explicit visible = false wins over non-empty text", function()
    chip.mount({ id = "spec_a", text = "ignored", visible = false })
    assert.is_false(vim.tbl_contains(chip.active(), "spec_a"))
  end)

  -- Regression: resolve_visible() used the classic `a and b or c` idiom
  -- (`ok and out and true or (ok and false or nil)`), which cannot express
  -- a `visible` PROVIDER (a function, not a literal) returning `false` --
  -- `ok and out` collapses to `false` the moment `out` is `false`, so the
  -- whole expression always fell through to `nil` ("not set"), and
  -- M.refresh()'s own text-derived fallback then re-showed the chip
  -- regardless. A real consumer hit this live: sessions.nvim's chip
  -- auto-hide timer flips its `visible = function() return X end` closure
  -- to return `false` and calls refresh() -- with the bug, the chip never
  -- actually hid, no matter how long `timeout_ms` allowed.
  it("a visible PROVIDER (function) returning false wins over non-empty text", function()
    chip.mount({
      id = "spec_a",
      text = "ignored",
      visible = function()
        return false
      end,
    })
    assert.is_false(
      vim.tbl_contains(chip.active(), "spec_a"),
      "a visible() function returning false must hide the chip, same as a literal false"
    )
  end)

  it("updates the buffer content in place on refresh (no re-mount needed)", function()
    local text = "first"
    chip.mount({
      id = "spec_a",
      text = function()
        return text
      end,
    })
    local win = assert(chip_window(), "chip window found")
    assert.equals("first", first_line(win))

    text = "second"
    chip.refresh("spec_a")
    -- refresh() updates the existing window rather than closing/reopening it
    assert.equals(win, chip_window(), "same window reused")
    assert.equals("second", first_line(win))
  end)

  it("splits an embedded newline into a multi-line box", function()
    chip.mount({ id = "spec_a", text = "AB-1234\nGrid stays red" })
    local win = assert(chip_window(), "chip window found")
    assert.same({ "AB-1234", "Grid stays red" }, all_lines(win))
    assert.equals(2, vim.api.nvim_win_get_config(win).height)
  end)

  it("a multi-line chip's width follows its widest line", function()
    chip.mount({ id = "spec_a", text = "short\na much longer second line" })
    local win = assert(chip_window(), "chip window found")
    local width = vim.api.nvim_win_get_config(win).width
    assert.is_true(width >= vim.fn.strdisplaywidth("a much longer second line"))
  end)

  it("growing from one line to two on refresh resizes the window in place", function()
    local text = "one line"
    chip.mount({
      id = "spec_a",
      text = function()
        return text
      end,
    })
    local win = assert(chip_window(), "chip window found")
    assert.equals(1, vim.api.nvim_win_get_config(win).height)

    text = "one line\nand a second"
    chip.refresh("spec_a")
    assert.equals(win, chip_window(), "same window reused")
    assert.equals(2, vim.api.nvim_win_get_config(win).height)
    assert.same({ "one line", "and a second" }, all_lines(win))
  end)

  it("mounting the same id twice reconfigures instead of duplicating", function()
    chip.mount({ id = "spec_a", text = "a" })
    chip.mount({ id = "spec_a", text = "a" })
    local count = 0
    for _, id in ipairs(chip.active()) do
      if id == "spec_a" then
        count = count + 1
      end
    end
    assert.equals(1, count)
  end)

  it("re-mounting with only shape keeps the earlier text/color (no wipe)", function()
    chip.mount({ id = "spec_a", text = "a", color = { fg = "#ff0000", bg = "#00ff00" } })
    chip.mount({ id = "spec_a", shape = "rect" })
    assert.is_true(
      vim.tbl_contains(chip.active(), "spec_a"),
      "still visible after the shape-only remount"
    )
    local win = assert(chip_window(), "chip window found")
    assert.equals("a", first_line(win), "text survived a remount that didn't repeat it")
    local hl = normal_hl(win)
    assert.equals(0xff0000, hl.fg, "color survived a remount that didn't repeat it")
  end)

  it("switching shape on an already-open chip actually changes its border", function()
    chip.mount({ id = "spec_a", text = "a", shape = "rounded" })
    local win = assert(chip_window(), "chip window found")
    local border_before = vim.api.nvim_win_get_config(win).border
    assert.is_not_nil(border_before, "rounded starts out bordered")

    chip.mount({ id = "spec_a", shape = "rect" })
    local win2 = assert(chip_window(), "chip window still found after the shape switch")
    local border_after = vim.api.nvim_win_get_config(win2).border
    assert.equals("none", border_after, "rect has no border once switched, on the very same chip")
  end)

  it("an explicit { fg, bg } colour is applied verbatim", function()
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ff0000", bg = "#00ff00" } })
    local hl = normal_hl(assert(chip_window(), "chip window found"))
    assert.equals(0xff0000, hl.fg)
    assert.equals(0x00ff00, hl.bg)
  end)

  it('shape = "text" ignores color.bg and blends with the window instead', function()
    chip.mount({
      id = "spec_a",
      text = "x",
      shape = "text",
      color = { fg = "#ff0000", bg = "#00ff00" },
    })
    local hl_a = normal_hl(assert(chip_window(), "chip window found"))
    assert.equals(0xff0000, hl_a.fg, "fg is still applied")
    assert.is_not.equal(0x00ff00, hl_a.bg, "bg is not the custom one -- shape = text has no box")

    chip.unmount("spec_a")
    chip.mount({ id = "spec_a", text = "y", shape = "text" })
    local hl_b = normal_hl(assert(chip_window(), "chip window found"))
    assert.equals(hl_a.bg, hl_b.bg, "every text-shape chip blends with the same window background")
  end)

  it('a ColorScheme event keeps shape = "text" transparent (no box regained)', function()
    -- Regression: the ColorScheme re-tint handler used to call resolve_colors
    -- without the transparent flag, so a themed shape="text" chip regained a
    -- visible tinted background on every colorscheme change.
    chip.mount({ id = "spec_a", text = "x", shape = "text", color = "Special" })
    local win = assert(chip_window(), "chip window found")
    local before = normal_hl(win)

    vim.api.nvim_exec_autocmds("ColorScheme", {})

    local after = normal_hl(chip_window())
    assert.equals(before.bg, after.bg, "still blends with the window background after ColorScheme")
  end)

  it("VimEnter re-settles colour once startup finishes, deferred not synchronous", function()
    -- Regression (Issue 1, startup pop-in): a chip mounted before VimEnter
    -- (e.g. during a plugin's `lazy = false` spec loading) can carry a
    -- colour/position resolved from not-yet-settled startup state, and
    -- previously only reached its correct final state whenever some
    -- unrelated later event happened to call refresh() -- no defined bound,
    -- reading as an arbitrary pop-in a few seconds after startup.
    -- ensure_hooks() now re-resolves every mounted chip's colour (and
    -- reflows it) once on VimEnter, wrapped in vim.schedule() so it runs
    -- after whatever else the VimEnter event itself still has queued -- not
    -- synchronously inside the autocmd, which could still be too early.
    vim.api.nvim_set_hl(0, "SpecSettleGroup", { fg = "#111111" })
    chip.mount({ id = "spec_a", text = "x", color = "SpecSettleGroup" })
    local win = assert(chip_window(), "chip window found")
    assert.equals(0x111111, normal_hl(win).fg)

    -- Change what the colour source now resolves to -- nothing here calls
    -- refresh(), so only the settle pass can pick this up.
    vim.api.nvim_set_hl(0, "SpecSettleGroup", { fg = "#222222" })

    vim.api.nvim_exec_autocmds("VimEnter", {})
    assert.equals(
      0x111111,
      normal_hl(win).fg,
      "not re-settled synchronously inside the VimEnter autocmd"
    )

    vim.wait(200, function()
      return normal_hl(win).fg == 0x222222
    end, 10)
    assert.equals(0x222222, normal_hl(win).fg, "re-settled once the scheduled tick ran")
  end)

  it("two ids that used to sanitize the same never bleed colour (no group collision)", function()
    -- Regression: hl_group_name() used to replace every non-alnum/underscore
    -- byte with "_", so "a.b" and "a_b" collided onto the same derived
    -- highlight group -- refreshing one recoloured the other's window too.
    chip.mount({ id = "a.b", text = "one", color = { fg = "#ff0000", bg = "#000000" } })
    chip.mount({ id = "a_b", text = "two", color = { fg = "#00ff00", bg = "#000000" } })

    local by_text = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative == "editor" then
        by_text[first_line(w)] = normal_hl(w)
      end
    end
    assert.equals(0xff0000, by_text["one"] and by_text["one"].fg, 'id "a.b" keeps its own colour')
    assert.equals(
      0x00ff00,
      by_text["two"] and by_text["two"].fg,
      'id "a_b" keeps its own, different colour'
    )

    chip.unmount("a.b")
    chip.unmount("a_b")
  end)

  it("a colour-source change with unchanged pixels still keeps the themed flag fresh", function()
    -- Regression: M.refresh()'s "already applied?" check compared only
    -- fg/bg, so switching entry.color from a custom table to a highlight
    -- group (or back) while the *rendered* colour happened not to change --
    -- easy to hit on a "text" shape chip, where bg is always window_bg()
    -- regardless of the colour source -- left entry.applied_colors.themed
    -- stale. The ColorScheme handler gates its re-tint on exactly that
    -- field, so a chip that had just become theme-linked this way would
    -- silently stop re-tinting on the next colorscheme change.
    vim.api.nvim_set_hl(0, "SpecChipThemeGroup", { fg = "#ff0000" })
    chip.mount({ id = "spec_a", text = "x", shape = "text", color = { fg = "#ff0000" } })
    assert.equals(0xff0000, normal_hl(chip_window()).fg, "custom colour applied")

    -- Same rendered fg (bg is window_bg() either way on a "text" chip) as
    -- before, but now sourced from a highlight group instead of a literal.
    chip.mount({ id = "spec_a", color = "SpecChipThemeGroup" })
    assert.equals(
      0xff0000,
      normal_hl(chip_window()).fg,
      "still the same colour, nothing to repaint"
    )

    vim.api.nvim_set_hl(0, "SpecChipThemeGroup", { fg = "#00ff00" })
    vim.api.nvim_exec_autocmds("ColorScheme", {})

    assert.equals(
      0x00ff00,
      normal_hl(chip_window()).fg,
      "re-tinted on ColorScheme -- it is correctly tracked as theme-linked now"
    )
  end)

  it("a highlight-group colour resolves that group's fg, not a literal", function()
    vim.api.nvim_set_hl(0, "SpecChipTestGroup", { fg = "#123456" })
    chip.mount({ id = "spec_a", text = "x", color = "SpecChipTestGroup" })
    assert.equals(0x123456, normal_hl(chip_window()).fg)
  end)

  it("pulse overrides the colour and reverts after duration_ms", function()
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    local win = chip_window()

    chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 30 })
    assert.equals(0xff00ff, normal_hl(win).fg, "pulse colour applied immediately")

    vim.wait(200, function()
      return normal_hl(win).fg == 0xffffff
    end, 10)
    assert.equals(0xffffff, normal_hl(win).fg, "reverted to the configured colour")
  end)

  it("a pending pulse doesn't get stuck after a tab-switch reopen", function()
    -- Regression: ensure_current_tab() closes and reopens a chip's window
    -- when the active tabpage differs from the one it was drawn on.
    -- open_window() used to reuse the (still pulsing) `applied_colors` for
    -- that reopened window, and the pending pulse-revert then targeted the
    -- now-closed old window handle and silently no-oped -- leaving the chip
    -- stuck showing the pulse colour indefinitely.
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    local win_before = assert(chip_window(), "chip window found")

    chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 300 })
    assert.equals(0xff00ff, normal_hl(win_before).fg, "pulse colour applied immediately")

    vim.cmd("tabnew") -- real TabEnter -> ensure_current_tab() reopens the chip here
    local win_after = assert(chip_window(), "chip window found on the new tab")
    assert.equals(
      0xffffff,
      normal_hl(win_after).fg,
      "reopened with its real colour, not stuck mid-pulse"
    )

    vim.cmd("tabclose")
  end)

  it("pulse still reverts correctly when the chip's window is replaced mid-pulse", function()
    -- Regression: M.pulse()'s deferred revert callback used to guard on
    -- `e.win == win`, the window handle captured when the pulse started. If
    -- the chip's window closed and reopened (e.g. a hide/show cycle driven
    -- by a text change, the same shape ":LastSession"'s refresh()-then-
    -- pulse() sequence can produce) before `duration_ms` elapsed, that
    -- captured handle no longer matched the chip's *current* window and the
    -- guard silently skipped the revert. Reverting onto whatever window is
    -- current for the id (not the one the pulse started on) fixes it.
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 60 })

    -- Replace the window mid-pulse: hide (closes it) then show again (opens
    -- a brand new one).
    chip.mount({ id = "spec_a", text = "" })
    chip.mount({ id = "spec_a", text = "x" })
    local win_after = assert(chip_window(), "chip window found after replacement")

    -- Past the original pulse's duration_ms: its deferred callback has now
    -- fired against the *replacement* window and must not error or leave it
    -- showing anything but the configured colour.
    vim.wait(200, function()
      return normal_hl(win_after).fg == 0xffffff
    end, 10)
    assert.equals(
      0xffffff,
      normal_hl(win_after).fg,
      "reverted to the configured colour on the replacement window"
    )
  end)

  it(
    "an earlier pulse's revert doesn't cut a later pulse short across a window replacement",
    function()
      -- Regression, found by adversarial review of the fix just above: once
      -- the revert callback stopped checking window *identity* and only
      -- checked window *validity*, an earlier pulse's callback -- now
      -- matching whatever window is currently live -- could fire on top of a
      -- later, still-active pulse on a *different* window for the same id,
      -- reverting it early. Only reachable when the window is replaced
      -- between the two pulse() calls (unchanged, same-window overlapping
      -- pulses already raced before this fix, on purpose out of scope here).
      -- A per-entry generation counter (same shape as sessions.nvim's own
      -- `hide_generation`) makes each pulse only revertible by its own
      -- callback.
      chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
      chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 40 })

      -- Replace the window while pulse 1 is still pending.
      chip.mount({ id = "spec_a", text = "" })
      chip.mount({ id = "spec_a", text = "x" })
      local win_after = assert(chip_window(), "chip window found after replacement")

      -- Start a second, longer pulse on the replacement window.
      chip.pulse("spec_a", { color = { fg = "#00ff00", bg = "#000000" }, duration_ms = 200 })
      assert.equals(0x00ff00, normal_hl(win_after).fg, "second pulse colour applied immediately")

      -- Past pulse 1's duration_ms (40ms) but well before pulse 2's (200ms):
      -- pulse 1's stale callback must not revert pulse 2's still-active colour.
      vim.wait(90, function()
        return normal_hl(win_after).fg ~= 0x00ff00
      end, 10)
      assert.equals(
        0x00ff00,
        normal_hl(win_after).fg,
        "pulse 2 still showing -- not cut short by pulse 1's stale revert"
      )

      -- Past pulse 2's own duration_ms: it reverts on schedule, on its own.
      vim.wait(300, function()
        return normal_hl(win_after).fg == 0xffffff
      end, 10)
      assert.equals(0xffffff, normal_hl(win_after).fg, "pulse 2 reverted on its own schedule")
    end
  )

  it("a stale pulse from an unmounted-then-remounted id doesn't cut the new pulse short", function()
    -- Regression, found by a second round of adversarial review of the
    -- generation-counter fix just above: the counter lives on the
    -- per-id `entry` table, but M.unmount(id) discards that table
    -- (`chips[id] = nil`) without cancelling its still-pending pulse
    -- timer, and a subsequent M.mount(id, ...) allocates a brand-new
    -- entry whose OWN counter restarts from scratch. A stale callback
    -- from a pulse on the old, orphaned entry can then land on the same
    -- generation number as the new entry's own first pulse purely by
    -- numeric coincidence, and (since the old fix only checked the
    -- generation counter, not which entry it belongs to) wrongly revert
    -- it early. Capturing the entry TABLE itself, and requiring
    -- `chips[id]` to still point at that exact table, closes the gap: a
    -- callback from an unmounted entry can never match again, no matter
    -- what its generation reads.
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 40 })

    -- Tear the chip down and remount it under the SAME id while pulse 1
    -- is still pending -- a brand-new entry table, generation reset.
    chip.unmount("spec_a")
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    local win_after = assert(chip_window(), "chip window found after remount")

    -- Its own first pulse also starts at generation 1 -- the exact
    -- numeric collision with pulse 1's stale callback.
    chip.pulse("spec_a", { color = { fg = "#00ff00", bg = "#000000" }, duration_ms = 200 })
    assert.equals(0x00ff00, normal_hl(win_after).fg, "second pulse colour applied immediately")

    vim.wait(90, function()
      return normal_hl(win_after).fg ~= 0x00ff00
    end, 10)
    assert.equals(
      0x00ff00,
      normal_hl(win_after).fg,
      "pulse 2 still showing -- not cut short by pulse 1's stale, now-orphaned revert"
    )

    vim.wait(300, function()
      return normal_hl(win_after).fg == 0xffffff
    end, 10)
    assert.equals(0xffffff, normal_hl(win_after).fg, "pulse 2 reverted on its own schedule")
  end)

  it("refresh() during an active pulse doesn't cut it short", function()
    -- Regression, found by a third round of adversarial review: none of the
    -- fixes above touch M.refresh()'s own colour reconciliation, which
    -- unconditionally re-applies whatever `entry.color` resolves to and
    -- never knew a pulse could be in flight. Any refresh() call during
    -- duration_ms -- sessions.nvim wires it into ordinary dirty-tracking
    -- autocmds (BufAdd/BufDelete/WinNew/WinClosed/...), so this fires on
    -- nearly every real pulse -- used to snap the colour straight back
    -- before the pulse's own revert ever ran.
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 200 })
    local win = assert(chip_window(), "chip window found")
    assert.equals(0xff00ff, normal_hl(win).fg, "pulse colour applied immediately")

    chip.refresh("spec_a") -- nothing else changed; simulates an unrelated dirty-tracking event
    assert.equals(0xff00ff, normal_hl(win).fg, "refresh() left the active pulse colour alone")

    vim.wait(300, function()
      return normal_hl(win).fg == 0xffffff
    end, 10)
    assert.equals(0xffffff, normal_hl(win).fg, "still reverted on its own schedule afterwards")
  end)

  it("mount() during an active pulse doesn't cut it short", function()
    -- Same bug, the other real trigger the review flagged: M.mount() always
    -- tail-calls M.refresh() at its end, so re-mounting an id (even to
    -- change something unrelated to colour) during a pending pulse hit the
    -- exact same unconditional colour reconciliation.
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 200 })
    local win = assert(chip_window(), "chip window found")

    chip.mount({ id = "spec_a", text = "x" }) -- re-mount, color left unspecified (unchanged)
    assert.equals(0xff00ff, normal_hl(win).fg, "mount() left the active pulse colour alone")

    vim.wait(300, function()
      return normal_hl(win).fg == 0xffffff
    end, 10)
    assert.equals(0xffffff, normal_hl(win).fg, "still reverted on its own schedule afterwards")
  end)

  it("a window replacement mid-pulse ends pulse_active too, not just the pulse colour", function()
    -- Regression, found by a fourth round of adversarial review: open_window()
    -- always repaints the *steady* colour when a chip's window gets
    -- (re)created (e.g. ensure_current_tab()'s tab-switch reopen) -- by
    -- design, so a reopened chip is never stuck showing a stale pulse
    -- colour. But it left `entry.pulse_active` untouched, still `true`,
    -- even though the pulse's visual effect had just ended right there --
    -- so a legitimate, unrelated colour change (a plain mount(id,
    -- {color=...}), or a ColorScheme re-tint) made afterwards, but still
    -- within the original pulse's duration_ms, was wrongly deferred: it
    -- updated entry.color but M.refresh()'s colour reconciliation kept
    -- skipping it (pulse_active still read `true`) until the stale pulse's
    -- own callback eventually happened to catch up.
    chip.mount({ id = "spec_a", text = "x", color = { fg = "#ffffff", bg = "#000000" } })
    chip.pulse("spec_a", { color = { fg = "#ff00ff", bg = "#0000ff" }, duration_ms = 500 })

    vim.cmd("tabnew") -- real TabEnter -> ensure_current_tab() reopens the chip here
    local win_after = assert(chip_window(), "chip window found on the new tab")
    assert.equals(0xffffff, normal_hl(win_after).fg, "reopened showing the steady colour")

    -- A brand new, unrelated colour change, still well inside the original
    -- pulse's 500ms window -- must apply immediately, not wait for it.
    chip.mount({ id = "spec_a", color = { fg = "#00ff00", bg = "#000000" } })
    assert.equals(
      0x00ff00,
      normal_hl(win_after).fg,
      "the new colour applied right away, not deferred behind the ended pulse"
    )

    vim.cmd("tabclose")
  end)

  it("a left-anchored chip sits flush against the screen edge (col 0)", function()
    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-left" })
    local win = assert(chip_window(), "chip window found")
    assert.equals(0, vim.api.nvim_win_get_config(win).col, "col 0, no inset")
  end)

  it("a right-anchored chip stays inset from the screen edge", function()
    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-right" })
    local win = assert(chip_window(), "chip window found")
    local col = vim.api.nvim_win_get_config(win).col
    assert.is_true(col > 0, "not flush against the right edge")
  end)

  it("row_offset/col_offset nudge the computed placement, on top of anchor/dock", function()
    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-left" })
    local base_win = assert(chip_window(), "chip window found")
    local base = vim.api.nvim_win_get_config(base_win).row
    chip.unmount("spec_a")

    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-left", row_offset = 2, col_offset = 3 })
    local win = assert(chip_window(), "chip window found")
    local cfg = vim.api.nvim_win_get_config(win)
    assert.equals(base + 2, cfg.row, "row_offset adds to the computed row")
    assert.equals(3, cfg.col, "col_offset adds to the computed col (0 + 3)")
  end)

  it("col_offset = 0 explicitly clears a previously set offset", function()
    -- `0` is truthy in Lua, and `sanitize_offset(0)` returns `0` unchanged
    -- -- confirms the `opts.col_offset ~= nil` guard still lets an honest,
    -- explicit `0` overwrite a previous nonzero value rather than being
    -- mistaken for "not passed this call".
    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-left", col_offset = 5 })
    chip.mount({ id = "spec_a", text = "x", col_offset = 0 })
    local win = assert(chip_window(), "chip window found")
    local cfg = vim.api.nvim_win_get_config(win)
    assert.equals(0, cfg.col, "col_offset = 0 overwrites the earlier 5, not kept")
  end)

  it("a non-numeric row_offset/col_offset sanitizes to 0 instead of crashing mount()", function()
    -- Regression, found by adversarial review, medium severity, live-
    -- reproduced: row_offset/col_offset had no type check at all. A
    -- non-number reaching reflow()'s `row = row + entry.row_offset`
    -- throws there (arithmetic on e.g. a table), OUTSIDE the one pcall
    -- that only wraps the later nvim_win_set_config call -- aborting that
    -- whole reflow() pass for every anchor group, not just this chip.
    -- ui.kit.chip is a shared primitive ~20 sibling plugins mount chips
    -- through, so a malformed value from any one caller's own (possibly
    -- unvalidated) config must never be able to take the others down too.
    assert.has_no.errors(function()
      chip.mount({
        id = "spec_a",
        text = "x",
        anchor = "bottom-left",
        row_offset = true,
        col_offset = {},
      })
    end)
    local win = assert(chip_window(), "chip window found")
    local cfg = vim.api.nvim_win_get_config(win)
    assert.equals(0, cfg.col, "a non-numeric offset sanitizes to 0, not left as garbage")
  end)

  it("NaN/Infinity row_offset/col_offset sanitize to 0 instead of stranding the chip", function()
    -- Same finding, the other half: NaN and +-Infinity both satisfy
    -- Lua's `type(v) == \"number\"`, so a bare type check alone would not
    -- have caught them -- and nvim_win_set_config accepts and silently
    -- STORES either with no validation or clamping (confirmed live via
    -- the review's own headless reproduction), which would otherwise
    -- strand the chip at an undiagnosable screen position with nothing
    -- to point at why.
    chip.mount({
      id = "spec_a",
      text = "x",
      anchor = "bottom-left",
      row_offset = 0 / 0, -- NaN
      col_offset = math.huge,
    })
    local win = assert(chip_window(), "chip window found")
    local cfg = vim.api.nvim_win_get_config(win)
    assert.equals(0, cfg.col, "col_offset = math.huge sanitizes to 0")
    assert.is_true(
      cfg.row == cfg.row,
      "row_offset = NaN sanitizes to 0, not left as NaN (NaN ~= NaN)"
    )
  end)

  it("a bottom-anchored chip leaves the statusline row free", function()
    local saved = vim.o.laststatus
    vim.o.laststatus = 2
    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-right", shape = "rect" })
    local win = assert(chip_window(), "chip window found")
    local row = vim.api.nvim_win_get_config(win).row
    -- The statusline sits one row above the cmdline; a borderless ("rect")
    -- chip is 1 row tall, so its own row must land one more row up than
    -- that -- landing ON `lines - cmdheight - 1` would draw it over the
    -- statusline instead of above it (the bug this reserves against).
    assert.is_true(
      row < vim.o.lines - vim.o.cmdheight - 1,
      ("row %d overlaps the statusline"):format(row)
    )
    vim.o.laststatus = saved
  end)

  it("a bottom-anchored chip sits right above the cmdline when laststatus is 0", function()
    local saved = vim.o.laststatus
    vim.o.laststatus = 0
    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-right", shape = "rect" })
    local win = assert(chip_window(), "chip window found")
    local row = vim.api.nvim_win_get_config(win).row
    -- No statusline drawn at all -- nothing to reserve, so the chip may sit
    -- flush against the cmdline the same as before this fix.
    assert.equals(vim.o.lines - vim.o.cmdheight - 1, row)
    vim.o.laststatus = saved
  end)

  it("does not count the chip's own float as a second real window (laststatus = 1)", function()
    local saved = vim.o.laststatus
    vim.o.laststatus = 1
    -- Precondition: exactly one real window before mounting -- otherwise
    -- this wouldn't exercise the bug at all (a genuine second split DOES
    -- legitimately trip laststatus=1's statusline).
    assert.equals(1, #vim.api.nvim_tabpage_list_wins(0))

    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-right", shape = "rect" })
    local win = assert(chip_window(), "chip window found")
    local row = vim.api.nvim_win_get_config(win).row
    -- The chip's own float must not count toward laststatus=1's "more than
    -- one window" check -- real Neovim draws no statusline for a lone real
    -- window here, so the chip may sit flush against the cmdline, same as
    -- the laststatus=0 case above.
    assert.equals(vim.o.lines - vim.o.cmdheight - 1, row)
    vim.o.laststatus = saved
  end)

  it('shape = "dock_left" gets a rounded-except-left-edge border', function()
    chip.mount({ id = "spec_a", text = "x", shape = "dock_left" })
    local win = assert(chip_window(), "chip window found")
    assert.same(
      { "", "─", "╮", "│", "╯", "─", "", "" },
      vim.api.nvim_win_get_config(win).border
    )
  end)

  it("a docked chip sits flush on the statusline row, no gap above it", function()
    local saved = vim.o.laststatus
    vim.o.laststatus = 2
    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-left", dock = true })
    local win = assert(chip_window(), "chip window found")
    local cfg = vim.api.nvim_win_get_config(win)
    assert.equals(vim.o.lines - vim.o.cmdheight - 1, cfg.row, "row lands ON the statusline row")
    assert.equals(0, cfg.col, "flush left, no gap")
    vim.o.laststatus = saved
  end)

  it("a docked dock_left chip is ALSO flush at col 0, same as any other shape", function()
    -- History: a brief `col = -1` "fix" lived here (found live, real
    -- terminal screenshots showed a ~1-cell gap before the chip's visible
    -- content) on the theory that Neovim reserves a screen column for
    -- `dock_left`'s blank (`""`) left corners/edge even though nothing is
    -- drawn there. That theory holds in isolation, but wasn't the actual
    -- cause: before/after screenshots with the "fix" applied showed the
    -- chip's first visible pixel at the exact same screen column, and the
    -- real source turned out to be this user's own terminal emulator's
    -- `window_padding` setting (1 full cell on every side, set
    -- deliberately for an unrelated image-placement feature) -- padding
    -- applied by the terminal around its whole grid, which no `col` value
    -- on any Neovim floating window can reach into or compensate for.
    -- Reverted; `col = 0` is correct for `dock_left` same as any other
    -- left-anchored shape.
    local saved = vim.o.laststatus
    vim.o.laststatus = 2
    chip.mount({
      id = "spec_a",
      text = "x",
      anchor = "bottom-left",
      dock = true,
      shape = "dock_left",
    })
    local win = assert(chip_window(), "chip window found")
    local cfg = vim.api.nvim_win_get_config(win)
    assert.equals(0, cfg.col, "flush left, no gap, no shape-specific offset")
    vim.o.laststatus = saved
  end)

  it("a docked chip degrades to the ordinary placement without a statusline row", function()
    -- `dock` is never a hard requirement on a real statusline row actually
    -- being there (laststatus = 0, or no statusline plugin active) -- it
    -- degrades to exactly the placement a non-docked chip gets, not some
    -- other row.
    local saved = vim.o.laststatus
    vim.o.laststatus = 0

    chip.mount({ id = "spec_b", text = "x", anchor = "bottom-left" })
    local reference_win = assert(chip_window(), "reference chip window found")
    local reference_row = vim.api.nvim_win_get_config(reference_win).row
    chip.unmount("spec_b")

    chip.mount({ id = "spec_a", text = "x", anchor = "bottom-left", dock = true })
    local docked_win = assert(chip_window(), "docked chip window found")
    local docked_row = vim.api.nvim_win_get_config(docked_win).row

    assert.equals(reference_row, docked_row, "same placement a non-docked chip would get")
    vim.o.laststatus = saved
  end)

  it("a function-valued colour resolves fresh on every refresh", function()
    local current = "#ffffff"
    chip.mount({
      id = "spec_a",
      text = "x",
      color = function()
        return { fg = current, bg = "#000000" }
      end,
    })
    local win = assert(chip_window(), "chip window found")
    assert.equals(0xffffff, normal_hl(win).fg, "initial function-resolved colour applied")

    current = "#00ff00"
    chip.refresh("spec_a")
    assert.equals(
      0x00ff00,
      normal_hl(win).fg,
      "re-resolved fresh on refresh, not cached from mount time"
    )
  end)

  it("track_mode fires exactly one extra refresh per ModeChanged when on, none when off", function()
    local calls = 0
    chip.mount({
      id = "spec_a",
      text = function()
        calls = calls + 1
        return "x"
      end,
      track_mode = true,
    })

    local before = calls
    vim.api.nvim_exec_autocmds("ModeChanged", {})
    assert.equals(before + 1, calls, "exactly one extra refresh from ModeChanged while tracking")

    chip.mount({ id = "spec_a", track_mode = false })
    local after_off = calls
    vim.api.nvim_exec_autocmds("ModeChanged", {})
    assert.equals(after_off, calls, "no extra refresh once tracking is turned back off")
  end)

  it(
    "enabling track_mode on one chip doesn't wipe the shared hooks group for every other chip",
    function()
      -- Regression, found by adversarial review: ensure_mode_tracking() used
      -- to call autocmd.group("UiKitChip", true) -- the `true` (clear)
      -- argument re-clears an ALREADY-EXISTING group instead of just looking
      -- it up (lib.nvim.bindings.autocmd's own documented behaviour), wiping
      -- every autocmd already registered in it -- ensure_hooks()'s own
      -- VimResized/TabEnter/ColorScheme/VimEnter, and any OTHER chip's own
      -- ModeChanged tracker -- the moment ANY chip opted into track_mode.
      -- Silent: no error, nothing logged, chips just silently stopped
      -- re-tinting/repositioning/following tabs for the rest of the session.
      chip.mount({ id = "spec_a", text = "x" }) -- ensures the shared group/hooks already exist
      local before = {}
      for _, au in ipairs(vim.api.nvim_get_autocmds({ group = "UiKitChip" })) do
        before[au.id] = true
      end
      assert.is_true(next(before) ~= nil, "the shared group already has autocmds before this")

      chip.mount({ id = "spec_b", text = "y", track_mode = true })

      local after = {}
      for _, au in ipairs(vim.api.nvim_get_autocmds({ group = "UiKitChip" })) do
        after[au.id] = true
      end
      for id in pairs(before) do
        assert.is_true(after[id], "pre-existing autocmd " .. id .. " survived enabling track_mode")
      end
    end
  )

  it(
    "a tab-switch reopen doesn't leak a duplicate window when a consumer's "
      .. "WinClosed/WinNew autocmd calls refresh() reentrantly",
    function()
      -- Regression: a consumer (e.g. sessions.nvim) wires a *generic*
      -- WinClosed/WinNew autocmd (no pattern -- fires for every window) to
      -- chip.refresh() for its own bookkeeping. ensure_current_tab()'s
      -- close-then-reopen cycle on TabEnter fires exactly those events for
      -- the chip's OWN window mid-transition, so the reentrant refresh() used
      -- to see a momentarily nil/invalid entry.win and open a second window
      -- that never got closed again -- a leaked duplicate chip.
      local group = vim.api.nvim_create_augroup("SpecChipReentrancy", { clear = true })
      vim.api.nvim_create_autocmd({ "WinClosed", "WinNew" }, {
        group = group,
        callback = function()
          chip.refresh("spec_a")
        end,
      })

      chip.mount({ id = "spec_a", text = "x" })
      vim.cmd("tabnew") -- real TabEnter -> ensure_current_tab() closes+reopens the chip here

      -- The assertion itself runs inside a pcall so the augroup/tab cleanup
      -- below always happens, even when it fails -- which is exactly when a
      -- regression of the guard this test exists to catch would otherwise
      -- leak a pattern-less WinClosed/WinNew autocmd and an orphaned tab
      -- into every test that runs after this one.
      local ok, err = pcall(function()
        local wins = {}
        for _, w in ipairs(vim.api.nvim_list_wins()) do
          if vim.api.nvim_win_get_config(w).relative == "editor" then
            wins[#wins + 1] = w
          end
        end
        assert.equals(1, #wins, "exactly one chip window survives the reopen, no leaked duplicate")
      end)

      vim.api.nvim_del_augroup_by_id(group)
      vim.cmd("tabclose")
      -- `tabclose` only closes windows on the tab it just left -- if the
      -- guard actually regressed, the reentrant open can land the leaked
      -- duplicate on the ORIGINAL tab instead, which survives `tabclose`
      -- and then breaks the next test with an unrelated-looking failure.
      -- Sweep every remaining editor-relative float unconditionally so a
      -- failure here never bleeds into later tests.
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative == "editor" then
          pcall(vim.api.nvim_win_close, w, true)
        end
      end

      if not ok then
        error(err, 0)
      end
    end
  )

  it("unmount closes the window and drops it from active()", function()
    chip.mount({ id = "spec_a", text = "x" })
    assert.is_true(vim.tbl_contains(chip.active(), "spec_a"))
    chip.unmount("spec_a")
    assert.is_false(vim.tbl_contains(chip.active(), "spec_a"))
    assert.is_nil(chip_window())
  end)

  it("two mounted chips are independent (different text, both active)", function()
    chip.mount({ id = "spec_a", text = "a" })
    chip.mount({ id = "spec_b", text = "b", anchor = "top-right" })
    assert.is_true(vim.tbl_contains(chip.active(), "spec_a"))
    assert.is_true(vim.tbl_contains(chip.active(), "spec_b"))
  end)

  it("refresh on an unknown id is a harmless no-op", function()
    assert.has_no.errors(function()
      chip.refresh("does_not_exist")
    end)
  end)
end)
