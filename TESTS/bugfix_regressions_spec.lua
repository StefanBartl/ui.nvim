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
