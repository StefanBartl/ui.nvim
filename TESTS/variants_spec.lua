-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- ui.config.variants: the registry `:UI variant`/`:UI variants` and
--- `ui.config.setup({ variant = "name" })` all read. Covers the registry
--- itself, then the runtime switching command built on top of it.

describe("ui.config.variants", function()
  local variants = require("ui.config.variants")

  it("lists the four shipped presets", function()
    local names = variants.list()
    for _, expected in ipairs({ "default", "minimal", "lsp", "blocks" }) do
      assert.is_true(vim.tbl_contains(names, expected), ("missing %q"):format(expected))
    end
  end)

  it("resolves a shipped preset to a real variant table", function()
    local resolved = variants.resolve("default")
    assert.equals("table", type(resolved))
    assert.equals("table", type(resolved.ui.statusline))
  end)

  it("returns nil for an unregistered name", function()
    assert.is_nil(variants.resolve("no_such_variant"))
    assert.is_false(variants.exists("no_such_variant"))
  end)

  it("registers a host variant under its own name", function()
    local own = { ui = { statusline = { order = {}, modules = {} } } }
    variants.register("my_test_variant", own)

    assert.is_true(variants.exists("my_test_variant"))
    assert.is_true(vim.tbl_contains(variants.list(), "my_test_variant"))
    assert.equals(own, variants.resolve("my_test_variant"))

    variants.unregister("my_test_variant")
  end)

  it("accepts a lazy loader function, called only on resolve", function()
    local built = false
    variants.register("my_lazy_variant", function()
      built = true
      return { ui = { statusline = { order = {}, modules = {} } } }
    end)

    assert.is_false(built)
    local resolved = variants.resolve("my_lazy_variant")
    assert.is_true(built)
    assert.equals("table", type(resolved))

    variants.unregister("my_lazy_variant")
  end)

  it("unregister is a no-op for a name that was never registered", function()
    assert.has_no.errors(function()
      variants.unregister("never_registered")
    end)
  end)
end)

describe("ui.config.setup with a registered variant name", function()
  local cfg = require("ui.config")
  local variants = require("ui.config.variants")

  it("resolves opts.variant as a string through the registry", function()
    local assembled = cfg.setup({ variant = "minimal" })
    assert.equals("minimal", cfg.get_variant())
    assert.same(variants.resolve("minimal").ui.statusline.order, assembled.ui.statusline.order)
  end)

  it("get_variant() is nil after an anonymous table variant", function()
    cfg.setup({ variant = { ui = { statusline = { order = {}, modules = {} } } } })
    assert.is_nil(cfg.get_variant())
  end)

  it("falls back to default and warns on an unknown string name", function()
    local ok, assembled = pcall(cfg.setup, { variant = "no_such_variant" })
    assert.is_true(ok)
    assert.equals("default", cfg.get_variant())
    assert.same(variants.resolve("default").ui.statusline.order, assembled.ui.statusline.order)
  end)
end)

describe(":UI variant / :UI variants", function()
  before_each(function()
    require("ui").setup({ all = true })
  end)

  it(":UI variant <name> switches the active variant and renders it", function()
    vim.cmd("UI variant minimal")
    assert.equals("minimal", require("ui.config").get_variant())

    local render = require("ui.statusline.render")
    assert.is_not_nil(render.current())
  end)

  it(":UI variant with no argument does not throw", function()
    assert.has_no.errors(function()
      vim.cmd("UI variant")
    end)
  end)

  it("UI variant <unknown> leaves the active variant unchanged", function()
    -- notify.error() surfaces as a thrown error under the test harness's
    -- notify backend -- the point of this test is the state afterward, not
    -- whether that particular call raises.
    vim.cmd("UI variant default")
    pcall(vim.cmd, "UI variant no_such_variant")
    assert.equals("default", require("ui.config").get_variant())
  end)

  it(":UI variants does not throw", function()
    assert.has_no.errors(function()
      vim.cmd("UI variants")
    end)
  end)
end)
