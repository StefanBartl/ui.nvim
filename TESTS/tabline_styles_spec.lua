-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- ui.tabline.styles: the registry `:UI tabline-style`/`:UI tabline-styles`
--- and `ui.tabline.modules.buffers()`'s `apply_boundaries` all read.
--- `cfg.style` used to be a closed set of three string literals hardcoded
--- into `ui.tabline.modules` itself -- no way for a host to add a fourth
--- look, unlike every other named-choice knob in this plugin. Mirrors
--- TESTS/variants_spec.lua's own shape, one module over.

describe("ui.tabline.styles", function()
  local styles = require("ui.tabline.styles")

  it("lists the three shipped looks", function()
    local names = styles.list()
    for _, expected in ipairs({ "rounded", "square", "divider" }) do
      assert.is_true(vim.tbl_contains(names, expected), ("missing %q"):format(expected))
    end
  end)

  it("resolves a shipped look to a callable decorator", function()
    local fn = styles.resolve("rounded")
    assert.equals("function", type(fn))
  end)

  it("returns nil for an unregistered name", function()
    assert.is_nil(styles.resolve("no_such_style"))
    assert.is_false(styles.exists("no_such_style"))
  end)

  it("returns nil for a nil or empty name instead of throwing", function()
    assert.has_no.errors(function()
      assert.is_nil(styles.resolve(nil))
      assert.is_nil(styles.resolve(""))
    end)
  end)

  it("registers a host style under its own name", function()
    local calls = 0
    local fn = function(_chips, _chip_bufs, _cur, _flush_right)
      calls = calls + 1
    end
    styles.register("my_test_style", fn)

    assert.is_true(styles.exists("my_test_style"))
    assert.is_true(vim.tbl_contains(styles.list(), "my_test_style"))
    assert.equals(fn, styles.resolve("my_test_style"))

    styles.resolve("my_test_style")({}, {}, 0, false)
    assert.equals(1, calls)

    styles.unregister("my_test_style")
    assert.is_false(styles.exists("my_test_style"))
  end)

  it("unregister is a no-op for a name that was never registered", function()
    assert.has_no.errors(function()
      styles.unregister("never_registered")
    end)
  end)

  it("square adds no boundary decoration", function()
    local chips = { "a", "b" }
    styles.resolve("square")(chips, { 1, 2 }, 1, false)
    assert.same({ "a", "b" }, chips)
  end)

  it("divider adds exactly one divider per internal boundary", function()
    local chips = { "a", "b", "c" }
    styles.resolve("divider")(chips, { 1, 2, 3 }, 1, false)
    local joined = table.concat(chips)
    -- The `%#UiTbDivider#` highlight-group wrapper is unambiguous per
    -- boundary -- 3 chips have 2 internal boundaries.
    local _, hl_count = joined:gsub("%%#UiTbDivider#", "%%#UiTbDivider#")
    assert.equals(2, hl_count, joined)
  end)
end)

describe("ui.tabline.modules.buffers with a host-registered style", function()
  local modules = require("ui.tabline.modules")
  local styles = require("ui.tabline.styles")

  ---@param n integer
  ---@return integer[]
  local function make_bufs(n)
    local bufs = {}
    for _ = 1, n do
      bufs[#bufs + 1] = vim.api.nvim_create_buf(true, false)
    end
    return bufs
  end

  ---@param bufs integer[]
  local function delete_bufs(bufs)
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end

  it("resolves cfg.style through the registry, not a hardcoded set", function()
    local marker = "%#MyCustomTablineStyle#"
    styles.register("my_render_test_style", function(chips)
      for i = 1, #chips - 1 do
        chips[i] = chips[i] .. marker
      end
    end)

    local saved = vim.t.bufs
    local bufs = make_bufs(3)
    vim.t.bufs = bufs

    local out = modules.buffers({ order = { "buffers" }, style = "my_render_test_style" })

    vim.t.bufs = saved
    delete_bufs(bufs)
    styles.unregister("my_render_test_style")

    local _, count = out:gsub("%%#MyCustomTablineStyle#", "%%#MyCustomTablineStyle#")
    assert.equals(2, count, out)
  end)

  it("still falls back to rounded for an unrecognized style name", function()
    local saved = vim.t.bufs
    local bufs = make_bufs(1)
    vim.t.bufs = bufs

    local ok, out = pcall(modules.buffers, { order = { "buffers" }, style = "no_such_style" })

    vim.t.bufs = saved
    delete_bufs(bufs)

    assert.is_true(ok, tostring(out))
    assert.is_string(out)
  end)
end)

describe(":UI tabline-style / :UI tabline-styles", function()
  before_each(function()
    require("ui").setup({ all = true })
    local assembled = require("ui.config").setup()
    require("ui.tabline.render").enable(assembled.ui.tabline)
  end)

  after_each(function()
    require("ui.tabline.render").disable()
  end)

  it(":UI tabline-style <name> switches the active style and redraws", function()
    vim.cmd("UI tabline-style square")
    assert.equals("square", require("ui.tabline.render").current().style)
  end)

  it(":UI tabline-style with no argument does not throw", function()
    assert.has_no.errors(function()
      vim.cmd("UI tabline-style")
    end)
  end)

  it("UI tabline-style <unknown> leaves the active style unchanged", function()
    vim.cmd("UI tabline-style divider")
    -- notify.error() surfaces as a thrown error under the test harness's
    -- notify backend -- the point of this test is the state afterward, not
    -- whether that particular call raises.
    pcall(vim.cmd, "UI tabline-style no_such_style")
    assert.equals("divider", require("ui.tabline.render").current().style)
  end)

  it(":UI tabline-styles does not throw", function()
    assert.has_no.errors(function()
      vim.cmd("UI tabline-styles")
    end)
  end)
end)
