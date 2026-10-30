-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.sidebar`: the themed split panel (a re-export of `lib.nvim.ui.kit.sidebar`, whose
--- TESTS/ui_kit_sidebar_spec.lua covers every branch). This pins the ui.nvim names and the
--- contract a consumer (a test explorer) relies on: a fixed-width split themed by the kit, found
--- by its buffer variable, displacing and restoring another sidebar once, and one cleanup.

local sidebar = require("ui.kit.sidebar")
local api = vim.api

--- Let the restore run: it is deferred by two `vim.schedule` ticks.
local function settle()
  vim.wait(50, function()
    return false
  end)
end

describe("ui.kit.sidebar", function()
  local tab

  before_each(function()
    vim.cmd("tabnew")
    tab = api.nvim_get_current_tabpage()
  end)

  after_each(function()
    sidebar.close_all()
    settle()
    if api.nvim_tabpage_is_valid(tab) and #api.nvim_list_tabpages() > 1 then
      vim.cmd("tabclose")
    end
  end)

  it("is lib.nvim's module under both names", function()
    assert.equals(require("lib.nvim.ui.kit.sidebar"), sidebar)
    assert.equals(sidebar, require("ui.kit").sidebar)
    assert.equals(require("lib.nvim.ui.kit.sidebar_state"), require("ui.kit.sidebar_state"))
  end)

  it("opens a themed, fixed-width split found by its buffer variable", function()
    local s = sidebar.open({ name = "explorer", position = "right", size = 28, title = "Tests" })
    assert.equals("", api.nvim_win_get_config(s.winid).relative)
    assert.equals(28, api.nvim_win_get_width(s.winid))
    assert.is_true(api.nvim_get_option_value("winfixwidth", { win = s.winid }))
    local winhl = api.nvim_get_option_value("winhighlight", { win = s.winid })
    assert.truthy(winhl:find("Normal:KitNormal_", 1, true))
    assert.truthy(winhl:find("CursorLine:KitSelection", 1, true))
    assert.equals(" Tests", api.nvim_get_option_value("winbar", { win = s.winid }))
    assert.equals(s.winid, sidebar.find("explorer"))
  end)

  it("restores the sidebar it displaced, once", function()
    local tree = sidebar.open({ name = "tree" })
    local explorer = sidebar.open({ name = "explorer" })
    assert.is_false(tree:is_visible())
    assert.is_true(explorer:is_visible())
    explorer:close()
    settle()
    assert.is_true(tree:is_visible())
    assert.is_true(tree:hide())
    settle()
    assert.is_false(tree:is_visible())
  end)

  it("close_all closes visible and hidden sidebars", function()
    local closed = 0
    local function count()
      closed = closed + 1
    end
    sidebar.open({ name = "tree", on_close = count })
    sidebar.open({ name = "explorer", on_close = count })
    sidebar.close_all()
    settle()
    assert.equals(2, closed)
    assert.equals(0, #sidebar.list())
    assert.is_nil(sidebar.find("tree"))
  end)
end)
