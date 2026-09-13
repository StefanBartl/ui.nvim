-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Two small, opt-in statusline segments from IDEEN-statusline.md's "klein,
--- isoliert, schnell" bucket -- neither is wired into a shipped preset, a
--- host adds them to its own `order`/`modules`.

describe("ui.statusline.modules.undo_depth", function()
  local undo_depth = require("ui.statusline.modules.undo_depth")

  it("renders empty on a fresh buffer with nothing to undo", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    assert.equals("", undo_depth())

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("shows the undo depth once an edit has been made", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one" })
    vim.cmd("normal! ihello ")
    vim.cmd("stopinsert")
    vim.cmd("undojoin | normal! " .. vim.api.nvim_replace_termcodes("<Esc>", true, false, true))

    local out = undo_depth()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(out:find("↺", 1, true) ~= nil, out)
  end)

  it("never throws even if vim.fn.undotree errors", function()
    local original = vim.fn.undotree
    vim.fn.undotree = function()
      error("boom")
    end

    local ok, out = pcall(undo_depth)

    vim.fn.undotree = original

    assert.is_true(ok, tostring(out))
    assert.equals("", out)
  end)
end)

describe("ui.statusline.modules.search_count", function()
  local search_count = require("ui.statusline.modules.search_count")

  it("renders empty when hlsearch is off", function()
    local saved = vim.v.hlsearch
    vim.v.hlsearch = 0

    assert.equals("", search_count())

    vim.v.hlsearch = saved
  end)

  it("renders [current/total] when hlsearch is on and there is a match", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "foo", "foo", "foo" })
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local saved_hlsearch = vim.v.hlsearch
    vim.fn.setreg("/", "foo")
    vim.v.hlsearch = 1

    local out = search_count()

    vim.v.hlsearch = saved_hlsearch
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(out:find("%[%d+/3%]") ~= nil, out)
  end)

  it("never throws even if vim.fn.searchcount errors", function()
    local saved = vim.v.hlsearch
    vim.v.hlsearch = 1
    local original = vim.fn.searchcount
    vim.fn.searchcount = function()
      error("boom")
    end

    local ok, out = pcall(search_count)

    vim.fn.searchcount = original
    vim.v.hlsearch = saved

    assert.is_true(ok, tostring(out))
    assert.equals("", out)
  end)
end)
