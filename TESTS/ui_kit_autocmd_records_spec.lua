-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- A kit popup must not leave autocmd records behind. `lib.nvim.bindings.autocmd`
--- records every autocmd it creates unless `record = false`, and drops a record
--- only through `delete(id)` or when the same group is asked for again. The kit
--- hooks each float under a group named after its window id -- new for every
--- popup, deleted with `nvim_del_augroup_by_id` -- so every open added its hooks
--- to the records for good (a surface one, a shortlist five, a picker five).
--- These are throwaway hooks of one float, not part of any plugin's autocmd
--- surface: nothing generated from the records should describe them.
---
--- Every component is opened and closed a number of times and the total number
--- of records must not change. A control first proves the counter can see a
--- recorded autocmd at all, and that `record = false` still creates a live one,
--- so a changed records API cannot turn this into a vacuous pass. (The keymap
--- twin of this spec is `ui_kit_keymap_records_spec.lua`.)

local kit = require("ui.kit")
local autocmd = require("lib.nvim.bindings.autocmd")

---@return integer
local function total()
  return #autocmd.registered()
end

local ROUNDS = 8

---@type table<string, { open: fun(), close: fun() }>
local COMPONENTS = {
  surface = {
    open = function()
      _G.__records_spec_handle = kit.surface.open({ lines = { "x" } })
    end,
    close = function()
      _G.__records_spec_handle:close()
      _G.__records_spec_handle = nil
    end,
  },
  chooser = {
    open = function()
      kit.select({ selection = { "a", "b" }, on_select = function() end })
    end,
    close = function()
      require("ui.kit.chooser").close()
    end,
  },
  confirm = {
    open = function()
      kit.confirm({ question = "Sure?", on_answer = function() end })
    end,
    close = function()
      require("ui.kit.confirm").close()
    end,
  },
  menu = {
    open = function()
      kit.menu({ items = { { label = "One", action = function() end } } })
    end,
    close = function()
      require("ui.kit.menu").close()
    end,
  },
  shortlist = {
    open = function()
      _G.__records_spec_handle = kit.shortlist({
        items = { "a", "b" },
        render = function() end,
        preview_bo = { modifiable = false },
      })
    end,
    close = function()
      _G.__records_spec_handle.close()
      _G.__records_spec_handle = nil
    end,
  },
  picker = {
    open = function()
      _G.__records_spec_handle = kit.picker({ on_submit = function() end })
    end,
    close = function()
      _G.__records_spec_handle.close()
      _G.__records_spec_handle = nil
      vim.cmd("stopinsert")
    end,
  },
  compare = {
    open = function()
      _G.__records_spec_handle = kit.compare({
        items = { "x", "y" },
        render = function(item, surface)
          surface:set_lines({ item })
        end,
      })
    end,
    close = function()
      _G.__records_spec_handle.close()
      _G.__records_spec_handle = nil
      vim.cmd("stopinsert")
    end,
  },
}

describe("ui.kit autocmd records", function()
  after_each(function()
    vim.cmd("stopinsert")
    vim.cmd("silent! %bwipeout!")
  end)

  it("the counter sees a recorded autocmd, and `record = false` keeps one out but alive", function()
    local group = autocmd.group("ui_kit_records_spec_control", true)
    local hits = 0
    local before = total()
    autocmd.create("User", function()
      hits = hits + 1
    end, { group = group, pattern = "UiKitRecordsSpecA" })
    assert.equals(before + 1, total(), "a plain create() is recorded")
    autocmd.create("User", function()
      hits = hits + 1
    end, { group = group, pattern = "UiKitRecordsSpecB", record = false })
    assert.equals(before + 1, total(), "record = false is not")
    vim.api.nvim_exec_autocmds("User", { pattern = "UiKitRecordsSpecB" })
    assert.equals(1, hits, "...and it still fires")
    pcall(vim.api.nvim_del_augroup_by_id, group)
    autocmd.group("ui_kit_records_spec_control", true) -- forgets the control's record
    pcall(vim.api.nvim_del_augroup_by_name, "ui_kit_records_spec_control")
  end)

  local names = vim.tbl_keys(COMPONENTS)
  table.sort(names)
  for _, name in ipairs(names) do
    it(name .. ": opening and closing it leaves no autocmd records behind", function()
      local c = COMPONENTS[name]
      -- One round first: whatever a first use sets up once is not a leak.
      c.open()
      c.close()
      local before = total()
      for _ = 1, ROUNDS do
        c.open()
        c.close()
      end
      assert.equals(
        before,
        total(),
        ("%s added %d autocmd records over %d opens"):format(name, total() - before, ROUNDS)
      )
    end)
  end
end)
