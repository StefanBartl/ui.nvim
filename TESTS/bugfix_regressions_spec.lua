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

describe("bug: statusline git/diagnostics/lsp counters silently lost their icon glyphs", function()
  -- primitives.git()/diagnostics()/lsp() were ported from
  -- nvchad/stl/utils.lua with every icon glyph reduced to a bare ASCII
  -- space -- confirmed byte-for-byte against that original file, which
  -- still has every one of them intact. This is what actually produced the
  -- reported "counter with no icon" (a gitsigns "changed" count rendering
  -- as a bare "1"), not the St_* highlight-group gap that shipped in the
  -- same round -- that fix was necessary but not sufficient, and the "1
  -- ohne Icon" report was never independently re-checked against it.
  local primitives = require("ui.statusline.utils.primitives")

  -- `vim.lsp` is a lazily-materialized submodule (Neovim's own `vim.__index`
  -- populates it on first read) -- `rawget(vim, "lsp")`, what M.lsp()/
  -- M.diagnostics() gate on below, only sees it once something has actually
  -- read `vim.lsp` at least once. A real session always has by the time any
  -- diagnostic or client exists (attaching one necessarily touches
  -- `vim.lsp` itself); a bare test process has not, unless something forces
  -- it first -- this line is that force, not a workaround for a bug.
  local _ = vim.lsp

  it("git() renders the added/changed/removed/branch icons, not bare spaces", function()
    local buf = primitives.stbufnr()
    local saved_head = vim.b[buf].gitsigns_head
    local saved_status = vim.b[buf].gitsigns_status_dict

    vim.b[buf].gitsigns_head = "main"
    vim.b[buf].gitsigns_status_dict = { head = "main", added = 1, changed = 2, removed = 3 }

    local out = primitives.git()

    vim.b[buf].gitsigns_head = saved_head
    vim.b[buf].gitsigns_status_dict = saved_status

    -- Each icon is a multi-byte UTF-8 sequence starting 0xEF/0xEE -- the
    -- regression left bare ASCII spaces, none of which contain these bytes.
    assert.is_true(out:find("\xEF\x81\x95", 1, true) ~= nil, out) -- added
    assert.is_true(out:find("\xEF\x91\x99", 1, true) ~= nil, out) -- changed
    assert.is_true(out:find("\xEF\x85\x86", 1, true) ~= nil, out) -- removed
    assert.is_true(out:find("\xEE\xA9\xA8", 1, true) ~= nil, out) -- branch
  end)

  it("diagnostics() renders the error/warning icons, not bare spaces", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    local ns = vim.api.nvim_create_namespace("ui_primitives_icon_regression_test")

    vim.diagnostic.set(ns, buf, {
      { lnum = 0, col = 0, message = "fake error", severity = vim.diagnostic.severity.ERROR },
      { lnum = 0, col = 0, message = "fake warning", severity = vim.diagnostic.severity.WARN },
    })

    local out = primitives.diagnostics()

    vim.diagnostic.reset(ns, buf)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(out:find("\xEF\x81\x97", 1, true) ~= nil, out) -- error
    assert.is_true(out:find("\xEF\x81\xB1", 1, true) ~= nil, out) -- warning
  end)

  it("lsp() renders the attached client's icon, not a bare space", function()
    local original = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return {
        { name = "fake-lsp", attached_buffers = { [vim.api.nvim_get_current_buf()] = true } },
      }
    end

    local out = primitives.lsp()
    vim.lsp.get_clients = original

    assert.is_true(out:find("\xEF\x82\x85", 1, true) ~= nil, out)
  end)
end)

describe("bug: git()'s branch name was not %-escaped for 'statusline'", function()
  -- `%` is a valid git ref character (a branch named e.g. "50%-done" is
  -- legal), and `git_status.head` was concatenated straight into the
  -- rendered string -- the same bug class `ui.tabline.utils`' own
  -- `stl_escape` and `ui.statusline.modules.formatters.stl_escape` already
  -- guard against for buffer names and LSP/Treesitter symbol text. Found
  -- while building the statusline click layer, never independently fixed
  -- for this call site before.
  local primitives = require("ui.statusline.utils.primitives")

  it("escapes a literal % in the branch name so it cannot be read as a directive", function()
    local buf = primitives.stbufnr()
    local saved_head = vim.b[buf].gitsigns_head
    local saved_status = vim.b[buf].gitsigns_status_dict

    vim.b[buf].gitsigns_head = "feature/50%-done"
    vim.b[buf].gitsigns_status_dict = { head = "feature/50%-done" }

    local out = primitives.git()

    vim.b[buf].gitsigns_head = saved_head
    vim.b[buf].gitsigns_status_dict = saved_status

    -- Escaped: one literal "%" becomes two ("%%"), plain-string search so
    -- neither side of this assertion is itself read as a Lua pattern.
    assert.is_true(out:find("50%%-done", 1, true) ~= nil, out)
    assert.is_nil(out:find("50%-done", 1, true))
  end)
end)
