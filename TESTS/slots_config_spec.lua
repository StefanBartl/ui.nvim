-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.slots.config` -- defaults, merging, validation.

local config = require("ui.slots.config")

describe("ui.slots.config", function()
  after_each(function()
    config.reset()
  end)

  it("is off by default and the defaults are valid", function()
    config.reset()
    local cfg = config.get()
    assert.is_false(cfg.enabled)
    assert.equals("chips", cfg.layout)
    assert.equals("rounded", cfg.style)
    assert.equals("project", cfg.scope)
    assert.equals("current", cfg.target)
    assert.same({}, config.issues())
  end)

  it("has no slot cap and no on_full option", function()
    local cfg = config.get()
    assert.is_nil(cfg.max_slots)
    assert.is_nil(cfg.on_full)
    assert.equals("accordion", cfg.overflow)
  end)

  it("keeps cmd and lua out of the kinds a data file may hold", function()
    local kinds = config.get().persistable_kinds
    assert.is_true(vim.tbl_contains(kinds, "file"))
    assert.is_false(vim.tbl_contains(kinds, "cmd"))
    assert.is_false(vim.tbl_contains(kinds, "lua"))
  end)

  it("setup() merges nested tables over the defaults", function()
    local cfg = config.setup({ preview = { mode = "auto" }, style = "solid" })
    assert.equals("auto", cfg.preview.mode)
    assert.equals(4000, cfg.preview.max_lines)
    assert.equals("solid", cfg.style)
    assert.equals(cfg, config.get())
  end)

  it("takes the slots table as the user's list, not as overrides", function()
    local fn = function() end
    local cfg =
      config.setup({ slots = { [3] = { kind = "lua", fn = fn }, [9] = { kind = "file" } } })
    assert.equals(fn, cfg.slots[3].fn)
    assert.is_not_nil(cfg.slots[9])
    cfg = config.setup({})
    assert.same({}, cfg.slots)
  end)

  it("replaces list options instead of merging them index by index", function()
    local cfg = config.setup({ clipboard = { "+" }, persistable_kinds = { "file" } })
    assert.same({ "+" }, cfg.clipboard)
    assert.same({ "file" }, cfg.persistable_kinds)
  end)

  it("does not let setup() change the defaults", function()
    config.setup({ clipboard = { "a" }, preview = { max_kb = 1 } })
    assert.same({ "+", "*", '"' }, config.DEFAULTS.clipboard)
    assert.equals(1536, config.DEFAULTS.preview.max_kb)
  end)

  it("reset() returns to the defaults", function()
    config.setup({ style = "ascii" })
    config.reset()
    assert.equals("rounded", config.get().style)
  end)

  describe("invalid values", function()
    it("are replaced by their defaults, so nothing downstream sees a wrong type", function()
      local cfg = config.setup({
        layout = "tower",
        persist = "yes",
        width = -1,
        save_delay_ms = "x",
        max_file_kb = math.huge,
        max_string_len = 0 / 0,
        style = 5,
        clipboard = { "++" },
        persistable_kinds = "file",
        keys = 3,
        slots = 4,
        data_dir = "",
        preview = { mode = "hover", delay = "slow", max_lines = -5, fetch = "yes" },
      })
      local D = config.DEFAULTS
      assert.equals(D.layout, cfg.layout)
      assert.equals(D.persist, cfg.persist)
      assert.equals(D.width, cfg.width)
      assert.equals(D.save_delay_ms, cfg.save_delay_ms)
      assert.equals(D.max_file_kb, cfg.max_file_kb)
      assert.equals(D.max_string_len, cfg.max_string_len)
      assert.equals(D.style, cfg.style)
      assert.same(D.clipboard, cfg.clipboard)
      assert.same(D.persistable_kinds, cfg.persistable_kinds)
      assert.same({}, cfg.keys)
      assert.same({}, cfg.slots)
      assert.is_nil(cfg.data_dir)
      assert.equals(D.preview.mode, cfg.preview.mode)
      assert.equals(D.preview.delay, cfg.preview.delay)
      assert.equals(D.preview.max_lines, cfg.preview.max_lines)
      assert.is_true(cfg.preview.fetch)
      assert.is_true(#config.issues() >= 10)
    end)

    it("do not stop the valid ones next to them from being applied", function()
      local cfg = config.setup({ layout = "tower", style = "solid", scope = "global" })
      assert.equals("chips", cfg.layout)
      assert.equals("solid", cfg.style)
      assert.equals("global", cfg.scope)
    end)

    it("do not raise for a setup() that is not even a table", function()
      assert.is_true((pcall(config.setup, "nope")))
      assert.equals("chips", config.get().layout)
    end)
  end)

  describe("issues()", function()
    ---@param opts table
    ---@return string
    local function joined(opts)
      config.setup(opts)
      return table.concat(config.issues(), "\n")
    end

    it("names a value outside an enum", function()
      assert.is_truthy(joined({ layout = "tower" }):find("layout", 1, true))
      assert.is_truthy(joined({ scope = "world" }):find("scope", 1, true))
      assert.is_truthy(joined({ target = "window" }):find("target", 1, true))
      assert.is_truthy(joined({ overflow = "wrap" }):find("overflow", 1, true))
    end)

    it("rejects numbers that are negative, NaN or infinite", function()
      assert.is_truthy(joined({ width = -1 }):find("width", 1, true))
      assert.is_truthy(joined({ save_delay_ms = 0 / 0 }):find("save_delay_ms", 1, true))
      assert.is_truthy(joined({ max_file_kb = math.huge }):find("max_file_kb", 1, true))
      assert.is_truthy(joined({ preview = { max_lines = -5 } }):find("max_lines", 1, true))
    end)

    it("rejects a wrong type", function()
      assert.is_truthy(joined({ persist = "yes" }):find("persist", 1, true))
      assert.is_truthy(joined({ style = 5 }):find("style", 1, true))
      assert.is_truthy(joined({ preview = { mode = "hover" } }):find("preview.mode", 1, true))
    end)

    it("checks the registers", function()
      assert.is_truthy(joined({ clipboard = {} }):find("clipboard", 1, true))
      assert.is_truthy(joined({ clipboard = { "++" } }):find("clipboard", 1, true))
    end)

    it("checks the fixed slots", function()
      local out = joined({ slots = { [0] = { kind = "file" }, [2] = { path = "x" }, [-1] = {} } })
      assert.is_truthy(out:find("slots", 1, true))
      assert.is_true(#config.issues() >= 3)
    end)

    it("is empty for a valid config with fixed slots", function()
      config.setup({ slots = { [4] = { kind = "yank", text = "x" } }, scope = "global" })
      assert.same({}, config.issues())
    end)

    it("reports an option it does not know instead of merging it away", function()
      assert.is_truthy(joined({ persits = false }):find("persits", 1, true))
      assert.is_truthy(joined({ preview = { modee = "auto" } }):find("modee", 1, true))
    end)

    it("reports a container option of the wrong type", function()
      assert.is_truthy(joined({ persistable_kinds = "file" }):find("persistable_kinds", 1, true))
      assert.is_truthy(joined({ slots = 4 }):find("slots", 1, true))
      assert.is_truthy(joined({ kinds = "x" }):find("kinds", 1, true))
    end)

    it("flags a slot number above the highest the store accepts", function()
      local out = joined({ slots = { [config.MAX_N + 1] = { kind = "file" } } })
      assert.is_truthy(out:find("slots", 1, true))
    end)

    it("is cleared by reset()", function()
      config.setup({ persits = false })
      config.reset()
      assert.same({}, config.issues())
    end)

    it("checks a table it is handed as it stands", function()
      local raw = vim.deepcopy(config.DEFAULTS)
      raw.layout = "tower"
      assert.is_truthy(table.concat(config.issues(raw), "\n"):find("layout", 1, true))
    end)

    it("never raises on a broken table", function()
      local ok = pcall(config.issues, { layout = {}, preview = 3, slots = 4, clipboard = "x" })
      assert.is_true(ok)
    end)
  end)
end)
