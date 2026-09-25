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

-- The shipped icons, captured before any test can switch them off.
local DEFAULT_ICONS = vim.deepcopy(context.config().headings.icons)
local DEFAULT_NODE_TYPES = vim.deepcopy(context.config().node_types)
local DEFAULT_EXCLUDES = vim.deepcopy(context.config().exclude_node_types)

describe("ui.context", function()
  after_each(function()
    context.disable()
    context.setup({
      max_lines = 3,
      trim = "outer",
      min_window_height = 6,
      line_numbers = true,
      persist = false,
      headings = { enable = true, max_level = 6, icons = DEFAULT_ICONS },
      node_types = DEFAULT_NODE_TYPES,
      exclude_node_types = DEFAULT_EXCLUDES,
      style = "mimic",
      chips = { layout = "row", shape = "rounded" },
      position = { anchor = "top" },
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

    ---@param lines string[]|nil  default: DOC
    ---@param ft string|nil  default: "markdown"
    ---@return integer win, integer buf
    local function open_doc(lines, ft)
      vim.cmd("new")
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or DOC)
      vim.bo[buf].filetype = ft or "markdown"
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

    ---@param head string[]  the headings, then enough body to scroll them off
    ---@return string[]
    local function with_body(head)
      local lines = vim.list_extend({}, head)
      for i = 1, 12 do
        lines[#lines + 1] = "body " .. i
      end
      return lines
    end

    it("draws an indented ATX heading as a heading, the icon on its `#`", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      -- CommonMark: up to three spaces before the `#`s still make a heading.
      local win = open_doc(with_body({ "# One", "", "   ## Two", "" }))
      context.setup({ max_lines = 10 })
      context.enable()
      scroll_to(win, 8)
      context.refresh(win)

      local lines = overlay_lines(win)
      assert.equals(2, #lines)
      local marks = overlay_marks(win)
      assert.is_true(has(marks, 1, "hl_group", "UiContextH2"), "level-2 text group")
      assert.is_true(has(marks, 1, "line_hl_group", "UiContextH2Row"), "row band")

      local icon = on_row(marks, 1, "virt_text")[1]
      assert.is_truthy(icon, "an icon on the indented heading")
      assert.equals(2, vim.fn.strdisplaywidth(icon.virt_text[1][1]))
      -- The overlay starts on the first `#`, not on the indent before it: a
      -- shifted icon would cover blanks and leave a `#` showing.
      local marks_on_row = vim.api.nvim_buf_get_extmarks(
        select(2, context.float(win)),
        vim.api.nvim_get_namespaces().ui_context,
        { 1, 0 },
        { 1, -1 },
        { details = true }
      )
      local icon_col
      for _, m in ipairs(marks_on_row) do
        if m[4].virt_text then
          icon_col = m[3]
        end
      end
      assert.equals((lines[2]:find("#", 1, true)) - 1, icon_col)
    end)

    it("draws an empty ATX heading (`##` alone) as a heading", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_doc(with_body({ "# One", "", "##", "" }))
      context.setup({ max_lines = 10 })
      context.enable()
      scroll_to(win, 8)
      context.refresh(win)

      local lines = overlay_lines(win)
      assert.equals(2, #lines)
      assert.truthy(lines[2]:find("##", 1, true))
      local marks = overlay_marks(win)
      assert.is_true(has(marks, 1, "hl_group", "UiContextH2"))
      assert.equals(1, #on_row(marks, 1, "virt_text"))
    end)

    it("draws a heading in a buffer that parses as Markdown, e.g. `markdown.mdx`", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_doc(nil, "markdown.mdx")
      context.enable()
      scroll_to(win, 8)
      assert.is_true(context.refresh(win) >= 2)
      local lines = overlay_lines(win)
      local marks = overlay_marks(win)
      local last = #lines - 1
      assert.truthy(lines[#lines]:find("### Detail", 1, true))
      assert.is_true(has(marks, last, "hl_group", "UiContextH3"), "level-3 text group")
      assert.is_true(has(marks, last, "line_hl_group", "UiContextH3Row"), "row band")
      assert.equals("overlay", on_row(marks, last, "virt_text")[1].virt_text_pos)
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

  describe("how deep the context reaches", function()
    local has_markdown_parser = pcall(vim.treesitter.language.add, "markdown")

    -- Five nested headings, then enough body to scroll them all off.
    local DEEP = {
      "# One",
      "",
      "## Two",
      "",
      "### Three",
      "",
      "#### Four",
      "",
      "##### Five",
      "",
    }
    for i = 1, 12 do
      DEEP[#DEEP + 1] = "body " .. i
    end

    ---@param lines string[]
    ---@param ft string|nil  default: "markdown"
    ---@return integer win, integer buf
    local function open_md(lines, ft)
      vim.cmd("new")
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].filetype = ft or "markdown"
      vim.bo[buf].buftype = ""
      vim.api.nvim_win_set_height(win, 8)
      vim.wo[win].number = true
      return win, buf
    end

    ---@param lines string[]  overlay rows, gutter included
    ---@return string[] texts  the source text of each row, gutter stripped
    local function texts(lines)
      return vim.tbl_map(function(l)
        return (l:gsub("^%s*%d+ ", ""))
      end, lines)
    end

    it("pins the innermost three headings by default", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_md(DEEP)
      context.enable()
      scroll_to(win, 12)
      context.refresh(win)
      assert.same({ "### Three", "#### Four", "##### Five" }, texts(overlay_lines(win)))
    end)

    it("headings.max_level leaves deeper headings out of the chain", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_md(DEEP)
      context.setup({ headings = { max_level = 3 } })
      context.enable()
      scroll_to(win, 12)
      context.refresh(win)
      -- Inside an H5, but nothing deeper than H3 is pinned: H1..H3, not H3..H5.
      assert.same({ "# One", "## Two", "### Three" }, texts(overlay_lines(win)))
    end)

    it("applies the level cap before the row cap", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_md(DEEP)
      context.setup({ max_lines = 10, headings = { max_level = 4 } })
      context.enable()
      scroll_to(win, 12)
      context.refresh(win)
      assert.same({ "# One", "## Two", "### Three", "#### Four" }, texts(overlay_lines(win)))
    end)

    it("takes the max_lines of the buffer's own filetype", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_md(DEEP)
      context.setup({ max_lines = { default = 1, markdown = 5 } })
      context.enable()
      scroll_to(win, 12)
      assert.equals(5, context.refresh(win))
      context.setup({ max_lines = { default = 2 } })
      context.refresh(win)
      assert.equals(2, #overlay_lines(win), "a filetype without an entry takes `default`")
    end)

    it("reads a Setext heading's level from its underline", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local lines = { "Title", "=====", "", "Sub", "---", "" }
      for i = 1, 12 do
        lines[#lines + 1] = "body " .. i
      end
      local win = open_md(lines)
      context.setup({ headings = { max_level = 1 } })
      context.enable()
      scroll_to(win, 10)
      context.refresh(win)
      assert.same({ "Title" }, texts(overlay_lines(win)))
    end)

    it("leaves the real scopes alone: go_to_context still reaches a capped heading", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win, buf = open_md(DEEP)
      context.setup({ headings = { max_level = 1 } })
      scroll_to(win, 12)
      assert.equals(5, #context.contexts(buf, 11))
      assert.is_true(context.go_to_context())
      assert.equals(9, vim.api.nvim_win_get_cursor(win)[1])
    end)

    it("setup clamps max_level into 1..6 and ignores a value of the wrong type", function()
      context.setup({ headings = { max_level = 99 } })
      assert.equals(6, context.config().headings.max_level)
      context.setup({ headings = { max_level = 0 } })
      assert.equals(1, context.config().headings.max_level)
      context.setup({ headings = { max_level = "deep" } })
      assert.equals(1, context.config().headings.max_level, "kept the previous value")
      context.setup({ max_lines = -3 })
      assert.equals(3, context.config().max_lines, "a negative row cap is refused")
    end)

    it("set_max_lines edits one filetype or the default, describe_max_lines shows both", function()
      assert.equals("3", context.describe_max_lines())
      context.set_max_lines(6, "markdown")
      assert.equals("3 (markdown 6)", context.describe_max_lines())
      context.set_max_lines(4)
      assert.equals("4 (markdown 6)", context.describe_max_lines())
      assert.equals(6, context.config().max_lines.markdown)
    end)

    it("set_max_lines refuses a bad value instead of losing the entry it would replace", function()
      context.set_max_lines(6, "markdown")
      assert.is_false(context.set_max_lines(-1, "markdown"))
      assert.is_false(context.set_max_lines("many"))
      assert.is_false(context.set_max_lines(nil, "markdown"))
      assert.equals("3 (markdown 6)", context.describe_max_lines())
      assert.is_true(context.set_max_lines(0, "markdown"))
      assert.equals(0, context.config().max_lines.markdown, "0 is a valid cap: unlimited")
    end)

    it("reads an indented ATX heading's level, so the cap still drops it", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      -- CommonMark allows up to three spaces before the `#`s.
      local lines = { "# One", "", "## Two", "", " ### Three", "", "#### Four", "" }
      for i = 1, 12 do
        lines[#lines + 1] = "body " .. i
      end
      local win = open_md(lines)
      context.setup({ max_lines = 10, headings = { max_level = 2 } })
      context.enable()
      scroll_to(win, 10)
      context.refresh(win)
      assert.same({ "# One", "## Two" }, texts(overlay_lines(win)))
    end)

    describe("Markdown variants", function()
      -- `markdown.mdx`, `markdown.pandoc` and `markdown.gfm` resolve to the
      -- `markdown` parser but are not the filetype `markdown`; a filetype the
      -- host registered for that parser is the same case.
      it("applies the level cap to a compound Markdown filetype", function()
        if not has_markdown_parser then
          pending("no Markdown parser available")
          return
        end
        local win = open_md(DEEP, "markdown.mdx")
        context.setup({ max_lines = 10, headings = { max_level = 3 } })
        context.enable()
        scroll_to(win, 12)
        context.refresh(win)
        assert.same({ "# One", "## Two", "### Three" }, texts(overlay_lines(win)))
      end)

      it("takes max_lines from the parser language's entry when the filetype has none", function()
        if not has_markdown_parser then
          pending("no Markdown parser available")
          return
        end
        local win = open_md(DEEP, "markdown.mdx")
        context.setup({ max_lines = { default = 1, markdown = 6 } })
        context.enable()
        scroll_to(win, 12)
        context.refresh(win)
        assert.equals(5, #overlay_lines(win), "the `markdown` entry, not `default`")
      end)

      it("lets an entry for the exact filetype win over the language's", function()
        if not has_markdown_parser then
          pending("no Markdown parser available")
          return
        end
        local win = open_md(DEEP, "markdown.mdx")
        context.setup({ max_lines = { default = 1, markdown = 6, ["markdown.mdx"] = 2 } })
        context.enable()
        scroll_to(win, 12)
        context.refresh(win)
        assert.equals(2, #overlay_lines(win))
      end)

      it("treats a filetype registered for the markdown parser as Markdown", function()
        if not has_markdown_parser then
          pending("no Markdown parser available")
          return
        end
        -- Process-wide and there is no way to take it back; harmless here, since no
        -- other test uses `rmd` and every spec file runs in its own Neovim.
        vim.treesitter.language.register("markdown", "rmd")
        local win = open_md(DEEP, "rmd")
        context.setup({ max_lines = { default = 1, markdown = 6 }, headings = { max_level = 2 } })
        context.enable()
        scroll_to(win, 12)
        context.refresh(win)
        assert.same({ "# One", "## Two" }, texts(overlay_lines(win)))
      end)

      it("leaves a filetype with its own parser alone", function()
        if not has_lua_parser then
          pending("no Lua parser available")
          return
        end
        -- Not Markdown, so the cap does not touch it and it takes `default`.
        local win = open_source()
        context.setup({ max_lines = { default = 1, markdown = 6 }, headings = { max_level = 1 } })
        context.enable()
        scroll_to(win, 7)
        context.refresh(win)
        assert.equals(1, #overlay_lines(win))
      end)
    end)

    it("redraws an open overlay at once when the depth changes", function()
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      local win = open_md(DEEP)
      context.enable()
      scroll_to(win, 12)
      context.refresh(win)
      assert.same({ "### Three", "#### Four", "##### Five" }, texts(overlay_lines(win)))
      -- No refresh() here: the cached overlay must not outlive the setting.
      context.set_max_level(3)
      assert.same({ "# One", "## Two", "### Three" }, texts(overlay_lines(win)))
      context.set_max_lines(1, "markdown")
      assert.same({ "### Three" }, texts(overlay_lines(win)))
    end)

    describe("saved settings (persist)", function()
      local file

      ---@param tbl table
      local function write_saved(tbl)
        vim.fn.mkdir(vim.fs.dirname(file), "p")
        vim.fn.writefile({ vim.json.encode(tbl) }, file)
      end

      ---@return table|nil
      local function read_saved()
        if vim.fn.filereadable(file) ~= 1 then
          return nil
        end
        return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
      end

      -- What `vim.notify` got, so a warning can be asserted and not printed.
      local notified, real_notify

      before_each(function()
        file = vim.fn.tempname() .. "/ui.nvim/sticky.json"
        notified, real_notify = {}, vim.notify
        vim.notify = function(msg, level)
          notified[#notified + 1] = { msg = tostring(msg), level = level }
        end
      end)

      after_each(function()
        vim.notify = real_notify
        vim.fn.delete(vim.fs.dirname(file), "rf")
      end)

      it("writes nothing while persist is off", function()
        context.setup({ state_file = file })
        context.set_max_level(3)
        context.set_max_lines(2, "markdown")
        assert.is_nil(read_saved())
        assert.equals("depth 3, lines markdown 2", context.describe_overrides())
      end)

      it("writes what depth and lines set, and only that", function()
        context.setup({ persist = true, state_file = file })
        context.set_max_level(3)
        assert.same({ max_level = 3 }, read_saved())
        context.set_max_lines(2, "markdown")
        context.set_max_lines(4)
        assert.same({ max_level = 3, lines = { markdown = 2, default = 4 } }, read_saved())
        context.set_max_lines(-1, "markdown")
        assert.same(
          { max_level = 3, lines = { markdown = 2, default = 4 } },
          read_saved(),
          "a refused value is not saved"
        )
      end)

      it("applies the saved values on top of the configuration at setup", function()
        write_saved({ max_level = 3, lines = { markdown = 2 } })
        context.setup({
          max_lines = { default = 3, markdown = 6 },
          headings = { max_level = 5 },
          persist = true,
          state_file = file,
        })
        assert.equals(3, context.config().headings.max_level)
        assert.equals("3 (markdown 2)", context.describe_max_lines())
        assert.is_true(context.is_persisting())
      end)

      it("reset returns to the configured values and deletes the file", function()
        write_saved({ max_level = 3, lines = { markdown = 2 } })
        context.setup({
          max_lines = { default = 3, markdown = 6 },
          headings = { max_level = 5 },
          persist = true,
          state_file = file,
        })
        assert.is_true(context.reset())
        assert.equals(5, context.config().headings.max_level)
        assert.equals("3 (markdown 6)", context.describe_max_lines())
        assert.is_nil(context.describe_overrides())
        assert.is_nil(read_saved())
        assert.is_false(context.reset(), "nothing left to reset")
      end)

      it("reset without persist restores the configuration and leaves the file alone", function()
        context.setup({ max_lines = 3, headings = { max_level = 5 }, state_file = file })
        write_saved({ max_level = 2 })
        context.set_max_level(1)
        context.set_max_lines(9)
        assert.is_true(context.reset())
        assert.equals(5, context.config().headings.max_level)
        assert.equals(3, context.config().max_lines)
        assert.same({ max_level = 2 }, read_saved())
      end)

      it("a config that restates a value replaces the command's earlier override", function()
        context.set_max_lines(2, "markdown")
        context.set_max_level(2)
        context.setup({ max_lines = 3, headings = { max_level = 6 } })
        assert.equals("3", context.describe_max_lines())
        assert.equals(6, context.config().headings.max_level)
        assert.is_nil(context.describe_overrides())
      end)

      it("ignores a missing, malformed or invalid file", function()
        assert.has_no.errors(function()
          context.setup({ persist = true, state_file = file })
        end)
        assert.equals(6, context.config().headings.max_level, "no file: nothing applied")

        vim.fn.mkdir(vim.fs.dirname(file), "p")
        vim.fn.writefile({ "{ not json" }, file)
        assert.has_no.errors(function()
          context.setup({ persist = true, state_file = file })
        end)
        assert.equals(6, context.config().headings.max_level)

        write_saved({ max_level = 9, lines = { markdown = -1, lua = "x" } })
        context.setup({ persist = true, state_file = file })
        assert.equals(6, context.config().headings.max_level, "level out of 1..6 is dropped")
        assert.equals("3", context.describe_max_lines(), "bad line caps are dropped")

        write_saved({ max_level = 2, lines = { markdown = -1, lua = 4 } })
        context.setup({ persist = true, state_file = file })
        assert.equals(
          2,
          context.config().headings.max_level,
          "a valid entry survives its neighbours"
        )
        assert.equals("3 (lua 4)", context.describe_max_lines())
      end)

      it("creates the missing state directory", function()
        context.setup({ persist = true, state_file = file })
        assert.equals(0, vim.fn.isdirectory(vim.fs.dirname(file)))
        context.set_max_level(4)
        assert.same({ max_level = 4 }, read_saved())
      end)

      it("survives a restart: a second setup reads what the first one saved", function()
        context.setup({ persist = true, state_file = file })
        context.set_max_level(2)
        context.set_max_lines(1, "markdown")
        -- What a fresh session does: the configuration again, then the saved values.
        context.setup({
          max_lines = { default = 3, markdown = 6 },
          headings = { max_level = 6 },
          persist = true,
          state_file = file,
        })
        assert.equals(2, context.config().headings.max_level)
        assert.equals("3 (markdown 1)", context.describe_max_lines())
      end)

      describe("hardening", function()
        it("takes an infinite row cap as unlimited and keeps saving afterwards", function()
          -- `inf` used to be stored as it was: `vim.json.encode` then refused it on
          -- every later save, so not even a valid depth reached the file again.
          context.setup({ persist = true, state_file = file })
          assert.is_true(context.set_max_lines(math.huge, "markdown"))
          assert.equals(0, context.config().max_lines.markdown)
          context.set_max_level(3)
          assert.same({ max_level = 3, lines = { markdown = 0 } }, read_saved())
          assert.is_true(context.is_saved())
          assert.is_false(context.set_max_lines(0 / 0), "nan is refused like any non-number")
        end)

        it("drops non-finite numbers from the file", function()
          vim.fn.mkdir(vim.fs.dirname(file), "p")
          vim.fn.writefile({ '{"max_level":1e999,"lines":{"markdown":1e999,"lua":4}}' }, file)
          context.setup({ persist = true, state_file = file })
          assert.equals(6, context.config().headings.max_level)
          assert.equals("3 (lua 4)", context.describe_max_lines())
        end)

        it("resolves ~ and $VAR and anchors a relative path", function()
          local resolve = require("ui.context.state").resolve
          assert.equals(
            vim.fs.normalize(vim.uv.os_homedir() .. "/x/sticky.json"),
            resolve("~/x/sticky.json")
          )
          vim.env.UI_NVIM_SPEC_STATE = vim.fs.dirname(file)
          local from_env = resolve("$UI_NVIM_SPEC_STATE/sticky.json")
          vim.env.UI_NVIM_SPEC_STATE = nil
          assert.equals(vim.fs.normalize(file), from_env)
          assert.equals(
            vim.fs.normalize(vim.fn.getcwd() .. "/rel/sticky.json"),
            resolve("rel/sticky.json")
          )
        end)

        it("writes to the expanded path, not to a directory named after the variable", function()
          vim.env.UI_NVIM_SPEC_STATE = vim.fs.dirname(file)
          context.setup({ persist = true, state_file = "$UI_NVIM_SPEC_STATE/sticky.json" })
          vim.env.UI_NVIM_SPEC_STATE = nil
          context.set_max_level(2)
          assert.same({ max_level = 2 }, read_saved())
          assert.equals(vim.fs.normalize(file), context.state_path())
          assert.equals(0, vim.fn.isdirectory(vim.fn.getcwd() .. "/$UI_NVIM_SPEC_STATE"))
        end)

        it("leaves a file that is not a state file alone, and says so", function()
          local theirs = { "-- somebody's init.lua", "vim.g.x = 1" }
          vim.fn.mkdir(vim.fs.dirname(file), "p")
          vim.fn.writefile(theirs, file)
          context.setup({ persist = true, state_file = file })
          context.set_max_level(3)
          assert.same(theirs, vim.fn.readfile(file), "not overwritten")
          assert.is_false(context.is_saved())
          assert.equals(3, context.config().headings.max_level, "the session still gets the value")
          assert.equals(vim.log.levels.WARN, notified[1].level)
          assert.is_truthy(notified[1].msg:find("not a ui.nvim sticky state file", 1, true))
          context.reset()
          assert.same(theirs, vim.fn.readfile(file), "not deleted by reset either")
        end)

        it("does not touch a directory or a JSON file with other keys", function()
          vim.fn.mkdir(file, "p")
          context.setup({ persist = true, state_file = file })
          assert.has_no.errors(function()
            context.set_max_level(3)
          end)
          assert.is_false(context.is_saved())
          assert.equals(1, vim.fn.isdirectory(file))
          vim.fn.delete(file, "d")

          local other = { name = "package", version = "1.0" }
          write_saved(other)
          context.set_max_level(2)
          assert.same(other, read_saved())
          assert.is_false(context.is_saved())
        end)

        it("replaces whatever sits at its own default location, corrupt or not", function()
          -- The default location is the plugin's own directory: a file there is
          -- ours, so a hand-broken one is replaced and reset can still clear it.
          local state = require("ui.context.state")
          local real_default = state.default_path
          local path = vim.fs.normalize(file)
          ---@diagnostic disable-next-line: duplicate-set-field
          state.default_path = function()
            return path
          end
          local ok, err = pcall(function()
            vim.fn.mkdir(vim.fs.dirname(file), "p")
            vim.fn.writefile({ "{ half a json" }, file)
            assert.is_true(state.write(path, { max_level = 2 }))
            assert.same({ max_level = 2 }, read_saved())
            vim.fn.writefile({ "-- anything at all" }, file)
            assert.is_true(state.remove(path))
            assert.equals(0, vim.fn.filereadable(file))
          end)
          state.default_path = real_default
          assert.is_true(ok, err)
        end)

        it("does replace an empty file and a state file of an earlier version", function()
          vim.fn.mkdir(vim.fs.dirname(file), "p")
          vim.fn.writefile({}, file)
          context.setup({ persist = true, state_file = file })
          context.set_max_level(3)
          assert.same({ max_level = 3 }, read_saved())
          assert.is_true(context.is_saved())
          write_saved({ max_level = 2, lines = { markdown = 1 } })
          context.set_max_level(4)
          assert.same({ max_level = 4 }, read_saved())
          assert.is_true(context.is_saved())
          assert.equals(0, #notified, "nothing to warn about")
        end)

        it("ignores a file over the size limit", function()
          vim.fn.mkdir(vim.fs.dirname(file), "p")
          local padding = (" "):rep(20 * 1024)
          vim.fn.writefile({ '{"max_level":2,' .. padding .. '"lines":{"lua":4}}' }, file)
          context.setup({ persist = true, state_file = file })
          assert.equals(6, context.config().headings.max_level)
          assert.equals("3", context.describe_max_lines())
        end)

        it("ignores the row caps of a file with more filetypes than any real one", function()
          local lines = {}
          for i = 1, 65 do
            lines["ft" .. i] = 2
          end
          write_saved({ max_level = 2, lines = lines })
          context.setup({ persist = true, state_file = file })
          assert.equals(2, context.config().headings.max_level, "the rest of the file counts")
          assert.equals("3", context.describe_max_lines())
        end)

        it("redraws once per change, however many values it touches", function()
          open_source()
          context.enable()
          write_saved({ max_level = 2, lines = { default = 2, markdown = 4, lua = 5, python = 6 } })
          local calls = 0
          local refresh_all = context.refresh_all
          ---@diagnostic disable-next-line: duplicate-set-field
          context.refresh_all = function(...)
            calls = calls + 1
            return refresh_all(...)
          end
          local ok, err = pcall(function()
            context.setup({ persist = true, state_file = file })
            assert.equals("2 (lua 5, markdown 4, python 6)", context.describe_max_lines())
            assert.equals(1, calls, "setup applying five saved values")
            calls = 0
            context.set_max_lines(1, "markdown")
            assert.equals(1, calls, "set_max_lines")
            calls = 0
            context.set_max_level(3)
            assert.equals(1, calls, "set_max_level")
            calls = 0
            context.reset()
            assert.equals(1, calls, "reset")
          end)
          context.refresh_all = refresh_all
          assert.is_true(ok, err)
        end)
      end)
    end)

    describe(":UI sticky", function()
      before_each(function()
        require("ui.bindings.usrcmds").setup()
      end)

      it("toggles, and `context` is the same command", function()
        vim.cmd("UI sticky")
        assert.is_true(context.is_enabled())
        vim.cmd("UI sticky off")
        assert.is_false(context.is_enabled())
        vim.cmd("UI context on")
        assert.is_true(context.is_enabled())
        vim.cmd("UI context toggle")
        assert.is_false(context.is_enabled())
      end)

      it("does not toggle on a misspelt action", function()
        vim.cmd("UI sticky dept 3")
        assert.is_false(context.is_enabled())
      end)

      it("depth sets the heading level, refuses out-of-range values, `all` is 6", function()
        vim.cmd("UI sticky depth 4")
        assert.equals(4, context.config().headings.max_level)
        vim.cmd("UI sticky depth 7")
        vim.cmd("UI sticky depth two")
        vim.cmd("UI sticky depth 2.5")
        assert.equals(4, context.config().headings.max_level)
        vim.cmd("UI sticky depth all")
        assert.equals(6, context.config().headings.max_level)
      end)

      it("lines sets the default or one filetype's row cap", function()
        vim.cmd("UI sticky lines 5")
        assert.equals(5, context.config().max_lines)
        vim.cmd("UI sticky lines markdown 2")
        assert.equals("5 (markdown 2)", context.describe_max_lines())
        vim.cmd("UI sticky lines lots")
        vim.cmd("UI sticky lines -1")
        assert.equals("5 (markdown 2)", context.describe_max_lines(), "bad numbers change nothing")
        vim.cmd("UI sticky lines markdown 0")
        assert.equals(0, context.config().max_lines.markdown, "0 means unlimited")
      end)

      it("reset drops what depth and lines changed", function()
        vim.cmd("UI sticky depth 2")
        vim.cmd("UI sticky lines markdown 1")
        vim.cmd("UI sticky reset")
        assert.equals(6, context.config().headings.max_level)
        assert.equals("3", context.describe_max_lines())
        assert.has_no.errors(function()
          vim.cmd("UI sticky reset")
        end)
      end)

      it("takes `inf` as an unlimited row cap", function()
        vim.cmd("UI sticky lines markdown inf")
        assert.equals(0, context.config().max_lines.markdown)
      end)

      describe("what the confirmation says about keeping the value", function()
        local file, seen, real_notify

        ---@return string
        local function said()
          return table.concat(seen, "\n")
        end

        before_each(function()
          file = vim.fn.tempname() .. "/ui.nvim/sticky.json"
          seen, real_notify = {}, vim.notify
          vim.notify = function(msg)
            seen[#seen + 1] = tostring(msg)
          end
        end)

        after_each(function()
          vim.notify = real_notify
          vim.fn.delete(vim.fs.dirname(file), "rf")
        end)

        it("says this session only without persist", function()
          vim.cmd("UI sticky depth 3")
          assert.is_truthy(said():find("this session only", 1, true))
          assert.is_nil(said():find("saved for the next start", 1, true))
        end)

        it("says saved once the file has been written", function()
          context.setup({ persist = true, state_file = file })
          vim.cmd("UI sticky depth 3")
          assert.is_truthy(said():find("saved for the next start", 1, true))
          vim.cmd("UI sticky status")
          assert.is_truthy(said():find("depth 3, saved", 1, true))
        end)

        it("does not claim a save that failed", function()
          vim.fn.mkdir(vim.fs.dirname(file), "p")
          vim.fn.writefile({ "not a state file" }, file)
          context.setup({ persist = true, state_file = file })
          vim.cmd("UI sticky depth 3")
          assert.is_truthy(said():find("saving failed", 1, true))
          assert.is_nil(said():find("saved for the next start", 1, true))
          vim.cmd("UI sticky status")
          assert.is_truthy(said():find("this session only, saving failed", 1, true))
        end)
      end)

      it("completes the actions", function()
        local got = vim.fn.getcompletion("UI sticky d", "cmdline")
        assert.same({ "depth" }, got)
        assert.is_truthy(vim.tbl_contains(vim.fn.getcompletion("UI sticky r", "cmdline"), "reset"))
        assert.is_truthy(vim.tbl_contains(vim.fn.getcompletion("UI context ", "cmdline"), "lines"))
      end)

      it("completes the level after `depth` and the filetype after `lines`", function()
        assert.same(
          { "1", "2", "3", "4", "5", "6", "all" },
          vim.fn.getcompletion("UI sticky depth ", "cmdline")
        )
        assert.same({ "all" }, vim.fn.getcompletion("UI sticky depth a", "cmdline"))
        assert.is_truthy(
          vim.tbl_contains(vim.fn.getcompletion("UI context lines mark", "cmdline"), "markdown")
        )
        assert.same({}, vim.fn.getcompletion("UI sticky on ", "cmdline"))
      end)
    end)
  end)

  describe("which node types are scopes", function()
    -- Node names as the grammars spell them (checked against real parsers for
    -- Rust and Python, against nvim-treesitter's queries for the others), so
    -- this part needs no parser and runs everywhere.
    local PINNED = {
      lua = {
        "function_declaration",
        "if_statement",
        "elseif_statement",
        "for_statement",
        "while_statement",
        "repeat_statement",
        "do_statement",
      },
      c = {
        "function_definition",
        "struct_specifier",
        "union_specifier",
        "switch_statement",
        "case_statement",
      },
      cpp = { "class_specifier", "namespace_definition", "linkage_specification" },
      markdown = { "section" },
      rust = {
        "function_item",
        "impl_item",
        "trait_item",
        "struct_item",
        "enum_item",
        "mod_item",
        "if_expression",
        "for_expression",
        "while_expression",
        "loop_expression",
        "match_expression",
        "match_arm",
        "else_clause",
      },
      python = {
        "function_definition",
        "class_definition",
        "if_statement",
        "elif_clause",
        "else_clause",
        "for_statement",
        "while_statement",
        "with_statement",
        "try_statement",
        "except_clause",
        "finally_clause",
        "match_statement",
        "case_clause",
      },
      go = {
        "function_declaration",
        "method_declaration",
        "func_literal",
        "if_statement",
        "for_statement",
        "expression_switch_statement",
        "expression_case",
        "type_case",
        "default_case",
        "type_declaration",
      },
      java = {
        "class_declaration",
        "method_declaration",
        "enhanced_for_statement",
        "switch_expression",
        "try_statement",
        "catch_clause",
        "finally_clause",
        "record_declaration",
      },
      javascript = { "function_expression", "arrow_function", "method_definition", "switch_case" },
      typescript = { "internal_module", "interface_declaration", "enum_declaration" },
      kotlin = { "if_expression", "when_expression", "do_while_statement", "function_declaration" },
      bash = { "function_definition", "elif_clause", "c_style_for_statement", "case_item" },
      yaml = { "block_mapping_pair" },
    }
    -- What must stay out: an expression or a call is not a place you are in.
    local NOT_PINNED = {
      lua = { "table_constructor" },
      cpp = { "destructor_name", "lambda_expression" },
      rust = { "call_expression", "closure_expression", "struct_expression", "try_expression" },
      go = { "call_expression", "composite_literal" },
      java = { "method_invocation", "lambda_expression" },
      javascript = { "call_expression" },
      c_sharp = { "invocation_expression", "lambda_expression" },
      kotlin = { "call_expression", "constructor_invocation" },
      json = { "object", "array", "pair" },
      markdown = { "atx_heading", "fenced_code_block", "list_item" },
    }

    for lang, types in pairs(PINNED) do
      it(lang .. ": pins " .. table.concat(types, ", "), function()
        for _, typ in ipairs(types) do
          assert.is_true(context.is_scope_type(typ), typ .. " should be a scope")
        end
      end)
    end

    for lang, types in pairs(NOT_PINNED) do
      it(lang .. ": leaves " .. table.concat(types, ", ") .. " out", function()
        for _, typ in ipairs(types) do
          assert.is_false(context.is_scope_type(typ), typ .. " should not be a scope")
        end
      end)
    end

    it("an exactly named node_types entry is not vetoed by the excludes", function()
      -- `_expression$` excludes this, and would keep `foo_expression` out...
      context.setup({ node_types = { "foo_expression" }, exclude_node_types = { "_expression$" } })
      assert.is_false(context.is_scope_type("foo_expression"))
      -- ...unless the entry spells the whole name.
      context.setup({ node_types = { "^foo_expression$" } })
      assert.is_true(context.is_scope_type("foo_expression"))
      -- The exception is that one name, not its family.
      assert.is_false(context.is_scope_type("bar_expression"))
      assert.is_false(context.is_scope_type("foo_expression_list"))
    end)

    it("a plain `^prefix` or `suffix$` entry is a family, so the excludes still apply", function()
      context.setup({ node_types = { "^if", "if$" }, exclude_node_types = { "_expression$" } })
      assert.is_true(context.is_scope_type("if_statement"))
      assert.is_false(context.is_scope_type("if_expression"), "`^if` is not an exact name")
      assert.is_true(context.is_scope_type("elif"), "`if$` is not an exact name either")
    end)

    it("a `$` behind an odd run of `%` is a literal dollar, not the anchor", function()
      context.setup({ node_types = { "^foo%$" }, exclude_node_types = { "foo" } })
      assert.is_false(context.is_scope_type("foo$"), "`^foo%$` is a family: the exclude applies")
      context.setup({ node_types = { "^foo%%$" } })
      assert.is_true(context.is_scope_type("foo%"), "`%%` is a literal percent, so `$` anchors")
    end)

    it("answers false for anything that is not a type name", function()
      -- Wrong types on purpose: the public function must not raise on them.
      ---@diagnostic disable: param-type-mismatch
      assert.is_false(context.is_scope_type(nil))
      assert.is_false(context.is_scope_type(5))
      assert.is_false(context.is_scope_type({}))
      ---@diagnostic enable: param-type-mismatch
    end)

    describe("with a broken node_types list", function()
      local real_notify_once = vim.notify_once
      local warned

      before_each(function()
        warned = {}
        vim.notify_once = function(msg)
          warned[#warned + 1] = msg
        end
      end)

      after_each(function()
        vim.notify_once = real_notify_once
      end)

      it("ignores a malformed pattern instead of raising, and says so", function()
        context.setup({ node_types = { "[", "^good$" } })
        local ok, hit = pcall(context.is_scope_type, "anything")
        assert.is_true(ok, "a bad pattern must not raise on every refresh")
        assert.is_false(hit)
        assert.is_true(context.is_scope_type("good"), "the valid entries still work")
        assert.is_truthy(warned[1] and warned[1]:find("[", 1, true), "the pattern is named")
      end)

      it("ignores an entry that is not a string", function()
        ---@diagnostic disable-next-line: assign-type-mismatch
        context.setup({ node_types = { {}, false, "^good$" } })
        local ok, hit = pcall(context.is_scope_type, "good")
        assert.is_true(ok)
        assert.is_true(hit)
      end)
    end)

    it("forgets its answers when setup changes a list", function()
      assert.is_true(context.is_scope_type("function_declaration"))
      assert.is_false(context.is_scope_type("call_expression"))
      context.setup({ node_types = { "^call_expression$" }, exclude_node_types = {} })
      assert.is_false(context.is_scope_type("function_declaration"), "no stale `true`")
      assert.is_true(context.is_scope_type("call_expression"), "no stale `false`")
      context.setup({ node_types = DEFAULT_NODE_TYPES, exclude_node_types = DEFAULT_EXCLUDES })
      assert.is_true(context.is_scope_type("function_declaration"))
    end)

    ---@param lang string
    ---@return boolean
    local function has_real_parser(lang)
      return #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) > 0
        and pcall(vim.treesitter.language.add, lang)
    end

    ---@param lang string
    ---@param lines string[]
    ---@return integer buf
    local function scratch(lang, lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].filetype = lang
      return buf
    end

    ---@param buf integer
    ---@param top integer  0-based top row
    ---@return integer[] rows
    local function context_rows(buf, top)
      return vim.tbl_map(function(e)
        return e.row
      end, context.contexts(buf, top))
    end

    it("rust: a real buffer pins mod/if/for/while/loop/match, not the `?` or a call", function()
      if not has_real_parser("rust") then
        pending("no Rust parser available")
        return
      end
      local buf = scratch("rust", {
        "mod outer {",
        "    pub fn run(items: Vec<i32>) -> i32 {",
        "        let mut total = 0;",
        "        if items.len() > 2 {",
        "            for x in items.iter() {",
        "                while total < 100 {",
        "                    loop {",
        "                        match x {",
        "                            1 => {",
        "                                total += helper(x)?;",
        "                            }",
        "                            _ => break,",
        "                        }",
        "                    }",
        "                }",
        "            }",
        "        }",
        "        total",
        "    }",
        "}",
      })
      -- mod, fn, if, for, while, loop, match, and the arm holding the top line.
      assert.same({ 0, 1, 3, 4, 5, 6, 7, 8 }, context_rows(buf, 9))
    end)

    it("python: a real buffer pins the elif and except branch the top line is in", function()
      if not has_real_parser("python") then
        pending("no Python parser available")
        return
      end
      local buf = scratch("python", {
        "class Outer:",
        "    def run(self, items):",
        "        if items:",
        "            pass",
        "        elif self:",
        "            pass",
        "            pass",
        "        try:",
        "            pass",
        "        except ValueError:",
        "            pass",
        "            pass",
        "        finally:",
        "            pass",
        "            pass",
      })
      assert.same({ 0, 1, 2, 4 }, context_rows(buf, 6), "class, def, the if, and the elif")
      assert.same({ 0, 1, 7, 9 }, context_rows(buf, 11), "class, def, the try, and the except")
      assert.same({ 0, 1, 7, 12 }, context_rows(buf, 14), "class, def, the try, and the finally")
    end)

    it("yaml: a real buffer pins the parent keys, not the list item or the scalar", function()
      if not has_real_parser("yaml") then
        pending("no YAML parser available")
        return
      end
      local buf = scratch("yaml", {
        "jobs:",
        "  build:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - name: Checkout",
        "        uses: actions/checkout@v4",
        "        with:",
        "          fetch-depth: 0",
        "      - name: Test",
        "        run: |",
        "          echo one",
        "          echo two",
      })
      assert.same({ 0, 1, 3, 6 }, context_rows(buf, 7), "jobs, build, steps, with")
      assert.same({ 0, 1, 3, 9 }, context_rows(buf, 10), "jobs, build, steps, run")
      assert.same({}, context_rows(buf, 0), "nothing above the first key")
    end)

    it("c: a real buffer pins function, if, for, switch/case, else and while", function()
      if not has_real_parser("c") then
        pending("no C parser available")
        return
      end
      local buf = scratch("c", {
        "struct point {", -- 0
        "    int x;",
        "    int y;",
        "};",
        "",
        "static int run(int n)", -- 5
        "{",
        "    int total = 0;",
        "    if (n > 2) {", -- 8
        "        for (int i = 0; i < n; i++) {",
        "            switch (i) {",
        "            case 1:", -- 11
        "                total += helper(i);",
        "                total += 1;",
        "                break;",
        "            default:", -- 15
        "                total -= 1;",
        "            }",
        "        }",
        "    } else {", -- 19
        "        while (total < 10) {", -- 20
        "            total++;",
        "            total++;",
        "        }",
        "    }",
        "    return total;",
        "}",
      })
      assert.same({}, context_rows(buf, 0))
      assert.same({ 0 }, context_rows(buf, 2), "the struct")
      assert.same({ 5, 8, 9, 10, 11 }, context_rows(buf, 12), "fn, if, for, switch, case 1")
      assert.same({ 5, 8, 9, 10, 15 }, context_rows(buf, 16), "the default case, not case 1")
      assert.same({ 5, 8, 19 }, context_rows(buf, 20), "the else, not the if's own body")
      assert.same({ 5, 8, 19, 20 }, context_rows(buf, 22), "else, while")
      assert.same({ 5 }, context_rows(buf, 26), "back to just the function")
    end)

    it("skips a scope whose first line is only an opening bracket (Allman style)", function()
      if not has_real_parser("c") then
        pending("no C parser available")
        return
      end
      -- `compound_statement` is the `{ ... }` body: it starts at its brace. Made a
      -- scope on purpose, it is the shape of every `*_body` node in Java, C#,
      -- Kotlin and TypeScript.
      context.setup({
        node_types = { "^compound_statement$", "^function_definition$" },
        exclude_node_types = {},
      })
      local allman = scratch("c", {
        "int run(int n)", -- 0
        "{", -- 1: the function body, brace alone
        "    if (n > 2)",
        "    {", -- 3: the if body, brace alone
        "        n++;",
        "        n++;",
        "    }",
        "    return n;",
        "}",
      })
      assert.same({ 0 }, context_rows(allman, 5), "only the function; no row for either lone `{`")

      local knr = scratch("c", {
        "int run(int n) {", -- 0: function and its body share the row
        "    if (n > 2) {", -- 1: the if body starts on the `if` row
        "        n++;",
        "        n++;",
        "    }",
        "}",
      })
      assert.same({ 0, 1 }, context_rows(knr, 3), "a brace after the header is part of a real line")
    end)

    it("json and toml: a real buffer pins nothing, however deep the nesting", function()
      if not has_real_parser("json") and not has_real_parser("toml") then
        pending("no JSON or TOML parser available")
        return
      end
      if has_real_parser("json") then
        local json = scratch("json", {
          "{",
          '  "a": {',
          '    "b": {',
          '      "c": [',
          "        1,",
          "        2",
          "      ]",
          "    }",
          "  }",
          "}",
        })
        for top = 0, 9 do
          assert.same({}, context_rows(json, top), "json, top row " .. top)
        end
      end
      if has_real_parser("toml") then
        -- `table` / `table_array_element` are the `[a.b]` headers; not pinned on purpose.
        local toml = scratch("toml", {
          "[package]",
          'name = "demo"',
          "",
          "[dependencies.serde]",
          'version = "1"',
          'features = ["derive"]',
          "",
          "[[bin]]",
          'name = "a"',
          'path = "src/a.rs"',
        })
        for top = 0, 9 do
          assert.same({}, context_rows(toml, top), "toml, top row " .. top)
        end
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

  describe("position", function()
    it("defaults to a full-width box pinned at the window's top-left", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(0, wcfg.row)
      assert.equals(0, wcfg.col)
      assert.equals(vim.api.nvim_win_get_width(win), wcfg.width)
    end)

    it("anchor = 'bottom' keeps full width but pins the box to the window's bottom", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ position = { anchor = "bottom" } })
      context.enable()
      -- Cursor kept off the window's bottom rows: a bottom-anchored overlay
      -- covering it would close it again, same as a top-anchored one would
      -- for a cursor on the window's first rows.
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = 7, lnum = 8, col = 0 })
      end)
      local shown = context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(vim.api.nvim_win_get_height(win) - shown, wcfg.row)
      assert.equals(0, wcfg.col)
      assert.equals(vim.api.nvim_win_get_width(win), wcfg.width)
    end)

    it("a corner anchor shrinks the box to its content and anchors it there", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ position = { anchor = "top-right" } })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(0, wcfg.row)
      assert.is_true(
        wcfg.width < vim.api.nvim_win_get_width(win),
        "box should shrink to its content"
      )
      assert.equals(vim.api.nvim_win_get_width(win) - wcfg.width, wcfg.col)
    end)

    it("position.row/col override the anchor outright", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ position = { anchor = "top-right", row = 2, col = 3 } })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(2, wcfg.row)
      assert.equals(3, wcfg.col)
    end)

    it("a plain anchor-only setup() drops a row/col an earlier call set", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ position = { anchor = "top-right", row = 2, col = 3 } })
      context.setup({ position = { anchor = "top-right" } })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(0, wcfg.row)
      assert.equals(vim.api.nvim_win_get_width(win) - wcfg.width, wcfg.col)
    end)

    it("an explicit col shrinks a full-width anchor's width to fit inside the window", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      -- anchor = "top" is full-width by default; col = 5 must not just shift
      -- that full width right, which would spill 5 columns past the
      -- window's own right edge.
      context.setup({ position = { anchor = "top", col = 5 } })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(5, wcfg.col)
      assert.equals(vim.api.nvim_win_get_width(win) - 5, wcfg.width)
      assert.is_true(wcfg.col + wcfg.width <= vim.api.nvim_win_get_width(win))
    end)

    it(
      "a compact anchor only hides for a cursor inside its own box, not elsewhere on the row",
      function()
        if not has_lua_parser then
          pending("no Lua parser available")
          return
        end
        -- SOURCE's own lines are all short; row 3 needs to be long enough to
        -- put the cursor at a screen column inside a right-anchored box.
        vim.cmd("new")
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_get_current_buf()
        -- The blocks are closed (end/end/end): an unterminated for/if/function
        -- parses as one ERROR node from row 0, which matches no scope type at
        -- all -- contexts() would then find nothing to pin, for a reason
        -- unrelated to what this test checks.
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "local function outer(a, b)",
          "  if a > b then",
          "    for i = 1, 10 do",
          '      local pad = "' .. string.rep("x", 80) .. '"',
          "      print(pad)",
          "    end",
          "  end",
          "  return a",
          "end",
        })
        vim.bo[buf].filetype = "lua"
        vim.bo[buf].buftype = ""
        vim.api.nvim_win_set_height(win, 8)
        vim.wo[win].number = true

        context.setup({ position = { anchor = "top-right" } })
        context.enable()
        -- Cursor kept off row 0 for the first draw, same reasoning as the
        -- "bottom" anchor test above: drawing itself must not be suppressed
        -- by the very check this test exercises.
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview({ topline = 4, lnum = 8, col = 0 })
        end)
        local shown = context.refresh(win)
        assert.is_true(shown > 0)
        local wcfg = vim.api.nvim_win_get_config((context.float(win)))

        -- Row 0, far-left column: outside the right-anchored box entirely.
        vim.api.nvim_win_set_cursor(win, { 4, 0 })
        assert.is_true(
          context.refresh(win) > 0,
          "a far-left cursor on the overlay's row must not hide a right-anchored box"
        )

        -- Row 0, a column inside the box: this must still hide it.
        local textoff = vim.fn.getwininfo(win)[1].textoff
        vim.api.nvim_win_set_cursor(win, { 4, wcfg.col + 1 - textoff })
        assert.equals(
          0,
          context.refresh(win),
          "a cursor inside a right-anchored box's own columns must hide it"
        )
      end
    )
  end)

  describe("a compact anchor with the cursor on the window's first row", function()
    it("still draws on the very first refresh (no earlier float to judge by)", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      vim.cmd("new")
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "local function outer(a, b)",
        "  if a > b then",
        "    print(a)",
        "    print(b)",
        "  end",
        "  return a",
        "end",
      })
      vim.bo[buf].filetype = "lua"
      vim.bo[buf].buftype = ""
      vim.api.nvim_win_set_height(win, 8)

      context.setup({ position = { anchor = "top-right" } })
      context.enable()
      -- Cursor on screen row 0, far left: the state `zt`, a search jump or
      -- `k` at the window edge leaves behind. With no float yet the overlay
      -- used to be judged "covering the cursor" on the row alone and closed,
      -- so it never got a geometry to be judged by and stayed hidden.
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = 3, lnum = 3, col = 0 })
      end)
      assert.is_nil((context.float(win)), "precondition: nothing drawn yet")
      assert.is_true(context.refresh(win) > 0)
      assert.is_not_nil((context.float(win)))
    end)
  end)

  describe("style = 'chips'", function()
    it("draws every entry as one row of rounded chips, joined by the separator", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ style = "chips" })
      context.enable()
      scroll_to(win, 7)
      local shown = context.refresh(win)
      assert.equals(3, shown)
      local lines = overlay_lines(win)
      assert.equals(1, #lines, "chips draw one row regardless of the entry count")
      assert.truthy(lines[1]:find("outer", 1, true))
      assert.truthy(lines[1]:find("for", 1, true))
      assert.truthy(
        lines[1]:find(vim.fn.nr2char(0x203A), 1, true),
        "separator glyph between chips: " .. lines[1]
      )
      assert.truthy(lines[1]:find(vim.fn.nr2char(0xE0B4), 1, true), "chip right cap: " .. lines[1])
    end)

    it("sizes a compact anchor's box to the chip line's own width", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ style = "chips", position = { anchor = "top-right" } })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      local lines = overlay_lines(win)
      -- strwidth, not strdisplaywidth: the latter folds in wrap-related
      -- padding once a string's width nears/exceeds 'columns', which a
      -- single unwrapped float row never actually needs -- see
      -- trunc_to_width's own doc comment.
      assert.equals(vim.fn.strwidth(lines[1]), wcfg.width)
      assert.is_true(wcfg.width < vim.api.nvim_win_get_width(win))
    end)

    it("a full-width anchor still draws one chip row, just inside a full-width box", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ style = "chips" })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(vim.api.nvim_win_get_width(win), wcfg.width)
      assert.equals(1, wcfg.height)
    end)

    it(
      "truncates by display width, not character count, so wide glyphs never overflow the box",
      function()
        local has_markdown_parser = pcall(vim.treesitter.language.add, "markdown")
        if not has_markdown_parser then
          pending("no Markdown parser available")
          return
        end
        -- Emoji are two display cells wide but one character: a naive
        -- strcharpart(text, 0, width) truncation (width in display cells)
        -- would keep too many of them and overflow the box.
        vim.cmd("new")
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "# " .. string.rep("🚀", 20),
          "",
          "text",
        })
        vim.bo[buf].filetype = "markdown"
        vim.bo[buf].buftype = ""
        vim.api.nvim_win_set_height(win, 6)

        -- A narrow explicit box: whatever survives truncation, its own
        -- display width must never exceed what was asked for.
        context.setup({
          style = "chips",
          position = { anchor = "top-right", col = vim.api.nvim_win_get_width(win) - 6 },
        })
        context.enable()
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview({ topline = 2, lnum = 3, col = 0 })
        end)
        local shown = context.refresh(win)
        assert.equals(1, shown)
        local fwin = context.float(win)
        assert.is_not_nil(fwin)
        local wcfg = vim.api.nvim_win_get_config(fwin)
        local lines = overlay_lines(win)
        assert.is_true(
          vim.fn.strwidth(lines[1]) <= wcfg.width,
          ("rendered width must not exceed the box width %d: %s"):format(wcfg.width, lines[1])
        )
      end
    )

    it(
      "resizes an existing float for new content, instead of staying stuck at the first draw's size",
      function()
        local has_markdown_parser = pcall(vim.treesitter.language.add, "markdown")
        if not has_markdown_parser then
          pending("no Markdown parser available")
          return
        end
        -- `nvim_win_set_config` rejects `noautocmd` on a window that
        -- already exists; a bare `pcall` around that used to swallow the
        -- error and leave every reused float stuck at its very first
        -- row/col/width. Draw a small box, then force a much wider one in
        -- the SAME window, and check the box itself actually grew.
        vim.cmd("new")
        local win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          "# Roadmap",
          "",
          "## Tasks",
          "",
          "### A rather long nested heading that pushes the chip line well past the first box",
          "",
          "text",
        })
        vim.bo[buf].filetype = "markdown"
        vim.bo[buf].buftype = ""
        vim.api.nvim_win_set_height(win, 8)

        context.setup({ style = "chips", position = { anchor = "top-right" } })
        context.enable()

        -- First draw: only "Roadmap" pinned.
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview({ topline = 2, lnum = 3, col = 0 })
        end)
        context.refresh(win)
        local small = vim.api.nvim_win_get_config((context.float(win)))

        -- Same window, scrolled further: three nested headings now pinned,
        -- a much wider chip line.
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview({ topline = 6, lnum = 7, col = 0 })
        end)
        context.refresh(win)
        local big = vim.api.nvim_win_get_config((context.float(win)))

        assert.is_true(
          big.width > small.width,
          ("float must resize for wider content: was %d, still %d"):format(small.width, big.width)
        )
        local lines = overlay_lines(win)
        assert.is_true(vim.fn.strwidth(lines[1]) <= big.width)
      end
    )
  end)

  describe("chips layout/shape", function()
    it("layout = 'stack' draws one chip per line, each fitting its own content", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({
        style = "chips",
        chips = { layout = "stack" },
        position = { anchor = "top-right" },
      })
      context.enable()
      scroll_to(win, 7)
      local shown = context.refresh(win)
      assert.equals(3, shown)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      assert.equals(3, wcfg.height)
      local lines = overlay_lines(win)
      assert.equals(3, #lines)
      assert.truthy(lines[1]:find("outer", 1, true))
      assert.truthy(lines[3]:find("for", 1, true))
      for _, l in ipairs(lines) do
        assert.is_true(vim.fn.strwidth(l) <= wcfg.width)
      end
    end)

    it("layout = 'stack' truncates only the entry that needs it, others stay intact", function()
      local has_markdown_parser = pcall(vim.treesitter.language.add, "markdown")
      if not has_markdown_parser then
        pending("no Markdown parser available")
        return
      end
      vim.cmd("new")
      local win = vim.api.nvim_get_current_win()
      local buf = vim.api.nvim_get_current_buf()
      local long_word = string.rep("x", 100)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "# Roadmap",
        "",
        "## " .. long_word,
        "",
        "text one",
        "text two",
        "text three",
        "text four",
      })
      vim.bo[buf].filetype = "markdown"
      vim.bo[buf].buftype = ""
      vim.api.nvim_win_set_height(win, 8)

      -- anchor stays "top" (the default, full window width): the box itself
      -- does not shrink to content here, only individual lines truncate.
      -- Cursor kept off the overlay's own rows (2 entries -> rows 0-1), same
      -- reasoning as the other "never cover the cursor" tests.
      context.setup({ style = "chips", chips = { layout = "stack" } })
      context.enable()
      vim.api.nvim_win_call(win, function()
        vim.fn.winrestview({ topline = 4, lnum = 8, col = 0 })
      end)
      local shown = context.refresh(win)
      assert.equals(2, shown)
      local wcfg = vim.api.nvim_win_get_config((context.float(win)))
      local lines = overlay_lines(win)
      assert.equals(2, #lines)
      assert.truthy(lines[1]:find("Roadmap", 1, true), "the short entry stays intact: " .. lines[1])
      assert.falsy(
        lines[2]:find(long_word, 1, true),
        "the long entry must be truncated: " .. lines[2]
      )
      for _, l in ipairs(lines) do
        assert.is_true(vim.fn.strwidth(l) <= wcfg.width)
      end
    end)

    it("shape = 'rect' draws no cap glyphs", function()
      if not has_lua_parser then
        pending("no Lua parser available")
        return
      end
      local win = open_source()
      context.setup({ style = "chips", chips = { shape = "rect" } })
      context.enable()
      scroll_to(win, 7)
      context.refresh(win)
      local lines = overlay_lines(win)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("outer", 1, true))
      assert.is_nil(lines[1]:find(vim.fn.nr2char(0xE0B6), 1, true), "no left cap in rect shape")
      assert.is_nil(lines[1]:find(vim.fn.nr2char(0xE0B4), 1, true), "no right cap in rect shape")
      assert.truthy(
        lines[1]:find(vim.fn.nr2char(0x203A), 1, true),
        "separator is unaffected by shape: " .. lines[1]
      )
    end)
  end)
end)
