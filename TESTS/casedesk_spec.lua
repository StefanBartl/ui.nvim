-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.casedesk` -- a thin require of casedesk.nvim's
--- own ready-made `casedesk.statusline.status()`.
---
--- It used to be 169 lines reaching into `casedesk.resolve`,
--- `casedesk.meta`, `casedesk.sla` and `casedesk.config`, and this spec
--- faked all four plus a distinct buffer name per case to work around the
--- module-local cache. Logic, design rules and tests moved into
--- casedesk.nvim (cross-feature report, finding E). What remains is the
--- adapter contract -- the same shape `sandbox_ambient_spec` and
--- `session_status_spec` check.
---
--- casedesk.nvim is not on this suite's runtimepath, so the "installed"
--- cases inject a fake module.

local casedesk = require("ui.statusline.modules.casedesk")

local function uninstall()
  package.loaded["casedesk.statusline"] = nil
end

describe("ui.statusline.modules.casedesk", function()
  after_each(uninstall)

  it("renders empty when casedesk.nvim is not installed", function()
    uninstall()
    assert.equals("", casedesk())
  end)

  it("renders empty when the buffer is not inside a known case", function()
    package.loaded["casedesk.statusline"] = {
      status = function()
        return ""
      end,
    }
    assert.equals("", casedesk())
  end)

  it("passes casedesk.nvim's own segment through unchanged", function()
    package.loaded["casedesk.statusline"] = {
      status = function()
        return " %#St_Lsp#AB-1234 Contoso \194\183 3 replies "
      end,
    }
    assert.equals(" %#St_Lsp#AB-1234 Contoso \194\183 3 replies ", casedesk())
  end)

  it("passes an SLA badge through unchanged too", function()
    package.loaded["casedesk.statusline"] = {
      status = function()
        return " AB-1 X \194\183 0 replies  %#DiagnosticError#SLA! -0h20m "
      end,
    }
    assert.is_true(casedesk():find("SLA!", 1, true) ~= nil)
  end)

  -- The adapter must not assume the sibling returns a string: a plugin
  -- mid-refactor returning nil should leave the statusline alone rather
  -- than concatenating nil into it.
  it("renders empty when the sibling returns nothing", function()
    package.loaded["casedesk.statusline"] = {
      status = function()
        return nil
      end,
    }
    assert.equals("", casedesk())
  end)
end)
