---@diagnostic disable: need-check-nil, undefined-field

--- The argument types of `:UI` go into lib.nvim's process-wide type registry. They are written by
--- `setup()`, not as a side effect of `require("ui.bindings.usrcmds")`.

local argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")

local TYPES = {
  "UI_THEME",
  "UI_VARIANT",
  "UI_TABLINE_STYLE",
  "UI_KIT_PRESET",
  "UI_SLOT_WORD",
  "UI_STICKY_WORD",
}

---@param name string
---@return boolean
local function registered(name)
  return argtypes.get(name) ~= argtypes.get("STRING")
end

describe("the :UI argument types", function()
  it("are not in the global registry after a bare require", function()
    local usrcmds = require("ui.bindings.usrcmds")
    assert.is_table(usrcmds)
    for _, name in ipairs(TYPES) do
      assert.is_false(registered(name), name .. " is registered by require")
    end
  end)

  it("are registered by setup()", function()
    require("ui.bindings.usrcmds").setup()
    for _, name in ipairs(TYPES) do
      assert.is_true(registered(name), name .. " is not registered by setup()")
    end
  end)

  it("stay registered when setup() runs twice", function()
    require("ui.bindings.usrcmds").setup()
    for _, name in ipairs(TYPES) do
      assert.is_true(registered(name), name)
    end
  end)
end)
