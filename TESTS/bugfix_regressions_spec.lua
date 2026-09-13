-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Regression coverage for the 2026-09-12 bug sweep. Each `describe` names
--- the bug it guards against, not just the function under test, so a future
--- reader knows WHY the assertion exists without digging through git blame.

describe("bug: :UI transparency on/off was inverted", function()
  it("'on' actually enables, 'off' actually disables", function()
    require("ui").setup({ all = true })
    local themes = require("ui.bindings.usrcmds.themes")

    -- Start from a known state regardless of what an earlier spec left behind.
    if themes.get_transparency() then
      themes.set_transparency(false)
    end

    vim.cmd("UI transparency on")
    assert.is_true(themes.get_transparency())

    vim.cmd("UI transparency off")
    assert.is_false(themes.get_transparency())
  end)
end)

describe("bug: get_separators had no fallback for an unknown style", function()
  local get_separators = require("ui.statusline.utils.get_separators")

  it("falls back to the default set instead of throwing", function()
    local sep
    assert.has_no.errors(function()
      sep = get_separators("no_such_style")
    end)
    assert.is_string(sep.left)
    assert.is_string(sep.right)
  end)

  it("still resolves a known style normally", function()
    local sep = get_separators("round")
    assert.is_string(sep.left)
    assert.is_string(sep.right)
  end)
end)

describe("bug: lsp.config.update() dropped valid fields after a bad one", function()
  local cfg = require("ui.statusline.modules.lsp.config")

  it("applies every valid field in a patch even when another field is rejected", function()
    local before = cfg.get("path_max_chars")

    cfg.update({
      -- `path_home_tilde` expects boolean; this is deliberately wrong to
      -- trigger the rejection path.
      path_home_tilde = "not-a-boolean",
      path_max_chars = before + 1,
    })

    assert.equals(before + 1, cfg.get("path_max_chars"))
    -- The rejected field must be untouched, not partially applied.
    assert.is_boolean(cfg.get("path_home_tilde"))

    cfg.set("path_max_chars", before)
  end)
end)

describe("bug: display_path() mutated shared config as a side effect", function()
  local paths = require("ui.statusline.modules.lsp.helpers.paths")
  local cfg = require("ui.statusline.modules.lsp.config")

  it("an override passed to display_path() does not leak into global config", function()
    local before_mode = cfg.get("path_mode")
    local before_tilde = cfg.get("path_home_tilde")

    paths.display_path({ path_mode = "home", path_home_tilde = not before_tilde }, "/tmp/x")

    assert.equals(before_mode, cfg.get("path_mode"))
    assert.equals(before_tilde, cfg.get("path_home_tilde"))
  end)

  it("path_relative's cache key accounts for the home-tilde override", function()
    -- Same (mode, path) pair, opposite home_tilde_override -- must not
    -- collide on one cached result.
    local home = vim.uv.os_homedir() or vim.loop.os_homedir()
    local under_home = home .. "/some/file.lua"

    local with_tilde = paths.path_relative("home", under_home, true)
    local without_tilde = paths.path_relative("home", under_home, false)

    assert.is_not.equals(with_tilde, without_tilde)
  end)
end)

describe("bug: ui.tabline.utils deferred close was not pcall'd", function()
  -- close_buffer()/close_all_bufs() defer the real state.close_buffer()/
  -- state.close_all_bufs() call behind the click-flash (see their own doc
  -- comments). The synchronous half was already pcall'd everywhere else in
  -- this ecosystem (close_n_buffers, the close_all keymap's own `rhs`), but
  -- the deferred callback itself was not -- a bufnr going invalid between
  -- the flash and the 120ms-later close (closed elsewhere, double-clicked)
  -- would raise, unhandled, out of a vim.defer_fn timer callback instead of
  -- notifying like docs/BINDINGS.md's "a failure notifies and returns
  -- rather than raising" promises.
  local utils = require("ui.tabline.utils")
  local state = require("ui.bindings.keymaps.tabufline.state")

  it("close_buffer notifies instead of raising when the deferred close fails", function()
    local original = state.close_buffer
    state.close_buffer = function()
      error("boom")
    end

    local notified = false
    local original_notify = vim.notify
    vim.notify = function(msg)
      if msg:find("close_buffer failed", 1, true) then
        notified = true
      end
    end

    assert.has_no.errors(function()
      utils.close_buffer(1)
    end)
    vim.wait(300, function()
      return notified
    end)

    vim.notify = original_notify
    state.close_buffer = original
    assert.is_true(notified)
  end)

  it("close_all_bufs notifies instead of raising when the deferred close fails", function()
    local original = state.close_all_bufs
    state.close_all_bufs = function()
      error("boom")
    end

    local notified = false
    local original_notify = vim.notify
    vim.notify = function(msg)
      if msg:find("close_all_bufs failed", 1, true) then
        notified = true
      end
    end

    assert.has_no.errors(function()
      utils.close_all_bufs()
    end)
    vim.wait(300, function()
      return notified
    end)

    vim.notify = original_notify
    state.close_all_bufs = original
    assert.is_true(notified)
  end)
end)

describe("bug: themes.default T.mode() drew its own separator glyph twice", function()
  -- One `St_<Mode>ModeSep` group already carries the sep_r glyph AND fades
  -- into ST_EmptySpace's background -- a second bare sep_r right after it
  -- duplicated the same halfcircle (confirmed against git log -p, present
  -- since the original wkdnvchad port). See themes/default.lua's own T.mode
  -- doc comment for the fix; nothing here previously asserted the glyph
  -- count, so a refactor could silently bring the duplicate back.
  local themes_default = require("ui.statusline.themes.default")
  local primitives = require("ui.statusline.utils.primitives")

  it("emits the mode separator glyph exactly once", function()
    local saved_winid = vim.g.statusline_winid
    vim.g.statusline_winid = vim.api.nvim_get_current_win()

    local T = themes_default.build("default")
    local out = T.mode()

    vim.g.statusline_winid = saved_winid

    local sep_r = primitives.separators.default.right
    local _, count = out:gsub(sep_r, sep_r)
    assert.equals(1, count)
  end)
end)
