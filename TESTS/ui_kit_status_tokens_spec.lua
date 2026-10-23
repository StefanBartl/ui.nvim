-- ui.kit theme: the status tokens `ok`, `warn`, `info` and `dim` (groups KitOk, KitWarn, KitInfo, KitDim), so a list whose
-- rows have a state does not invent groups of its own.
---@diagnostic disable: need-check-nil, undefined-field

describe("ui.kit status tokens", function()
  local theme

  before_each(function()
    package.loaded["ui.kit"] = nil
    theme = require("ui.kit").theme
  end)

  local function link_of(group)
    return vim.api.nvim_get_hl(0, { name = group, link = true }).link
  end

  it("every preset resolves the four tokens, linked to the diagnostic groups by default", function()
    for _, name in ipairs({ "rounded", "minimal", "solid", "double", "ascii", "menu" }) do
      local hl = theme.resolve(name).hl
      assert.are.equal("DiagnosticOk", hl.ok, name)
      assert.are.equal("DiagnosticWarn", hl.warn, name)
      assert.are.equal("DiagnosticInfo", hl.info, name)
      assert.are.equal("Comment", hl.dim, name)
    end
  end)

  it("materializes the groups KitOk, KitWarn, KitInfo and KitDim", function()
    theme.materialize(theme.resolve("rounded"))
    assert.are.equal("DiagnosticOk", link_of("KitOk"))
    assert.are.equal("DiagnosticWarn", link_of("KitWarn"))
    assert.are.equal("DiagnosticInfo", link_of("KitInfo"))
    assert.are.equal("Comment", link_of("KitDim"))
  end)

  it("an override table changes a token and leaves the others", function()
    local resolved = theme.resolve({ hl = { ok = "String", dim = { fg = "#808080" } } })
    assert.are.equal("String", resolved.hl.ok)
    assert.are.same({ fg = "#808080" }, resolved.hl.dim)
    assert.are.equal("DiagnosticWarn", resolved.hl.warn)
    theme.materialize(resolved)
    assert.are.equal("String", link_of("KitOk"))
    assert.are.equal("DiagnosticWarn", link_of("KitWarn"))
    assert.are.equal(
      "#808080",
      string.format("#%06x", vim.api.nvim_get_hl(0, { name = "KitDim" }).fg)
    )
  end)

  it("the fixed-palette preset sets them as colours, not as links", function()
    local hl = theme.resolve("hacker").hl
    for _, key in ipairs({ "ok", "warn", "info", "dim" }) do
      assert.is_table(hl[key], key)
      assert.is_string(hl[key].fg, key)
    end
  end)
end)
