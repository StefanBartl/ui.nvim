-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

-- `kit.confirm` button hotkeys through the `ui.kit` names (the code is lib.nvim's, see its
-- TESTS/ui_kit_confirm_hotkeys_spec.lua for every rule): one key per button picks it without
-- moving the focus -- y/n on Yes/No, the first free letter of the label, else the digit -- and the
-- key is marked in the button.

local api = vim.api

--- Open a dialog; returns its answers and its surface.
local function open(opts)
  local calls = {}
  opts.on_answer = function(v)
    calls[#calls + 1] = v == nil and "nil" or v
  end
  local surf = require("ui.kit").confirm(opts)
  assert(surf, "the dialog opened")
  return calls, surf
end

local function type_keys(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

--- The texts the dialog underlines as hotkeys, in buffer order.
local function hotkeys(buf)
  local out = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    if m[4].hl_group == "KitHotkey" then
      out[#out + 1] = api.nvim_buf_get_text(buf, m[2], m[3], m[2], m[4].end_col, {})[1]
    end
  end
  return out
end

describe("ui.kit.confirm hotkeys", function()
  after_each(function()
    require("ui.kit.confirm").close()
  end)

  it("Yes/No/Cancel/Overwrite: each key picks its button, the focus stays on No", function()
    local confirm = require("ui.kit.confirm")
    local choices = { "Yes", "No", "Cancel", "Overwrite" }
    local calls, surf = open({ question = "Exists.", choices = choices, default = 2 })
    assert.are.equal(2, confirm.current_focus())
    assert.are.same({ "Y", "N", "C", "O" }, hotkeys(surf.bufnr))
    type_keys("c")
    assert.are.same({ "Cancel" }, calls)
    calls = open({ question = "Exists.", choices = choices, default = 2 })
    type_keys("<CR>")
    assert.are.same({ "No" }, calls)
  end)

  it("a taken first letter falls back to the next free one, in button order", function()
    local calls, surf = open({ question = "Q?", choices = { "Cancel", "Close", "Copy" } })
    assert.are.same({ "C", "o", "p" }, hotkeys(surf.bufnr))
    type_keys("o")
    assert.are.same({ "Close" }, calls)
  end)

  it("y answers the Yes button wherever it stands", function()
    local calls = open({ question = "Delete?", choices = { "No", "Yes, delete" } })
    type_keys("y")
    assert.are.same({ "Yes, delete" }, calls)
  end)
end)
