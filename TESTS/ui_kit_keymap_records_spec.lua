-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- A kit popup must not leave keymap records behind. `lib.nvim.bindings.keymap`
--- records every mapping it sets unless `record = false`, keyed by
--- (buffer, lhs, mode, call site) and never removed -- and each popup has a new
--- buffer, so every open added its buffer-local keys to the records for good
--- (20 per chooser), and each record holds its `rhs` closure, which keeps the
--- popup's state alive with it. These keys are throwaway buffer-local keys of a
--- float, not public surface: there is nothing for the records to describe.
---
--- Every component is opened and closed a number of times and the total number
--- of records must not change. A control first proves the counter can see a
--- leak at all, so a changed records API cannot turn this into a vacuous pass.

local kit = require("ui.kit")
local keymap = require("lib.nvim.bindings.keymap")
local records = require("lib.nvim.bindings.keymap.records")

--- Every record `set()` has kept, whichever plugin bucket it landed in.
---@return integer
local function total()
  local n = 0
  for _, list in pairs(records.all()) do
    n = n + #list
  end
  return n
end

local ROUNDS = 8

---@type table<string, { open: fun(), close: fun() }>
local COMPONENTS = {
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

describe("ui.kit keymap records", function()
  after_each(function()
    vim.cmd("stopinsert")
    vim.cmd("silent! %bwipeout!")
  end)

  it("the counter sees a recorded keymap, and `record = false` keeps one out", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local before = total()
    keymap("n", "x", function() end, { buffer = buf })
    assert.equals(before + 1, total(), "a plain set() is recorded")
    keymap("n", "y", function() end, { buffer = buf, record = false })
    assert.equals(before + 1, total(), "record = false is not")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  local names = vim.tbl_keys(COMPONENTS)
  table.sort(names)
  for _, name in ipairs(names) do
    it(name .. ": opening and closing it leaves no keymap records behind", function()
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
        ("%s added %d keymap records over %d opens"):format(name, total() - before, ROUNDS)
      )
    end)
  end
end)
