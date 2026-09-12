-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Step 6 of the roadmap: base46 replaced by `ui.theme.palette` (accent
--- colors derived from the active colorscheme), `ui.theme.transparency`
--- (this plugin's own toggle), and `ui.bindings.usrcmds.themes` (real
--- `:colorscheme` switching). Run WITHOUT NvChad or base46 on the
--- runtimepath -- that absence is the point.

describe("ui.theme.palette", function()
  local palette = require("ui.theme.palette")

  it("resolves an accent for every documented semantic key", function()
    for _, key in ipairs({ "project", "nearest", "lock", "manual", "tree_leads" }) do
      local hex = palette.accent(key)
      assert.is_string(hex)
      assert.is_not_nil(hex:match("^#%x%x%x%x%x%x$"))
    end
  end)

  it("falls back to a fixed hex for an unknown key rather than throwing", function()
    assert.has_no.errors(function()
      ---@diagnostic disable-next-line: param-type-mismatch -- deliberately invalid
      palette.accent("no_such_key")
    end)
  end)

  it("picks black or white contrast text for any hex", function()
    assert.equals("#000000", palette.contrast_fg("#ffffff"))
    assert.equals("#ffffff", palette.contrast_fg("#000000"))
  end)

  it("returns a usable statusline background hex", function()
    local hex = palette.statusline_bg()
    assert.is_string(hex)
    assert.is_not_nil(hex:match("^#%x%x%x%x%x%x$"))
  end)
end)

describe("ui.theme.transparency", function()
  local transparency = require("ui.theme.transparency")

  after_each(function()
    -- Leave global state clean for the next test/spec file.
    if transparency.is_enabled() then
      transparency.set(false)
    end
  end)

  it("starts disabled", function()
    assert.is_false(transparency.is_enabled())
  end)

  it("toggle() flips state and returns the new value", function()
    local new_state = transparency.toggle()
    assert.is_true(new_state)
    assert.is_true(transparency.is_enabled())
  end)

  it("set(true) strips bg from Normal, set(false) restores it", function()
    local before = vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg

    transparency.set(true)
    assert.is_nil(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg)

    transparency.set(false)
    assert.equals(before, vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg)
  end)

  it("set() is a no-op when already in the requested state", function()
    assert.has_no.errors(function()
      transparency.set(false)
      transparency.set(false)
    end)
  end)
end)

describe("ui.bindings.usrcmds.themes", function()
  local themes = require("ui.bindings.usrcmds.themes")

  it("lists at least one real colorscheme", function()
    local list = themes.list_themes()
    assert.is_true(#list > 0)
  end)

  it("theme_exists agrees with list_themes", function()
    local list = themes.list_themes()
    assert.is_true(themes.theme_exists(list[1]))
    assert.is_false(themes.theme_exists("definitely_not_a_real_colorscheme"))
  end)

  it("load_theme switches vim.g.colors_name on success", function()
    -- "default" ships with Neovim itself, so this does not depend on any
    -- colorscheme plugin being installed in the test environment.
    local ok = themes.load_theme("default")
    assert.is_true(ok)
    assert.equals("default", themes.get_current_theme())
  end)

  it("load_theme refuses an unknown theme rather than throwing", function()
    assert.is_false(themes.load_theme("definitely_not_a_real_colorscheme"))
  end)

  it("set_transparency/get_transparency/toggle_transparency agree", function()
    local new_state = themes.toggle_transparency()
    assert.equals(new_state, themes.get_transparency())
    themes.set_transparency(false)
    assert.is_false(themes.get_transparency())
  end)

  it("get_info reports theme, transparency and the toggle pair", function()
    local info = themes.get_info()
    assert.is_string(info.theme)
    assert.is_boolean(info.transparency)
    assert.equals("table", type(info.toggle_themes))
  end)
end)
