-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.catalog` -- the module list `:UI modules`/docs/modules.md
--- both read from -- and the `:UI modules` command itself.

describe("ui.statusline.catalog", function()
  local catalog = require("ui.statusline.catalog")

  it("is a non-empty list", function()
    assert.is_true(#catalog > 0)
  end)

  it("every entry has a key, a summary, and a boolean builtin flag", function()
    for _, entry in ipairs(catalog) do
      assert.equals("string", type(entry.key))
      assert.is_true(#entry.key > 0)
      assert.equals("string", type(entry.summary))
      assert.is_true(#entry.summary > 0)
      assert.equals("boolean", type(entry.builtin))
      assert.equals("table", type(entry.used_by))
    end
  end)

  it("has no duplicate keys", function()
    local seen = {}
    for _, entry in ipairs(catalog) do
      assert.is_nil(seen[entry.key], "duplicate catalog key: " .. entry.key)
      seen[entry.key] = true
    end
  end)

  it("every non-builtin entry names a require()-able source", function()
    for _, entry in ipairs(catalog) do
      if not entry.builtin then
        assert.equals("string", type(entry.source), entry.key .. " has no source")
        local ok = pcall(require, entry.source)
        assert.is_true(ok, entry.key .. "'s source %q does not resolve: " .. entry.source)
      end
    end
  end)

  it("every entry's optional `live` reader, if present, is a function", function()
    for _, entry in ipairs(catalog) do
      if entry.live ~= nil then
        assert.equals("function", type(entry.live), entry.key .. "'s live is not a function")
      end
    end
  end)

  describe("plugin_progress's live reader", function()
    local sl = require("lib.nvim.progress.styles.statusline")
    local entry
    for _, e in ipairs(catalog) do
      if e.key == "plugin_progress" then
        entry = e
      end
    end

    local original_active

    before_each(function()
      original_active = sl.active
    end)

    after_each(function()
      sl.active = original_active
    end)

    it("is nil when nothing is running", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      sl.active = function()
        return {}
      end
      assert.is_nil(entry.live())
    end)

    it("joins every active operation's text, oldest first", function()
      ---@diagnostic disable-next-line: duplicate-set-field
      sl.active = function()
        return { "[repos] cloning 3/10", "[replace] applying" }
      end
      assert.equals("[repos] cloning 3/10\n[replace] applying", entry.live())
    end)
  end)
end)

describe(":UI modules", function()
  -- Idempotent: some other spec in a full-suite run may already have called
  -- this; a standalone run of just this file has not.
  pcall(function()
    require("ui.bindings.usrcmds").setup()
  end)

  it("does not throw", function()
    assert.has_no.errors(function()
      vim.cmd("UI modules")
    end)
  end)
end)

describe(":UI progress", function()
  pcall(function()
    require("ui.bindings.usrcmds").setup()
  end)

  it("does not throw with nothing running", function()
    assert.has_no.errors(function()
      vim.cmd("UI progress")
    end)
  end)

  it("does not throw with an operation active", function()
    local sl = require("lib.nvim.progress.styles.statusline")
    local original_active = sl.active
    ---@diagnostic disable-next-line: duplicate-set-field
    sl.active = function()
      return { "[repos] cloning 3/10" }
    end

    assert.has_no.errors(function()
      vim.cmd("UI progress")
    end)

    sl.active = original_active
  end)
end)
