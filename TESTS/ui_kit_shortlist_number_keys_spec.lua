-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.shortlist`'s opt-in `number_keys`: `1`..`9` in the list submit the
--- first nine entries like `<CR>` does, and each of those lines shows its digit
--- (or leaves drawing it to `format_item`). Keys are driven through
--- `nvim_feedkeys`, so the mappings themselves are what is tested.

local kit = require("ui.kit")

---@param key string
local function press(key)
  vim.api.nvim_feedkeys(vim.keycode(key), "mx", false)
end

---@param bufnr integer
---@param lhs string
---@return boolean
local function has_map(bufnr, lhs)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
    if m.lhs == lhs then
      return true
    end
  end
  return false
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

---@param n integer
---@return string[]
local function names(n)
  local out = {}
  for i = 1, n do
    out[i] = ("item%d"):format(i)
  end
  return out
end

describe("ui.kit.shortlist: number_keys", function()
  local h
  local main
  local submitted
  local widths

  ---@param extra table|nil  merged over the default options
  ---@param count integer|nil  how many items (default 4)
  local function open(extra, count)
    submitted = {}
    widths = {}
    h = assert(
      kit.shortlist(vim.tbl_extend("force", {
        items = names(count or 4),
        format_item = function(item, width)
          widths[#widths + 1] = width
          return item
        end,
        render = function(item, surface)
          surface:set_lines({ item })
        end,
        on_submit = function(item, idx)
          submitted[#submitted + 1] = { item = item, idx = idx }
        end,
      }, extra or {})),
      "shortlist opens"
    )
    return h
  end

  ---@return string[]
  local function list_lines()
    return vim.api.nvim_buf_get_lines(h.results.bufnr, 0, -1, false)
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

  it("`3` submits the third entry like <CR> does, and closes the popup", function()
    open({ number_keys = true })
    local results, preview = h.results, h.preview
    press("3")
    assert.equals(1, #submitted, "on_submit ran once")
    assert.equals("item3", submitted[1].item)
    assert.equals(3, submitted[1].idx)
    assert.is_false(results:is_valid(), "the list closed")
    assert.is_false(preview:is_valid(), "the preview closed with it")
  end)

  it("labels each entry with its digit, once, and gives format_item the narrower width", function()
    open({ number_keys = true })
    assert.same({ "1 item1", "2 item2", "3 item3", "4 item4" }, list_lines())
    local slot = vim.api.nvim_win_get_width(h.results.winid)
    assert.equals(slot - 2, widths[1], "format_item's budget leaves room for the label")
  end)

  it("binds only the first nine; the tenth entry on is blank-padded to line up", function()
    open({ number_keys = true }, 11)
    local lines = list_lines()
    assert.equals("9 item9", lines[9])
    assert.equals("  item10", lines[10])
    assert.equals("  item11", lines[11])
    for i = 1, 9 do
      assert.is_true(has_map(h.results.bufnr, tostring(i)), ("`%d` is bound"):format(i))
    end
  end)

  it("binds no more digits than there are entries", function()
    open({ number_keys = true }, 2)
    assert.is_true(has_map(h.results.bufnr, "2"))
    assert.is_false(has_map(h.results.bufnr, "3"), "no `3` for a two-entry list")
  end)

  it("without the option: no digit maps, no labels", function()
    open()
    for i = 1, 9 do
      assert.is_false(has_map(h.results.bufnr, tostring(i)), ("`%d` is not bound"):format(i))
    end
    assert.same({ "item1", "item2", "item3", "item4" }, list_lines())
    assert.is_nil(footer_text(h.results.winid):find("1-", 1, true), "no digit hint")
  end)

  it("{ label = false } binds the keys, format_item (given idx) draws the digit", function()
    local seen = {}
    open({
      number_keys = { label = false },
      format_item = function(item, _width, idx)
        seen[#seen + 1] = idx
        return ("[%d] %s"):format(idx, item)
      end,
    })
    assert.same({ "[1] item1", "[2] item2", "[3] item3", "[4] item4" }, list_lines())
    assert.same({ 1, 2, 3, 4 }, seen)
    press("2")
    assert.equals("item2", submitted[1].item)
    assert.equals(2, submitted[1].idx)
  end)

  it("the list footer names the digit keys", function()
    open({ number_keys = true })
    assert.is_truthy(footer_text(h.results.winid):find("1-4 open", 1, true))
  end)

  it("a resize re-formats with the label kept", function()
    open({ number_keys = true })
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert.same({ "1 item1", "2 item2", "3 item3", "4 item4" }, list_lines())
  end)

  it("digits stay counts in the preview", function()
    open({ number_keys = true })
    assert.is_false(has_map(h.preview.bufnr, "3"), "the preview binds no digits")
  end)
end)
