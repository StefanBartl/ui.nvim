-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.keys` -- the mappings under a prefix, as a tree and as a menu.

local keys = require("ui.keys")

describe("ui.keys", function()
  local hits = {}
  local PREFIX = "<leader>y"

  before_each(function()
    hits = {}
    vim.g.mapleader = " "
    vim.keymap.set("n", PREFIX .. "a", function()
      hits[#hits + 1] = "a"
    end, { desc = "Alpha" })
    vim.keymap.set("n", PREFIX .. "ba", function()
      hits[#hits + 1] = "ba"
    end, { desc = "Beta one" })
    vim.keymap.set("n", PREFIX .. "bb", function()
      hits[#hits + 1] = "bb"
    end, { desc = "Beta two" })
    vim.keymap.set("n", PREFIX .. "<C-x>", function()
      hits[#hits + 1] = "cx"
    end, { desc = "Control x" })
    vim.keymap.set("n", PREFIX .. "h", function() end, { desc = "which_key_ignore" })
    keys.setup({ groups = { [PREFIX .. "b"] = "Betas" } })
  end)

  after_each(function()
    for _, lhs in ipairs({ "a", "ba", "bb", "<C-x>", "h", "z" }) do
      pcall(vim.keymap.del, "n", PREFIX .. lhs)
    end
    pcall(vim.keymap.del, "n", PREFIX .. "z", { buffer = 0 })
    vim.cmd("silent! %bwipeout!")
  end)

  it("lists the mappings under a prefix, hidden ones excluded, sorted", function()
    local maps = keys.mappings(PREFIX)
    local rests = vim.tbl_map(function(m)
      return m.rest
    end, maps)
    assert.same({ "<C-X>", "a", "ba", "bb" }, rests)
    assert.equals("Alpha", maps[2].desc)
    assert.same({ "<C-X>" }, maps[1].tokens)
    assert.same({ "b", "a" }, maps[3].tokens)
  end)

  it("prefers a buffer-local mapping over the global one", function()
    vim.keymap.set("n", PREFIX .. "z", function() end, { desc = "global z" })
    vim.keymap.set("n", PREFIX .. "z", function() end, { desc = "local z", buffer = 0 })
    local maps = keys.mappings(PREFIX)
    local z
    for _, m in ipairs(maps) do
      if m.rest == "z" then
        z = m
      end
    end
    assert.equals("local z", z.desc)
    assert.is_true(z.buffer)
  end)

  it("builds leaves and named groups", function()
    local nodes = keys.tree(PREFIX)
    local by_token = {}
    for _, n in ipairs(nodes) do
      by_token[n.token] = n
    end
    assert.equals("Alpha", by_token["a"].label)
    assert.is_nil(by_token["a"].children)
    assert.equals("Betas", by_token["b"].label)
    assert.equals(2, #by_token["b"].children)
    assert.equals("Beta two", by_token["b"].children[2].label)
    assert.equals("Control x", by_token["<C-X>"].label)
  end)

  it("opens a menu and a picked row runs the mapping", function()
    local surf = keys.open(PREFIX)
    assert.is_not_nil(surf)
    assert.is_true(vim.api.nvim_win_is_valid(surf.winid))
    surf:close()
    -- The runner behind a leaf feeds the raw keys.
    local nodes = keys.tree(PREFIX)
    local a
    for _, n in ipairs(nodes) do
      if n.token == "a" then
        a = n
      end
    end
    vim.api.nvim_feedkeys(a.mapping.raw, "mtx", false)
    assert.same({ "a" }, hits)
  end)

  it("returns nil for a prefix with nothing under it", function()
    assert.is_nil(keys.open("<leader>qqqq"))
  end)
end)
