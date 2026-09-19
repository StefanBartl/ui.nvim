-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.context` -- the sticky code-context overlay. Runs against a real
--- window over a real Lua buffer with Neovim's bundled Lua parser: the
--- window is made short, scrolled by `winrestview`, and the overlay's own
--- buffer is read back. No autocmd timing is relied on -- every assertion
--- calls `refresh()` itself, so what is tested is the context computation
--- and the drawing, not the debounce.

local context = require("ui.context")

local SOURCE = {
  "local M = {}",
  "",
  "local function outer(a, b)",
  "  if a > b then",
  "    for i = 1, 10 do",
  "      local x = i * 2",
  "      print(x)",
  "      print(x + 1)",
  "      print(x + 2)",
  "      print(x + 3)",
  "      print(x + 4)",
  "      print(x + 5)",
  "      print(x + 6)",
  "      print(x + 7)",
  "    end",
  "  end",
  "  return a",
  "end",
  "",
  "return M",
}

---@return integer win, integer buf
local function open_source()
  vim.cmd("new")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, SOURCE)
  vim.bo[buf].filetype = "lua"
  vim.bo[buf].buftype = ""
  vim.api.nvim_win_set_height(win, 8)
  vim.wo[win].number = true
  return win, buf
end

---@param win integer
---@param topline integer  1-based
local function scroll_to(win, topline)
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview({ topline = topline, lnum = topline + 6, col = 0 })
  end)
end

---@param win integer
---@return string[]
local function overlay_lines(win)
  local fwin, fbuf = context.float(win)
  if not fwin then
    return {}
  end
  return vim.api.nvim_buf_get_lines(fbuf, 0, -1, false)
end

local has_lua_parser = pcall(vim.treesitter.language.add, "lua")

describe("ui.context", function()
  after_each(function()
    context.disable()
    context.setup({ max_lines = 3, trim = "outer", min_window_height = 6, line_numbers = true })
    vim.cmd("silent! %bwipeout!")
  end)

  it("is off by default", function()
    assert.is_false(context.is_enabled())
    assert.is_nil(context.float())
  end)

  it("enable()/disable()/toggle() flip the state and close the overlays", function()
    context.enable()
    assert.is_true(context.is_enabled())
    context.disable()
    assert.is_false(context.is_enabled())
    assert.is_true(context.toggle())
    assert.is_false(context.toggle())
  end)

  it("finds the enclosing scopes above the top line, outermost first", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local _, buf = open_source()
    -- Top line 7 (0-based 6): inside for (row 4), if (row 3), function (row 2).
    local entries = context.contexts(buf, 6)
    assert.is_table(entries)
    assert.equals(3, #entries)
    assert.equals(2, entries[1].row)
    assert.equals(3, entries[2].row)
    assert.equals(4, entries[3].row)
    assert.truthy(entries[1].type:find("function"))
  end)

  it("reports nothing at the top of the buffer, and nil without a parser", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local _, buf = open_source()
    assert.equals(0, #context.contexts(buf, 0))
    local plain = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(plain, 0, -1, false, { "just", "text" })
    assert.is_nil(context.contexts(plain, 1))
  end)

  it("draws an overlay with the context lines and the source line numbers", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local win = open_source()
    context.enable()
    scroll_to(win, 7)
    local shown = context.refresh(win)
    assert.equals(3, shown)
    local lines = overlay_lines(win)
    assert.equals(3, #lines)
    assert.truthy(lines[1]:find("local function outer"))
    assert.truthy(lines[1]:find("^%s*3 "), "line number gutter: " .. lines[1])
    assert.truthy(lines[3]:find("for i = 1, 10 do"))
    local fwin = context.float(win)
    local wcfg = vim.api.nvim_win_get_config(fwin)
    assert.equals("win", wcfg.relative)
    assert.equals(vim.api.nvim_win_get_width(win), wcfg.width)
    assert.is_false(wcfg.focusable)
  end)

  it(
    "caps at max_lines, dropping the outer contexts by default and the inner ones on request",
    function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ max_lines = 1 })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local lines = overlay_lines(win)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("for i"), "outer trimmed keeps the innermost: " .. lines[1])

      context.setup({ max_lines = 1, trim = "inner" })
      context.refresh(win)
      lines = overlay_lines(win)
      assert.truthy(
        lines[1]:find("local function outer"),
        "inner trimmed keeps the outermost: " .. lines[1]
      )
    end
  )

  it("closes the overlay when the top line has no context, and on disable", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local win = open_source()
    context.enable()
    scroll_to(win, 7)
    context.refresh(win)
    assert.is_not_nil(context.float(win))
    scroll_to(win, 1)
    assert.equals(0, context.refresh(win))
    assert.is_nil(context.float(win))

    scroll_to(win, 7)
    context.refresh(win)
    assert.is_not_nil(context.float(win))
    context.disable()
    assert.is_nil(context.float(win))
  end)

  it("skips windows that are too short, floats, and special buffers", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local win = open_source()
    context.setup({ min_window_height = 20 })
    context.enable()
    scroll_to(win, 7)
    assert.equals(0, context.refresh(win))
    context.setup({ min_window_height = 6 })
    assert.equals(3, context.refresh(win))

    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = "nofile"
    assert.equals(0, context.refresh(win))
  end)

  it("never covers the cursor line in the focused window", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local win = open_source()
    context.enable()
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = 7, lnum = 7, col = 0 })
    end)
    -- Cursor on the first visible row: an overlay would sit on it.
    assert.equals(0, context.refresh(win))
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({ topline = 7, lnum = 13, col = 0 })
    end)
    assert.equals(3, context.refresh(win))
  end)

  it("go_to_context jumps to the innermost, then outer, enclosing scope", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local win = open_source()
    scroll_to(win, 7)
    assert.is_true(context.go_to_context())
    assert.equals(5, vim.api.nvim_win_get_cursor(win)[1])
    scroll_to(win, 7)
    assert.is_true(context.go_to_context(3))
    assert.equals(3, vim.api.nvim_win_get_cursor(win)[1])
    scroll_to(win, 1)
    assert.is_false(context.go_to_context())
  end)
end)
