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
    context.setup({
      max_lines = 3,
      trim = "outer",
      min_window_height = 6,
      line_numbers = true,
      headings = { enable = true },
    })
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

  it("redraws when the enclosing declaration is edited in place", function()
    if not has_lua_parser then
      pending("no Lua parser available")
      return
    end
    local win, buf = open_source()
    context.enable()
    scroll_to(win, 7)
    context.refresh(win)
    local lines = overlay_lines(win)
    assert.truthy(lines[1]:find("local function outer"))
    -- Rename the enclosing function in place: same row (0), same node
    -- type, so a cache keyed only on context row numbers + window width
    -- would (wrongly) skip the redraw and keep showing the old name.
    vim.api.nvim_buf_set_lines(buf, 2, 3, false, { "local function outer_RENAMED(a, b)" })
    context.refresh(win)
    lines = overlay_lines(win)
    assert.truthy(
      lines[1]:find("outer_RENAMED"),
      "overlay did not pick up the in-place rename: " .. lines[1]
    )
  end)

  describe("markdown headings", function()
    local has_markdown_parser = pcall(vim.treesitter.language.add, "markdown")

    local DOC = {
      "# Title",
      "",
      "## Section",
      "",
      "### Detail",
      "",
      "text one",
      "text two",
      "text three",
      "text four",
      "text five",
      "text six",
      "text seven",
      "text eight",
    }

    ---@return integer win, integer buf
    local function open_doc()
      vim.cmd("new")
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, DOC)
      vim.bo[buf].filetype = "markdown"
      vim.bo[buf].buftype = ""
      vim.api.nvim_win_set_height(win, 8)
      vim.wo[win].number = true
      return win, buf
    end

    ---@param win integer
    ---@return table[] marks  { row, col, details }
    local function overlay_marks(win)
      local _, fbuf = context.float(win)
      local ns = vim.api.nvim_get_namespaces().ui_context
      return vim.api.nvim_buf_get_extmarks(fbuf, ns, 0, -1, { details = true })
    end

    ---@param marks table[]
    ---@param row integer
    ---@param key string
    ---@return table[]
    local function on_row(marks, row, key)
      local out = {}
      for _, m in ipairs(marks) do
        if m[2] == row and m[4][key] then
          out[#out + 1] = m[4]
        end
      end
      return out
    end

    ---@param marks table[]
    ---@param row integer
    ---@param key string
    ---@param value string
    ---@return boolean
    local function has(marks, row, key, value)
      for _, d in ipairs(on_row(marks, row, key)) do
        if d[key] == value then
          return true
        end
      end
      return false
    end

    it("styles a heading line with its level's group, a row band and an icon", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_doc()
      context.enable()
      scroll_to(win, 8)
      assert.is_true(context.refresh(win) >= 2)

      local lines = overlay_lines(win)
      local marks = overlay_marks(win)
      -- The context is Title/Section/Detail, trimmed to the last three: the
      -- deepest one is on the last row, and carries level 3.
      local last = #lines - 1
      assert.truthy(lines[#lines]:find("### Detail", 1, true))

      assert.is_true(has(marks, last, "hl_group", "UiContextH3"), "level-3 text group")
      assert.is_true(has(marks, last, "line_hl_group", "UiContextH3Row"), "row band")
      -- The rule under the last row is still there next to the band.
      assert.is_true(has(marks, last, "line_hl_group", "UiContextBottom"), "bottom rule")

      local icon = on_row(marks, last, "virt_text")[1]
      assert.equals("overlay", icon.virt_text_pos)
      -- Level 3 covers the three cells of `###`.
      assert.equals(3, vim.fn.strdisplaywidth(icon.virt_text[1][1]))
    end)

    it("leaves the marker alone with icons switched off", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_doc()
      context.setup({ headings = { icons = false } })
      context.enable()
      scroll_to(win, 8)
      context.refresh(win)

      local marks = overlay_marks(win)
      for row = 0, #overlay_lines(win) - 1 do
        assert.equals(0, #on_row(marks, row, "virt_text"))
      end
      assert.is_true(has(marks, #overlay_lines(win) - 1, "hl_group", "UiContextH3"))
    end)

    it("draws headings as plain source lines when headings are off", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_doc()
      context.setup({ headings = false })
      context.enable()
      scroll_to(win, 8)
      context.refresh(win)

      for _, m in ipairs(overlay_marks(win)) do
        local d = m[4]
        assert.is_falsy(d.hl_group and d.hl_group:find("^UiContextH%d"))
        assert.is_falsy(d.virt_text)
      end
    end)

    it("does not treat a hash line in a non-markdown buffer as a heading", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      vim.bo.filetype = "lua"
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      for _, m in ipairs(overlay_marks(win)) do
        assert.is_falsy(m[4].virt_text)
      end
    end)
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
