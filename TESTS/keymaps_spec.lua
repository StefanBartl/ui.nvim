-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.bindings.keymaps` -- buffer/tab/theme navigation through
--- `lib.nvim.bindings.keymap.register()`'s named-action mechanism: every
--- action binds at its shipped default with NO opt-in required, matching
--- `register()`'s own behavior and the same shape `my.nvim`'s
--- `bindings/keymaps.lua` uses. Regression coverage for two things found
--- live: `<Tab>`/`<S-Tab>` breaking when `lua/wkdnvchad/` (the only thing
--- binding them in that host) was removed, and this module's own first fix
--- requiring `{ all = true }` to bind anything at all -- an opt-in gate
--- nothing else in this ecosystem's keymap.register() callers has.

local keymaps = require("ui.bindings.keymaps")
local keymap = require("lib.nvim.bindings.keymap")

--- One `ui.nvim` entry for `name`, or nil.
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

local ALL_ACTIONS = {
  "next",
  "prev",
  "close",
  "close_all",
  "move_right",
  "move_left",
  "move_to_tab",
  "toggle_theme",
  "theme_picker",
}

describe("ui.bindings.keymaps toggle_sticky", function()
  local context = require("ui.context")

  after_each(function()
    context.disable()
    pcall(vim.keymap.del, "n", "<M-p>")
  end)

  it("is registered but bound to nothing by default", function()
    keymaps.setup()
    local entry = find_registered("toggle_sticky")
    assert.is_not_nil(entry, "registered")
    assert.is_false(entry.bound == true, "no key unasked")
  end)

  it("binds the key the host names and toggles the sticky context with it", function()
    keymaps.setup({ toggle_sticky = "<M-p>" })
    assert.is_true(find_registered("toggle_sticky").bound)
    local map = vim.fn.maparg("<M-p>", "n", false, true)
    assert.equals("ui.nvim: toggle the sticky code context", map.desc)

    assert.is_false(context.is_enabled())
    map.callback()
    assert.is_true(context.is_enabled())
    map.callback()
    assert.is_false(context.is_enabled())
  end)
end)

describe("ui.bindings.keymaps.setup with no opts", function()
  it("binds every action at its shipped default -- no opt-in required", function()
    keymaps.setup()

    assert.equals("<Tab>", find_registered("next").lhs)
    assert.equals("<S-Tab>", find_registered("prev").lhs)
    assert.equals("<leader>bc", find_registered("close").lhs)
    assert.equals("<leader>bq", find_registered("close_all").lhs)
    assert.equals("<leader>tr", find_registered("move_right").lhs)
    assert.equals("<leader>tl", find_registered("move_left").lhs)
    assert.equals("<leader>tt", find_registered("move_to_tab").lhs)
    assert.equals("<leader>ut", find_registered("toggle_theme").lhs)
    assert.equals("<leader>uP", find_registered("theme_picker").lhs)
  end)

  it("binds every action the same way when called with an empty table", function()
    keymaps.setup({})
    for _, name in ipairs(ALL_ACTIONS) do
      assert.is_not_nil(find_registered(name), name .. " should be registered")
      assert.is_true(find_registered(name).bound, name .. " should be bound")
    end
  end)

  it("binds every action the same way when called with true", function()
    keymaps.setup(true)
    for _, name in ipairs(ALL_ACTIONS) do
      assert.is_true(find_registered(name).bound, name .. " should be bound")
    end
  end)
end)

describe("ui.bindings.keymaps.setup(false)", function()
  it("binds nothing, without throwing", function()
    assert.has_no.errors(function()
      keymaps.setup(false)
    end)
  end)
end)

describe("ui.bindings.keymaps.setup with per-action overrides", function()
  it("remaps one action, leaving the others at their default", function()
    keymaps.setup({ next = "<C-Right>" })

    assert.equals("<C-Right>", find_registered("next").lhs)
    assert.equals("<S-Tab>", find_registered("prev").lhs)
    assert.equals("<leader>bc", find_registered("close").lhs)
  end)

  it("drops one action with <name> = false, without touching the rest", function()
    keymaps.setup({ close = false })

    local close_entry = find_registered("close")
    assert.is_not_nil(close_entry) -- still declared -- register() records it as unbound, not absent
    assert.is_nil(close_entry.lhs)
    assert.is_false(close_entry.bound)

    assert.equals("<Tab>", find_registered("next").lhs)
    assert.equals("<leader>ut", find_registered("toggle_theme").lhs)
  end)

  it("does not warn about an unknown action for any of the eight real names", function()
    local warned = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      warned[#warned + 1] = { msg = msg, level = level }
    end

    keymaps.setup({
      next = "<C-n>",
      prev = false,
      move_right = "<C-Right>",
      toggle_theme = "<leader>tt2",
    })

    vim.notify = original_notify

    for _, w in ipairs(warned) do
      assert.is_nil(
        tostring(w.msg):find("no such keymap action", 1, true),
        "unexpected unknown-action warning: " .. tostring(w.msg)
      )
    end
  end)
end)
