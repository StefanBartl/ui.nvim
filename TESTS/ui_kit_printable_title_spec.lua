-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- A chooser that walks into a submenu rewrites its float's title in place
--- (`chooser.set_items`). The title is spelled out, never drawn raw: `nvim_win_set_config` keeps
--- the control characters of a plain-string title as grid cells of their own, and the TUI writes
--- those to the terminal verbatim, so an ESC ] 0 ; ... BEL in a title built from typed or pasted
--- text could set the terminal's window title. `lib.nvim.window.printable_title` does the
--- spelling (and has its own specs in lib.nvim); `lib.nvim` fixed this in its frozen copy of the
--- chooser first (863952e) and the canonical one here had to take it over.

local chooser = require("ui.kit.chooser")
local api = vim.api

---@return string|nil
local function frame_title()
  for _, w in ipairs(api.nvim_list_wins()) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == "lib-kit-chooser" then
      local cfg = api.nvim_win_get_config(w)
      return cfg.title and cfg.title[1] and cfg.title[1][1] or nil
    end
  end
end

describe("kit.chooser set_items", function()
  after_each(function()
    chooser.close()
  end)

  it("spells out the control characters of a title", function()
    local esc, bel = string.char(27), string.char(7)
    chooser.open({ items = { "a", "b" }, title = "top", on_select = function() end })
    assert.is_true(chooser.is_open(), "the fixture is open")
    assert.equals("top", frame_title())

    assert.is_true(chooser.set_items({ items = { "c", "d" }, title = "Child" }))
    assert.equals("Child", frame_title(), "a plain title is drawn as it is")

    local hostile = "my" .. esc .. "]0;evil" .. bel .. ".txt"
    assert.is_true(chooser.set_items({ items = { "c", "d" }, title = hostile }))
    assert.equals("my^[]0;evil^G.txt", frame_title(), "the escape and the bell are spelled out")

    assert.is_true(chooser.set_items({ items = { "e" }, title = "a\tb" .. string.char(127) }))
    assert.equals("a^Ib^?", frame_title(), "so are a tab and DEL")

    assert.is_true(chooser.set_items({ items = { "e" } }))
    assert.is_true(frame_title() == nil or frame_title() == "", "an omitted title clears it")
  end)
end)
