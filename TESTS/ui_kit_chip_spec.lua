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
