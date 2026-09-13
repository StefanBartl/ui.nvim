-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.bindings.usrcmds.themes.picker` -- the visual theme picker added on
--- top of `:UI theme`/`:UI toggle`. Drives `lib.nvim.ui.kit.select`'s real
--- floating window headless: opens the picker, moves the cursor with the
--- actual Neovim API (firing a real `CursorMoved`, not a stubbed callback),
--- and asserts the colorscheme changed live. No NvChad on the runtimepath --
--- same constraint as every other spec here.

local picker = require("ui.bindings.usrcmds.themes.picker")
local theme = require("ui.bindings.usrcmds.themes")

---@internal
--- The chooser's own float is the current window right after `picker.open()`
--- returns (kit focuses it synchronously) -- simpler than threading the
--- surface handle back out of a function whose only real contract is `nil`.
---@return integer winid
local function picker_winid()
  return vim.api.nvim_get_current_win()
end

---@internal
--- Move to row `n` in the picker's results and fire the same autocmd a real
--- keypress would have triggered. Does NOT wait for the preview's debounce
--- (see `PREVIEW_DEBOUNCE_MS` in picker.lua) -- callers that want the
--- settled result use `wait_for_theme` below.
---@param winid integer
---@param n integer
local function move_to(winid, n)
  vim.api.nvim_win_set_cursor(winid, { n, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_win_get_buf(winid) })
end

---@internal
--- Block until the debounced preview has actually applied `name`, or the
--- wait times out (leaving the caller's own assertion to report the
--- mismatch instead of failing on a timing race).
---@param name string
local function wait_for_theme(name)
  vim.wait(300, function()
    return vim.g.colors_name == name
  end, 10)
end

describe("ui.bindings.usrcmds.themes.picker", function()
  local themes = theme.list_themes()

  -- Needs at least two real colorschemes to move between and tell apart --
  -- true for any stock Neovim (default, blue, morning, ... ship built in).
  if #themes < 2 then
    return
  end

  before_each(function()
    -- A known, non-nil starting theme: `vim.g.colors_name` is nil in a bare
    -- headless run until something calls `:colorscheme` at least once, and
    -- `picker.on_cancel` deliberately does nothing when there was nothing to
    -- restore to (see picker.lua) -- realistic for a real session (the host
    -- always sets one at startup), but it would make every "restores the
    -- original" assertion below vacuous.
    theme.load_theme(themes[1])
  end)

  after_each(function()
    -- A leftover float from an assertion failure mid-test must not bleed
    -- into the next one.
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(winid).relative ~= "" then
        pcall(vim.api.nvim_win_close, winid, true)
      end
    end
  end)

  it("previews the theme under the cursor live, without confirming", function()
    local original = theme.get_current_theme()
    picker.open()
    local winid = picker_winid()

    local target, row
    for i, name in ipairs(themes) do
      if name ~= original then
        target, row = name, i
        break
      end
    end
    assert.is_not_nil(target)

    move_to(winid, row)
    wait_for_theme(target)
    assert.equals(target, vim.g.colors_name)

    -- Closing the float (however it closes -- WinClosed covers all of them,
    -- not just <Esc>) must run the same cancel path and restore the
    -- pre-picker theme, not leave the last-previewed one applied.
    -- `kit.select`'s own cancel-vs-select disambiguation defers one tick
    -- (`vim.schedule`, see its own comment) to let a real selection flip its
    -- `chose` flag first -- flush that tick before asserting.
    vim.api.nvim_win_close(winid, true)
    vim.wait(200, function()
      return vim.g.colors_name == original
    end, 10)
    assert.equals(original, vim.g.colors_name)
  end)

  it("keeps the previewed theme on confirm", function()
    local original = theme.get_current_theme()
    picker.open()
    local winid = picker_winid()

    local target, row
    for i, name in ipairs(themes) do
      if name ~= original then
        target, row = name, i
        break
      end
    end
    assert.is_not_nil(target)

    move_to(winid, row)
    wait_for_theme(target)
    assert.equals(target, vim.g.colors_name)

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    assert.equals(target, vim.g.colors_name)

    -- Leave the suite in a known colorscheme for whatever spec runs next.
    theme.load_theme(original)
  end)

  it("restores the original theme when the picker is cancelled", function()
    local original = theme.get_current_theme()
    picker.open()
    local winid = picker_winid()

    local target, row
    for i, name in ipairs(themes) do
      if name ~= original then
        target, row = name, i
        break
      end
    end
    assert.is_not_nil(target)

    move_to(winid, row)
    wait_for_theme(target)
    assert.equals(target, vim.g.colors_name)

    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    vim.wait(200, function()
      return vim.g.colors_name == original
    end, 10)
    assert.equals(original, vim.g.colors_name)
  end)

  it("debounces rapid moves instead of reloading the colorscheme on every one", function()
    local original = theme.get_current_theme()
    picker.open()
    local winid = picker_winid()

    -- At least three distinct rows to hop across, none of them `original`.
    local rows = {}
    for i, name in ipairs(themes) do
      if name ~= original then
        rows[#rows + 1] = i
        if #rows == 3 then
          break
        end
      end
    end
    if #rows < 3 then
      -- Fewer than four installed colorschemes total -- nothing meaningful
      -- to hop across three times; the other tests already cover the
      -- two-theme case.
      return
    end

    for _, row in ipairs(rows) do
      move_to(winid, row)
    end
    -- Immediately after firing three rapid moves, none has had time to
    -- settle yet -- the debounce must still be pending, not already
    -- applied to an intermediate (now stale) row.
    assert.equals(original, vim.g.colors_name)

    local final_target = themes[rows[#rows]]
    wait_for_theme(final_target)
    assert.equals(final_target, vim.g.colors_name)
  end)

  it("is a no-op when there is nothing to pick from", function()
    local list_themes = theme.list_themes
    ---@diagnostic disable-next-line: duplicate-set-field
    theme.list_themes = function()
      return {}
    end
    assert.has_no.errors(function()
      picker.open()
    end)
    theme.list_themes = list_themes
  end)
end)
