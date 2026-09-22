-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.shortlist`'s preview pane as something to work in, not only look at:
--- scrolling it from the list, hopping focus between list and preview, `<CR>`
--- at the cursor line, closing from inside, closing when focus leaves, and the
--- hints (footer, lit border). Keys are driven through `nvim_feedkeys` so that
--- the mappings themselves are what is tested, not just the functions behind
--- them. (The list+preview basics stay in `ui_kit_spec.lua`.)

local kit = require("ui.kit")

--- 200 lines, so the preview has somewhere to scroll to.
local LONG = {}
for i = 1, 200 do
  LONG[i] = ("line %d"):format(i)
end

---@param key string  e.g. "<C-f>"
local function press(key)
  vim.api.nvim_feedkeys(vim.keycode(key), "mx", false)
end

---@param win integer
---@return integer
local function topline(win)
  return vim.fn.getwininfo(win)[1].topline
end

---@param win integer
---@return string
local function winhl(win)
  return vim.api.nvim_get_option_value("winhighlight", { win = win })
end

---@param win integer
---@return string
local function footer_text(win)
  local footer = vim.api.nvim_win_get_config(win).footer
  if type(footer) ~= "table" then
    return ""
  end
  local out = {}
  for _, chunk in ipairs(footer) do
    out[#out + 1] = type(chunk) == "table" and chunk[1] or tostring(chunk)
  end
  return table.concat(out)
end

describe("ui.kit.shortlist: the preview pane", function()
  local h
  local main
  local items

  ---@param extra table|nil  merged over the default options
  local function open(extra)
    items = { { path = "a.txt" }, { path = "b.txt" } }
    h = assert(
      kit.shortlist(vim.tbl_extend("force", {
        items = items,
        format_item = function(item)
          return item.path
        end,
        preview_bo = { modifiable = false },
        render = function(item, surface)
          surface:set_lines(vim.deepcopy(LONG))
          surface.tag = item.path
        end,
        on_submit = function() end,
      }, extra or {})),
      "shortlist opens"
    )
    return h
  end

  before_each(function()
    main = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    if h and h.results:is_valid() then
      h.close()
    end
    h = nil
    if vim.api.nvim_win_is_valid(main) then
      vim.api.nvim_set_current_win(main)
    end
  end)

  describe("scrolling from the list", function()
    it("<C-f> and <C-p> move the preview one page down and up, the list keeps focus", function()
      open()
      assert.equals(h.results.winid, vim.api.nvim_get_current_win())
      assert.equals(1, topline(h.preview.winid))

      press("<C-f>")
      local after_page = topline(h.preview.winid)
      assert.is_true(after_page > 1, "<C-f> scrolled the preview")
      assert.equals(h.results.winid, vim.api.nvim_get_current_win(), "focus stays in the list")

      press("<C-p>")
      assert.is_true(topline(h.preview.winid) < after_page, "<C-p> scrolled it back")
      assert.equals(1, topline(h.preview.winid), "one page down and one page up is where it began")
    end)

    it("the aliases scroll the same way: <PageDown>/<PageUp> and <C-b>", function()
      open()
      press("<PageDown>")
      local down = topline(h.preview.winid)
      assert.is_true(down > 1, "<PageDown> scrolled")
      press("<PageUp>")
      assert.equals(1, topline(h.preview.winid), "<PageUp> undid it")
      press("<PageDown>")
      press("<C-b>")
      assert.equals(1, topline(h.preview.winid), "<C-b> is a page up as well")
    end)

    it("<C-d>/<C-u> move half a page, less than <C-f> does", function()
      open()
      press("<C-d>")
      local half = topline(h.preview.winid)
      assert.is_true(half > 1, "<C-d> scrolled")
      press("<C-u>")
      assert.equals(1, topline(h.preview.winid))
      press("<C-f>")
      assert.is_true(topline(h.preview.winid) > half, "a full page goes further than half of one")
    end)

    it("the same keys scroll from inside the preview", function()
      open()
      press("<Tab>")
      assert.equals(h.preview.winid, vim.api.nvim_get_current_win())
      press("<C-f>")
      local down = topline(h.preview.winid)
      assert.is_true(down > 1, "<C-f> scrolls the preview from inside it")
      -- <C-p> is Vim's "one line up" natively; here it is a page, as in the list.
      press("<C-p>")
      assert.equals(1, topline(h.preview.winid), "<C-p> is a page up in the preview too")
    end)
  end)

  describe("focus", function()
    it("opens with focus in the list, not the preview", function()
      open()
      assert.equals(h.results.winid, vim.api.nvim_get_current_win())
      assert.is_not.equal(h.preview.winid, vim.api.nvim_get_current_win())
    end)

    it("<Tab> hops between list and preview", function()
      open()
      press("<Tab>")
      assert.equals(h.preview.winid, vim.api.nvim_get_current_win(), "list -> preview")
      press("<Tab>")
      assert.equals(h.results.winid, vim.api.nvim_get_current_win(), "preview -> list")
    end)

    it("the window-cycle keys stay inside the popup instead of walking on to the editor", function()
      open()
      for _, key in ipairs({ "<C-w>w", "<C-w><C-w>", "<C-w>W" }) do
        assert.equals(h.results.winid, vim.api.nvim_get_current_win(), key .. ": start in the list")
        press(key)
        assert.equals(h.preview.winid, vim.api.nvim_get_current_win(), key .. ": list -> preview")
        press(key)
        assert.equals(
          h.results.winid,
          vim.api.nvim_get_current_win(),
          key .. ": preview -> list, not the editor"
        )
      end
      assert.is_true(h.results:is_valid() and h.preview:is_valid(), "the popup is still open")
    end)

    it(
      "<C-w>j/<C-w>k hop too, but direction-aware -- a no-op at the edge, not a jump the wrong way",
      function()
        open()
        assert.equals(h.results.winid, vim.api.nvim_get_current_win(), "starts in the list")

        press("<C-w>j") -- "down": nothing below the list
        assert.equals(
          h.results.winid,
          vim.api.nvim_get_current_win(),
          "<C-w>j in the list is a no-op"
        )

        press("<C-w>k") -- "up": the preview is above the list
        assert.equals(
          h.preview.winid,
          vim.api.nvim_get_current_win(),
          "<C-w>k in the list -> preview"
        )

        press("<C-w>k") -- "up": nothing above the preview
        assert.equals(
          h.preview.winid,
          vim.api.nvim_get_current_win(),
          "<C-w>k in the preview is a no-op"
        )

        press("<C-w>j") -- "down": the list is below the preview
        assert.equals(
          h.results.winid,
          vim.api.nvim_get_current_win(),
          "<C-w>j in the preview -> list"
        )
      end
    )

    it("the list's selection survives a trip into the preview", function()
      open()
      vim.api.nvim_win_set_cursor(h.results.winid, { 2, 0 })
      press("<Tab>")
      assert.equals(items[2], h.current_item(), "current_item() still reads the highlighted row")
      assert.equals(2, h.current_index())
    end)

    it("focus leaving for another window closes the popup", function()
      open()
      press("<Tab>")
      vim.api.nvim_set_current_win(main)
      assert.is_true(
        vim.wait(1000, function()
          return not h.results:is_valid() and not h.preview:is_valid()
        end, 10),
        "both windows are gone"
      )
    end)

    it("close_on_leave = false keeps it open", function()
      open({ close_on_leave = false })
      vim.api.nvim_set_current_win(main)
      vim.wait(150, function()
        return false
      end, 10)
      assert.is_true(h.results:is_valid() and h.preview:is_valid())
    end)
  end)

  describe("closing", function()
    it("q and <Esc> in the preview close the whole popup", function()
      for _, key in ipairs({ "q", "<Esc>" }) do
        open()
        press("<Tab>")
        press(key)
        assert.is_false(h.results:is_valid(), key .. " closed the list")
        assert.is_false(h.preview:is_valid(), key .. " closed the preview")
      end
    end)

    it("q in the list still closes it, as before", function()
      open()
      press("q")
      assert.is_false(h.results:is_valid())
      assert.is_false(h.preview:is_valid())
    end)
  end)

  describe("<CR> in the preview", function()
    it("hands the item and the cursor line to on_preview_submit, after the popup closed", function()
      local got
      open({
        on_preview_submit = function(item, idx, pos)
          got = {
            item = item,
            idx = idx,
            pos = pos,
            results_open = h.results:is_valid(),
            preview_open = h.preview:is_valid(),
          }
        end,
      })
      vim.api.nvim_win_set_cursor(h.results.winid, { 2, 0 })
      press("<Tab>")
      vim.api.nvim_win_set_cursor(h.preview.winid, { 37, 3 })
      press("<CR>")

      assert.is_table(got, "on_preview_submit ran")
      assert.equals(items[2], got.item, "the highlighted item, not the first")
      assert.equals(2, got.idx)
      assert.same({ row = 37, col = 3 }, got.pos, "the preview cursor")
      assert.is_false(got.results_open, "the list was already closed")
      assert.is_false(got.preview_open, "the preview was already closed")
    end)

    it("falls back to on_submit(item, idx) without an on_preview_submit", function()
      local got
      open({
        on_submit = function(item, idx)
          got = { item = item, idx = idx }
        end,
      })
      press("<Tab>")
      press("<CR>")
      assert.same({ item = items[1], idx = 1 }, got)
      assert.is_false(h.preview:is_valid())
    end)

    it("<CR> in the list still calls on_submit, not on_preview_submit", function()
      local submitted, preview_submitted = false, false
      open({
        on_submit = function()
          submitted = true
        end,
        on_preview_submit = function()
          preview_submitted = true
        end,
      })
      press("<CR>")
      assert.is_true(submitted)
      assert.is_false(preview_submitted)
    end)
  end)

  describe("read-only", function()
    it("everything that reads works in the preview, nothing can change it", function()
      open()
      press("<Tab>")
      vim.api.nvim_win_set_cursor(h.preview.winid, { 5, 0 })
      press("yy")
      assert.equals("line 5\n", vim.fn.getreg('"'), "yank copies the line")

      local before = vim.api.nvim_buf_get_lines(h.preview.bufnr, 0, -1, false)
      pcall(vim.api.nvim_feedkeys, vim.keycode("dd"), "mx", false)
      pcall(vim.api.nvim_feedkeys, vim.keycode("ihello<Esc>"), "mx", false)
      assert.same(
        before,
        vim.api.nvim_buf_get_lines(h.preview.bufnr, 0, -1, false),
        "the buffer is unchanged"
      )
      assert.is_false(vim.bo[h.preview.bufnr].modifiable)
    end)
  end)

  describe("hints", function()
    it("each window's footer lists the keys that work there", function()
      open()
      local list = footer_text(h.results.winid)
      local view = footer_text(h.preview.winid)
      assert.truthy(list:find("<C-f>/<C-p> scroll", 1, true), "list: " .. list)
      assert.truthy(list:find("<Tab> preview", 1, true), "list: " .. list)
      assert.truthy(list:find("q close", 1, true), "list: " .. list)
      assert.truthy(view:find("y copy", 1, true), "preview: " .. view)
      assert.truthy(view:find("<CR> open at line", 1, true), "preview: " .. view)
      assert.truthy(view:find("<Tab> list", 1, true), "preview: " .. view)
    end)

    it("the focused window's border is lit, and follows the focus", function()
      open()
      assert.truthy(
        winhl(h.results.winid):find("FloatBorder:KitAccent", 1, true),
        "list lit at open"
      )
      assert.truthy(winhl(h.preview.winid):find("FloatBorder:KitBorder", 1, true), "preview idle")

      press("<Tab>")
      assert.truthy(winhl(h.preview.winid):find("FloatBorder:KitAccent", 1, true), "preview lit")
      assert.truthy(winhl(h.results.winid):find("FloatBorder:KitBorder", 1, true), "list idle")
      assert.truthy(
        winhl(h.results.winid):find("CursorLine:KitSelection", 1, true),
        "the chooser's own entry survived"
      )
    end)

    it("hints = false leaves footers and borders alone", function()
      open({ hints = false })
      assert.equals("", footer_text(h.results.winid))
      assert.equals("", footer_text(h.preview.winid))
      press("<Tab>")
      assert.is_nil(winhl(h.preview.winid):find("KitAccent", 1, true))
    end)

    it("a disabled key group is left out of the hints", function()
      open({ preview_keys = { scroll_down = false, submit = false } })
      assert.is_nil(footer_text(h.results.winid):find("scroll", 1, true))
      assert.is_nil(footer_text(h.preview.winid):find("open at line", 1, true))
    end)
  end)

  describe("configuring the keys", function()
    ---@param bufnr integer
    ---@param lhs string
    ---@return boolean
    local function mapped(bufnr, lhs)
      local want = vim.keycode(lhs)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if vim.keycode(m.lhs) == want then
          return true
        end
      end
      return false
    end

    it("preview_keys = false binds nothing", function()
      open({ preview_keys = false })
      for _, lhs in ipairs({ "<C-f>", "<C-p>", "<Tab>", "<C-w>w" }) do
        assert.is_false(mapped(h.results.bufnr, lhs), lhs .. " on the list")
      end
      for _, lhs in ipairs({ "<C-f>", "<C-p>", "<Tab>", "<C-w>w", "q", "<Esc>", "<CR>" }) do
        assert.is_false(mapped(h.preview.bufnr, lhs), lhs .. " on the preview")
      end
    end)

    it("a group takes your own keys, and false switches just that group off", function()
      open({ preview_keys = { scroll_down = { "<C-j>" }, close = false } })
      assert.is_true(mapped(h.results.bufnr, "<C-j>"), "the custom scroll key")
      assert.is_false(mapped(h.results.bufnr, "<C-f>"), "the default one is replaced, not added to")
      assert.is_true(mapped(h.results.bufnr, "<C-p>"), "the other groups keep their defaults")
      assert.is_false(mapped(h.preview.bufnr, "q"), "close = false leaves q unbound in the preview")
      assert.is_true(mapped(h.preview.bufnr, "<CR>"))

      press("<C-j>")
      assert.is_true(topline(h.preview.winid) > 1, "the custom key scrolls")
    end)

    it("a bare string is a list of one, not a group that silently vanishes", function()
      open({ preview_keys = { scroll_down = "<C-j>" } })
      assert.is_true(mapped(h.results.bufnr, "<C-j>"), "the string is bound")
      assert.is_false(mapped(h.results.bufnr, "<C-f>"), "and replaces the group's defaults")
    end)

    it("entries that are not keys are ignored, not left as a half-open popup", function()
      -- A table in a key list made the hint text raise, an empty string made `map`
      -- raise ("Invalid (empty) LHS") -- both after the two windows were up, so
      -- both stayed open with no handle to close them.
      local before = #vim.api.nvim_list_wins()
      open({
        preview_keys = {
          scroll_down = { {}, "", "<C-j>" },
          focus = { "" },
          half_down = { {} },
        },
      })
      assert.equals(before + 2, #vim.api.nvim_list_wins(), "the list and the preview, no more")
      assert.is_true(mapped(h.results.bufnr, "<C-j>"), "the usable entry is bound")
      assert.is_false(mapped(h.results.bufnr, "<Tab>"), "a group left with no key is off")
      assert.is_false(mapped(h.results.bufnr, "<C-d>"), "so is one that only held a table")
      assert.is_true(mapped(h.results.bufnr, "<C-p>"), "the other groups keep their defaults")
    end)
  end)
end)

describe("ui.kit.shortlist: a preview that cannot be rendered", function()
  local h
  local main

  ---@param extra table|nil  merged over the default options
  local function open(extra)
    h = assert(
      kit.shortlist(vim.tbl_extend("force", {
        items = { { path = "good.txt" }, { path = "bad.bin" } },
        format_item = function(item)
          return item.path
        end,
        preview_bo = { modifiable = false },
        render = function(item, surface)
          if item.path == "bad.bin" then
            -- What a NUL byte out of readfile() looks like: the API refuses it.
            surface:set_lines({ "one\ntwo" })
          else
            surface:set_lines({ "good content" })
          end
        end,
      }, extra or {})),
      "shortlist opens"
    )
    return h
  end

  --- Put the list's cursor on row `row` the way a keypress would.
  ---@param row integer
  local function select_row(row)
    vim.api.nvim_win_set_cursor(h.results.winid, { row, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = h.results.bufnr })
  end

  ---@return string[]
  local function preview_lines()
    return vim.api.nvim_buf_get_lines(h.preview.bufnr, 0, -1, false)
  end

  before_each(function()
    main = vim.api.nvim_get_current_win()
  end)

  after_each(function()
    if h and h.results:is_valid() then
      h.close()
    end
    h = nil
    if vim.api.nvim_win_is_valid(main) then
      vim.api.nvim_set_current_win(main)
    end
  end)

  it("says so, instead of keeping the previous item's text under the new selection", function()
    open()
    assert.same({ "good content" }, preview_lines())

    select_row(2)
    local shown = preview_lines()
    assert.equals(1, #shown)
    assert.truthy(
      shown[1]:find("preview failed:", 1, true),
      "the pane says it failed: " .. shown[1]
    )
    assert.is_nil(shown[1]:find("good content", 1, true), "and no longer shows the other item")
    assert.equals(1, vim.api.nvim_win_get_cursor(h.preview.winid)[1], "cursor on the notice")

    select_row(1)
    assert.same({ "good content" }, preview_lines(), "the pane recovers on an item that renders")
  end)

  it("a preview that stays read-only when its render raises", function()
    open()
    select_row(2)
    assert.is_false(vim.bo[h.preview.bufnr].modifiable, "the render raised in set_lines")
  end)

  it(
    "Surface:set_lines puts `modifiable` back when the API refuses a line, and still raises",
    function()
      open()
      local ok, err = pcall(h.preview.set_lines, h.preview, { "a\nb" })
      assert.is_false(ok, "the caller still sees the error")
      assert.truthy(
        tostring(err):find("newline", 1, true),
        "and it is the API's own: " .. tostring(err)
      )
      assert.is_false(vim.bo[h.preview.bufnr].modifiable, "a read-only pane stays read-only")
    end
  )
end)
