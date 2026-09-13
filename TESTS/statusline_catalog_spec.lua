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

  it("does not catalogue the known-dead neotest_module", function()
    for _, entry in ipairs(catalog) do
      assert.is_not.equals("neotest_module", entry.key)
    end
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
