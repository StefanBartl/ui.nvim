-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- A kit float is one buffer for its whole life.
---
--- Every kit float's buffer is `bufhidden = "wipe"`. A key that changes the buffer of
--- the WINDOW -- `<C-o>`/`<C-^>` from the jumplist every new float inherits, `:bnext`,
--- `:e` -- put the user's file into the float and wiped the component's buffer
--- from under it: the window stayed open with no callback left to fire, and a
--- `kit.sync` caller waited out its ten minutes. The Normal-mode rows (a select
--- field, a button row) make those keys easy to hit. `surface.open` sets
--- `winfixbuf`, which turns the swap into E1513.

local kit = require("ui.kit")
local api = vim.api

---@param keys string
local function feed(keys)
  -- A refused swap raises E1513 inside the fed keys: that is the point, not a failure.
  pcall(api.nvim_feedkeys, api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

local function close_floats()
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(w).relative ~= "" then
      pcall(api.nvim_win_close, w, true)
    end
  end
end

describe("kit floats are winfixbuf", function()
  local dir
  local jumped_to

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "a" }, dir .. "/a.txt")
    vim.fn.writefile({ "b" }, dir .. "/b.txt")
    -- Two files in the jumplist of the window: a float opened from it inherits it,
    -- so `<C-o>` has somewhere to go.
    vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/a.txt"))
    vim.cmd("normal! m'")
    vim.cmd("edit " .. vim.fn.fnameescape(dir .. "/b.txt"))
    vim.cmd("normal! m'")
    jumped_to = vim.fn.bufnr(dir .. "/a.txt")
  end)

  after_each(function()
    close_floats()
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  it("sets winfixbuf on every surface, unless the caller says otherwise", function()
    local s = kit.surface.open({ lines = { "x" } })
    assert.is_true(vim.wo[s.winid].winfixbuf)
    local free = kit.surface.open({ lines = { "x" }, wo = { winfixbuf = false } })
    assert.is_false(vim.wo[free.winid].winfixbuf)
  end)

  it("keeps a sheet's buffer when <C-o> is pressed on a select row", function()
    local result
    local surf = kit.sheet({
      fields = {
        { name = "area", kind = "select", choices = { "Alpha", "Beta" } },
        { name = "title" },
      },
      on_submit = function(v)
        result = v
      end,
      on_cancel = function()
        result = "cancelled"
      end,
    })
    assert.equals("area", surf:state().focus, "the focus is on the select row, in Normal mode")
    assert.is_true(vim.wo[surf.winid].winfixbuf)
    assert.is_true(#vim.fn.getjumplist(surf.winid)[1] >= 2, "the float inherited a jumplist")
    feed("<C-o>")
    assert.is_true(api.nvim_buf_is_valid(surf.bufnr), "the sheet's buffer is still there")
    assert.equals(surf.bufnr, api.nvim_win_get_buf(surf.winid))
    assert.not_equals(jumped_to, api.nvim_win_get_buf(surf.winid))
    -- Nothing was stranded: it still answers.
    feed("<Esc>")
    assert.equals("cancelled", result)
    assert.is_false(surf:is_valid())
  end)

  it("keeps a prompt's buffer when <C-o> or <C-^> is pressed on its button row", function()
    local result
    local surf = kit.input({
      buttons = { { id = "submit", label = "OK" }, { id = "skip", label = "Skip" } },
      on_submit = function(v)
        result = v
      end,
      on_cancel = function()
        result = "cancelled"
      end,
    })
    feed("<Down>")
    assert.is_false(vim.bo[surf.bufnr].modifiable, "the focus is on the button row")
    feed("<C-o>")
    feed("<C-^>")
    assert.is_true(api.nvim_buf_is_valid(surf.bufnr), "the prompt's buffer is still there")
    assert.equals(surf.bufnr, api.nvim_win_get_buf(surf.winid))
    feed("<Esc>")
    assert.equals("cancelled", result)
    assert.is_false(surf:is_valid())
  end)

  it("keeps a confirm dialog's buffer", function()
    local confirm = require("ui.kit.confirm")
    local answered
    local surf = confirm.open({
      question = "Sure?",
      on_answer = function(v)
        answered = v
      end,
    })
    feed("<C-o>")
    assert.is_true(api.nvim_buf_is_valid(surf.bufnr))
    assert.equals(surf.bufnr, api.nvim_win_get_buf(surf.winid))
    feed("<Esc>")
    assert.is_false(answered)
  end)

  it("still cancels a prompt whose buffer was swapped by force", function()
    -- Not reachable by a key any more, but another plugin can do it through the API
    -- after taking the option off: the close of the window must still be answered.
    local cancelled = 0
    local surf = kit.input({
      on_cancel = function()
        cancelled = cancelled + 1
      end,
    })
    vim.wo[surf.winid].winfixbuf = false
    local other = api.nvim_create_buf(true, false)
    api.nvim_win_set_buf(surf.winid, other)
    assert.is_false(api.nvim_buf_is_valid(surf.bufnr), "the prompt's buffer is wiped")
    api.nvim_win_close(surf.winid, true)
    assert.equals(1, cancelled, "on_cancel fires once, from the window closing")
  end)
end)
