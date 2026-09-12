-- Three file-wide suppressions, each for a reason that holds for every spec
-- here: the test body IS the guard (need-check-nil), `assert` is busted's
-- rather than Lua's so LuaLS finds no `.equals` on it (undefined-field), and a
-- spec arranging state has no return value to inspect (discard-returns).
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- The configuration surface, tested WITHOUT NvChad present.
---
--- That constraint is the point rather than a limitation: everything asserted
--- here is what must keep working once the NvChad coupling is gone, and the
--- suite would silently stop proving it if it ran against a full session.

describe("ui.config.DEFAULTS", function()
  local D = require("ui.config.DEFAULTS")

  it("carries the three groups", function()
    assert.equals("table", type(D.theme))
    assert.equals("table", type(D.statusline))
    assert.equals("table", type(D.modules))
  end)

  it("names a transparency flag and a toggle pair", function()
    -- No `theme` field any more (step 6): nothing here applies a startup
    -- colorscheme, so there is nothing for such a field to feed.
    assert.is_boolean(D.theme.transparency)
    assert.equals(2, #D.theme.theme_toggle)
  end)

  it("agrees with the variant the code actually reads", function()
    -- Two places would otherwise drift: DEFAULTS records the shipped variant,
    -- ui.config.STATUSLINE_VARIANT is the switch the assembly reads.
    assert.equals(require("ui.config").STATUSLINE_VARIANT, D.statusline.variant)
  end)

  it("names a variant that exists as a module", function()
    assert.is_true(pcall(require, "ui.config.statusline." .. D.statusline.variant))
  end)
end)

describe("ui.config", function()
  local cfg = require("ui.config")

  it("assembles without NvChad", function()
    -- Step 3 of the roadmap replaced every layout's `nvconfig`/
    -- `nvchad.stl.utils` read with a local literal and
    -- `ui.statusline.utils.primitives`, so assembly no longer touches NvChad
    -- at all. If this starts failing, a new NvChad require crept back in.
    local ok, assembled = pcall(cfg.setup)
    assert.is_true(ok, tostring(assembled))
    assert.equals("table", type(assembled))
  end)

  it("accepts theme overrides", function()
    local assembled = cfg.setup({ theme = { theme_toggle = { "a", "b" } } })
    assert.same({ "a", "b" }, assembled.theme.theme_toggle)
  end)

  it("does not let an override leak into the shipped defaults", function()
    cfg.setup({ theme = { theme_toggle = { "leaked1", "leaked2" } } })
    assert.is_not.same({ "leaked1", "leaked2" }, require("ui.config.DEFAULTS").theme.theme_toggle)
  end)

  it("records the assembled config for ui.config.last()", function()
    local assembled = cfg.setup({ theme = { theme_toggle = { "x", "y" } } })
    assert.same(assembled, cfg.last())
  end)

  it("falls back to 'normal' for an unknown variant instead of throwing", function()
    local saved = cfg.STATUSLINE_VARIANT
    -- An invalid value is the point of this test, so the type error is too.
    ---@diagnostic disable-next-line: assign-type-mismatch
    cfg.STATUSLINE_VARIANT = "no_such_variant"

    local ok = pcall(cfg.setup)
    assert.is_true(ok)

    cfg.STATUSLINE_VARIANT = saved
  end)

  it("has all six documented layouts on disk", function()
    for _, variant in ipairs({
      "normal",
      "base",
      "lspbased",
      "custom",
      "custom_light",
      "custom_minimal",
    }) do
      assert.is_true(
        pcall(require, "ui.config.statusline." .. variant),
        ("variant %q does not load"):format(variant)
      )
    end
  end)
end)

describe("ui.setup", function()
  it("does nothing without a flag", function()
    package.loaded["ui.bindings.keymaps"] = nil
    package.loaded["ui.bindings.usrcmds"] = nil

    require("ui").setup({})

    assert.is_nil(package.loaded["ui.bindings.keymaps"])
    assert.is_nil(package.loaded["ui.bindings.usrcmds"])
  end)

  it("runs with no argument at all", function()
    assert.has_no.errors(function()
      require("ui").setup()
    end)
  end)

  it("loads both submodules under all = true", function()
    require("ui").setup({ all = true })
    assert.is_truthy(package.loaded["ui.bindings.keymaps"])
    assert.is_truthy(package.loaded["ui.bindings.usrcmds"])
  end)

  it("registers :UI", function()
    require("ui").setup({ all = true })
    assert.equals(2, vim.fn.exists(":UI"))
  end)
end)
