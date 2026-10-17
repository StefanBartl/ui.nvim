-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- UI-05: `:UI variant`, `:UI tabline-style` and `:UI kit-preset` without a
--- name open a choice over the closed set of names (via `ui.kit.select`),
--- the current value marked and preselected; a pick switches, a cancel
--- leaves everything as it was. With a name, no choice opens at all.
--- `ui.kit.select.open` is stubbed so the spec sees the exact options the
--- command hands over and can play the user's pick or cancel.

describe("UI-05: setters without a name open a choice", function()
  pcall(function()
    require("ui.bindings.usrcmds").setup()
  end)

  local kit_select = require("ui.kit.select")
  local real_open = kit_select.open
  local kit_theme = require("ui.kit.theme")
  local original_preset = kit_theme.default()
  local seen

  before_each(function()
    seen = nil
    kit_select.open = function(opts)
      seen = opts
      return nil
    end
  end)

  after_each(function()
    kit_select.open = real_open
    kit_theme.setup({ default = original_preset })
    pcall(require("ui.tabline.render").disable)
  end)

  ---Assert the captured options list `names`, mark and preselect `current`.
  ---@param names string[]
  ---@param current string
  local function assert_choice(names, current)
    assert.is_table(seen, "no choice was opened")
    assert.same(names, seen.items)
    assert.is_function(seen.on_select)
    assert.equals(current, seen.items[seen.initial_index])
    assert.equals("✓ " .. current, seen.format_item(current))
    for _, name in ipairs(names) do
      if name ~= current then
        assert.equals("  " .. name, seen.format_item(name))
      end
    end
  end

  ---First name in `names` that is not `current`.
  ---@param names string[]
  ---@param current string
  ---@return string
  local function other_than(names, current)
    for _, name in ipairs(names) do
      if name ~= current then
        return name
      end
    end
    error("no second name to pick")
  end

  describe(":UI kit-preset", function()
    it("opens a choice over the presets, the current one marked", function()
      vim.cmd("UI kit-preset solid")
      vim.cmd("UI kit-preset")
      assert_choice(kit_theme.presets(), "solid")
    end)

    it("a pick switches the preset", function()
      vim.cmd("UI kit-preset solid")
      vim.cmd("UI kit-preset")
      seen.on_select("minimal", 1)
      assert.equals("minimal", kit_theme.default())
    end)

    it("a cancel leaves the preset unchanged", function()
      vim.cmd("UI kit-preset solid")
      vim.cmd("UI kit-preset")
      if seen.on_cancel then
        seen.on_cancel()
      end
      assert.equals("solid", kit_theme.default())
    end)

    it("with a name, switches without opening a choice", function()
      vim.cmd("UI kit-preset ascii")
      assert.is_nil(seen)
      assert.equals("ascii", kit_theme.default())
    end)
  end)

  describe(":UI tabline-style", function()
    local function enable_tabline()
      require("ui").setup({ all = true })
      local assembled = require("ui.config").setup()
      require("ui.tabline.render").enable(assembled.ui.tabline)
      return require("ui.tabline.render").current()
    end

    it("opens a choice over the styles, the current one marked", function()
      local cfg = enable_tabline()
      local current = cfg.style or "rounded"
      vim.cmd("UI tabline-style")
      assert_choice(require("ui.tabline.styles").list(), current)
    end)

    it("a pick switches, a cancel does not", function()
      local cfg = enable_tabline()
      local current = cfg.style or "rounded"
      local target = other_than(require("ui.tabline.styles").list(), current)

      vim.cmd("UI tabline-style")
      if seen.on_cancel then
        seen.on_cancel()
      end
      assert.equals(current, require("ui.tabline.render").current().style or "rounded")

      vim.cmd("UI tabline-style")
      seen.on_select(target, 1)
      assert.equals(target, require("ui.tabline.render").current().style)
    end)

    it("with a name, switches without opening a choice", function()
      local cfg = enable_tabline()
      local target = other_than(require("ui.tabline.styles").list(), cfg.style or "rounded")
      vim.cmd("UI tabline-style " .. target)
      assert.is_nil(seen)
      assert.equals(target, require("ui.tabline.render").current().style)
    end)
  end)

  describe(":UI variant", function()
    local variants = require("ui.config.variants")

    it("opens a choice over the variants, the current one marked; a pick switches", function()
      require("ui").setup({ all = true })
      local names = variants.list()
      local first = names[1]
      vim.cmd("UI variant " .. first)
      assert.is_nil(seen)
      assert.equals(first, require("ui.config").get_variant())

      vim.cmd("UI variant")
      assert_choice(names, first)

      if seen.on_cancel then
        seen.on_cancel()
      end
      assert.equals(first, require("ui.config").get_variant())

      local target = other_than(names, first)
      seen.on_select(target, 1)
      assert.equals(target, require("ui.config").get_variant())
    end)
  end)
end)
