-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `:UI kit-preset`/`:UI kit-presets` -- the interactive front end for
--- `ui.kit.theme`'s active default (border/colors every `ui.kit` surface
--- resolves through), which previously had no `:UI` command at all, unlike
--- its siblings `:UI theme` (colorscheme) and `:UI tabline-style` (chip
--- boundary shape). Also covers the "combined look" cross-switch: a kit
--- preset name that is ALSO a registered `ui.tabline.styles` name (true for
--- "rounded" -- see that registry's own aliases) switches the tabline style
--- too, in the same command.

describe(":UI kit-preset / :UI kit-presets", function()
  pcall(function()
    require("ui.bindings.usrcmds").setup()
  end)

  local theme = require("ui.kit.theme")
  local original_default = theme.default()

  after_each(function()
    theme.setup({ default = original_default })
  end)

  it(":UI kit-preset <name> switches the active preset", function()
    vim.cmd("UI kit-preset ascii")
    assert.equals("ascii", theme.default())
  end)

  it(":UI kit-preset with no argument does not throw", function()
    assert.has_no.errors(function()
      vim.cmd("UI kit-preset")
    end)
  end)

  it(":UI kit-preset <unknown> leaves the active preset unchanged", function()
    vim.cmd("UI kit-preset solid")
    -- notify.error() surfaces as a thrown error under the test harness's
    -- notify backend -- the point of this test is the state afterward, not
    -- whether that particular call raises (same reasoning as the sibling
    -- tabline-style spec).
    pcall(vim.cmd, "UI kit-preset no_such_preset")
    assert.equals("solid", theme.default())
  end)

  it(":UI kit-presets does not throw", function()
    assert.has_no.errors(function()
      vim.cmd("UI kit-presets")
    end)
  end)

  it(
    "switching to a preset name that is also a registered tabline style "
      .. "switches the tabline style too",
    function()
      require("ui").setup({ all = true })
      local assembled = require("ui.config").setup()
      require("ui.tabline.render").enable(assembled.ui.tabline)

      -- "rounded" is both a kit preset (ui.kit.theme's BUILTIN.rounded) and a
      -- registered tabline style (ui.tabline.styles' pre-canonical alias) --
      -- exercises the cross-switch without needing a fixture registration.
      vim.cmd("UI kit-preset rounded")

      assert.equals("rounded", theme.default())
      assert.equals("rounded", require("ui.tabline.render").current().style)

      require("ui.tabline.render").disable()
    end
  )

  it("a kit-only preset (no matching tabline style) switches without error", function()
    assert.has_no.errors(function()
      vim.cmd("UI kit-preset minimal")
    end)
    assert.equals("minimal", theme.default())
  end)
end)
