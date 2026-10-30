-- @cache-inputs TESTS/__snapshots__/
-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field

-- `kit.confirm` as the user sees it: the dialog is opened in a real embedded editor
-- (testing.rpc, 80x24) and its screen -- text and highlight attributes -- is compared with the
-- reviewed snapshot in TESTS/__snapshots__/ (testing.screen). The attribute rows show the
-- hotkey marking: the marked letter of each button carries an attribute of its own.
-- A changed dialog fails with the differing rows; `scripts/test.sh --update-snapshots` accepts it.

local rpc = require("testing.rpc")
local screen = require("testing.screen")

local this = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p"))
local root = vim.fs.dirname(vim.fs.dirname(this))

describe("ui.kit.confirm on screen", function()
  local child

  before_each(function()
    local err
    child, err = rpc.spawn({
      root = root,
      minit = root .. "/TESTS/minimal_init.lua",
      size = { rows = 24, cols = 80 },
      guard = false,
    })
    assert(child, err)
  end)

  after_each(function()
    if child then
      child.kill()
      child = nil
    end
  end)

  it("Yes/No/Cancel/Overwrite with the focus on No: buttons, hotkeys and focus as drawn", function()
    child.lua([[
      require("ui.kit").confirm({
        question = "The file exists. Overwrite it?",
        choices = { "Yes", "No", "Cancel", "Overwrite" },
        default = 2,
        on_answer = function() end,
      })
    ]])
    assert(child.settle(3000))
    screen.check("confirm-four-buttons.80x24", child.screen(), { file = this, root = root })
  end)
end)
