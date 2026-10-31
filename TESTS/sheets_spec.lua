-- @cache-inputs TESTS/sheets/ TESTS/__snapshots__/
-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: undefined-field

-- The live checks of TESTS/sheets/*.sheet.lua (testing.sheet): each sheet is one case named
-- `sheet:<id>`, run by the RPC klicker; `testing sheets report` lists them with this result.

local sheet = require("testing.sheet")

local this = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local root = vim.fs.dirname(vim.fs.dirname(this))

describe("test sheets", function()
  for _, path in ipairs(sheet.files(root .. "/TESTS/sheets")) do
    local s, err = sheet.load(path)
    it(s and sheet.spec_name(s) or path, function()
      assert(s, err)
      sheet.check(s, { root = root })
    end)
  end
end)
