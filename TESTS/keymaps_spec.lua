-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.bindings.keymaps` -- buffer/tab navigation through
--- `lib.nvim.bindings.keymap.register()`'s named-action mechanism: every
--- left-hand side is a shipped default, overridable or disabled per action
--- via `opts.keys`. Regression coverage for the Tab/S-Tab breakage found
--- live after `lua/wkdnvchad/` (the only thing binding them in that host)
--- was removed -- `ui.setup({ keymaps = true })` is the replacement, and
--- this proves it actually binds, and that overrides reach the right action.

local keymaps = require("ui.bindings.keymaps")
local keymap = require("lib.nvim.bindings.keymap")

--- One `ui.nvim` entry (either surface -- register()'s `opts.surface`
--- suffixes the *registry key* ("ui.nvim/buffers"), not each entry's own
--- `.plugin` field, which stays "ui.nvim") for `name`, or nil. Reads the
--- whole registry rather than `keymap.registered("ui.nvim")`, which would
--- look for the exact key "ui.nvim" and find nothing -- both surfaces here
--- are stored under "ui.nvim/buffers" and "ui.nvim/tabs".
---@param name string
---@return table|nil
local function find_registered(name)
  for _, entries in pairs(keymap.registered()) do
    for _, entry in ipairs(entries) do
      if entry.plugin == "ui.nvim" and entry.name == name then
        return entry
      end
    end
  end
  return nil
end

describe("ui.bindings.keymaps.setup buffers", function()
  it("binds the default <Tab>/<S-Tab>/<leader>bc when buffers = true", function()
    keymaps.setup({ buffers = true })

    local next_entry = find_registered("next")
    local prev_entry = find_registered("prev")
    local close_entry = find_registered("close")

    assert.is_not_nil(next_entry)
    assert.equals("<Tab>", next_entry.lhs)
    assert.is_true(next_entry.bound)

    assert.is_not_nil(prev_entry)
    assert.equals("<S-Tab>", prev_entry.lhs)

    assert.is_not_nil(close_entry)
    assert.equals("<leader>bc", close_entry.lhs)
  end)

  it("does not bind anything when buffers is left off", function()
    -- register() replaces this surface's own array each call, so a prior
    -- test's bindings do not leak into this assertion.
    keymaps.setup({ buffers = false, tabs = false })
    -- Nothing to assert on the registry (a no-op setup() call touches
    -- neither surface's array) -- the real assertion is that this throws
    -- nothing, which the outer `it` already covers by not erroring.
    assert.has_no.errors(function()
      keymaps.setup({})
    end)
  end)

  it("remaps one action via opts.keys, leaving the others at their default", function()
    keymaps.setup({ buffers = true, keys = { next = "<C-Right>" } })

    assert.equals("<C-Right>", find_registered("next").lhs)
    assert.equals("<S-Tab>", find_registered("prev").lhs)
  end)

  it("drops one action with keys.<name> = false, without touching the rest", function()
    keymaps.setup({ buffers = true, keys = { close = false } })

    local close_entry = find_registered("close")
    assert.is_not_nil(close_entry) -- still declared -- register() records it as unbound, not absent
    assert.is_nil(close_entry.lhs)
    assert.is_false(close_entry.bound)

    assert.equals("<Tab>", find_registered("next").lhs)
  end)

  it("does not warn about a tabs-surface override reaching the buffers registration", function()
    -- Regression: opts.keys is one flat table across both surfaces (a user
    -- writes `keys = { next = ..., move_right = ... }` in one place) --
    -- passing it to attach_buffers()'s register() call unfiltered would
    -- report "move_right" as an unknown buffers action.
    local warned = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      warned[#warned + 1] = { msg = msg, level = level }
    end

    keymaps.setup({
      buffers = true,
      tabs = true,
      keys = { next = "<C-n>", move_right = "<C-Right>" },
    })

    vim.notify = original_notify

    for _, w in ipairs(warned) do
      assert.is_nil(
        tostring(w.msg):find("no such keymap action", 1, true),
        "unexpected unknown-action warning: " .. tostring(w.msg)
      )
    end
    assert.equals("<C-n>", find_registered("next").lhs)
    assert.equals("<C-Right>", find_registered("move_right").lhs)
  end)
end)

describe("ui.bindings.keymaps.setup tabs", function()
  it("binds the default <leader>tr/<leader>tl/<leader>tt when tabs = true", function()
    keymaps.setup({ tabs = true })

    assert.equals("<leader>tr", find_registered("move_right").lhs)
    assert.equals("<leader>tl", find_registered("move_left").lhs)
    assert.equals("<leader>tt", find_registered("move_to_tab").lhs)
  end)
end)

describe("ui.bindings.keymaps.setup all", function()
  it("binds every action across both surfaces", function()
    keymaps.setup({ all = true })

    for _, name in ipairs({ "next", "prev", "close", "move_right", "move_left", "move_to_tab" }) do
      assert.is_not_nil(find_registered(name), name .. " should be registered")
    end
  end)
end)
