-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.bindings.keymaps` driven through the keyboard: every default key is
--- typed with `nvim_feedkeys(..., "x")` (the typeahead is executed until it
--- is empty, mappings included) and the spec asserts what the action did --
--- the current buffer, `vim.t.bufs`, the pin state, the tab pages, the
--- colorscheme, the picker float, the sticky context. `keymaps_spec.lua`
--- covers the registration (lhs, desc, overrides); this file covers that the
--- registered key actually reaches its action.
---
--- Not covered here, on purpose: the close flash (`ui.tabline.utils.flash`)
--- is a highlight swap of ~120ms with no state worth asserting beyond "the
--- buffer closed afterwards", which the close cases below do check.

local keymaps = require("ui.bindings.keymaps")
local state = require("ui.bindings.keymaps.tabufline.state")

--- Type `keys` as if from the keyboard (termcodes and <leader> resolved) and
--- run them, mappings included, before returning.
---@param keys string
local function press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
end

--- Wait for a deferred action (the close keys run 25ms behind their flash).
---@param cond fun(): boolean
local function wait_for(cond)
  vim.wait(1000, cond, 10)
end

---@param name string
---@return integer bufnr
local function open_named_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

---@param bufs integer[]
---@param buf integer
---@return boolean
local function has(bufs, buf)
  return vim.tbl_contains(bufs or {}, buf)
end

--- Back to one tab with one empty buffer, every other buffer wiped.
local function reset_layout()
  pcall(vim.cmd, "silent! tabonly!")
  pcall(vim.cmd, "silent! only!")
  vim.cmd("enew!")
  local keep = vim.api.nvim_get_current_buf()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= keep then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

describe("ui.bindings.keymaps default keys, typed", function()
  local a, b, c

  before_each(function()
    reset_layout()
    keymaps.setup()
    vim.cmd("tabnew")
    a = open_named_buffer("ui-keymaps-feedkeys-a.txt")
    b = open_named_buffer("ui-keymaps-feedkeys-b.txt")
    c = open_named_buffer("ui-keymaps-feedkeys-c.txt")
    assert.same({ a, b, c }, vim.t.bufs)
  end)

  after_each(function()
    reset_layout()
  end)

  it("<Tab> goes to the next buffer, wrapping, and takes a count", function()
    vim.api.nvim_set_current_buf(a)
    press("<Tab>")
    assert.equals(b, vim.api.nvim_get_current_buf())
    press("<Tab>")
    press("<Tab>")
    assert.equals(a, vim.api.nvim_get_current_buf(), "wraps from the last to the first")
    press("2<Tab>")
    assert.equals(c, vim.api.nvim_get_current_buf(), "a count moves that many")
  end)

  it("<S-Tab> goes to the previous buffer, wrapping", function()
    vim.api.nvim_set_current_buf(b)
    press("<S-Tab>")
    assert.equals(a, vim.api.nvim_get_current_buf())
    press("<S-Tab>")
    assert.equals(c, vim.api.nvim_get_current_buf(), "wraps from the first to the last")
  end)

  it("<leader>bc closes the current buffer and lands on its neighbour", function()
    vim.api.nvim_set_current_buf(b)
    press("<leader>bc")
    wait_for(function()
      return not vim.api.nvim_buf_is_valid(b) or not vim.bo[b].buflisted
    end)
    assert.is_false(has(vim.t.bufs, b))
    assert.same({ a, c }, vim.t.bufs)
    assert.equals(c, vim.api.nvim_get_current_buf())
  end)

  it("2<leader>bc closes two buffers", function()
    vim.api.nvim_set_current_buf(a)
    press("2<leader>bc")
    wait_for(function()
      return #vim.t.bufs == 1
    end)
    assert.same({ c }, vim.t.bufs)
    assert.equals(c, vim.api.nvim_get_current_buf())
  end)

  it("<leader>bq closes every listed buffer of the tab except a pinned one", function()
    state.set_pinned(a, true)
    vim.api.nvim_set_current_buf(c)
    press("<leader>bq")
    wait_for(function()
      return not has(vim.t.bufs, b) and not has(vim.t.bufs, c)
    end)
    assert.same({ a }, vim.t.bufs)
  end)

  it("<leader>bp pins the current buffer, and unpins it again", function()
    vim.api.nvim_set_current_buf(b)
    assert.is_false(state.is_pinned(b))
    press("<leader>bp")
    assert.is_true(state.is_pinned(b))
    press("<leader>bp")
    assert.is_false(state.is_pinned(b))
  end)

  it("<leader>tr / <leader>tl move the current buffer one slot right / left", function()
    vim.api.nvim_set_current_buf(a)
    press("<leader>tr")
    assert.same({ b, a, c }, vim.t.bufs)
    assert.equals(a, vim.api.nvim_get_current_buf(), "moving does not switch buffers")
    press("<leader>tl")
    assert.same({ a, b, c }, vim.t.bufs)
  end)

  it("<leader>tt moves the current buffer into a new tab and drops its chip here", function()
    vim.api.nvim_set_current_buf(c)
    local source = vim.api.nvim_get_current_tabpage()
    local tabs_before = #vim.api.nvim_list_tabpages()
    press("<leader>tt")
    assert.equals(tabs_before + 1, #vim.api.nvim_list_tabpages())
    assert.are_not.equal(source, vim.api.nvim_get_current_tabpage())
    assert.equals(c, vim.api.nvim_get_current_buf())
    assert.is_false(has(vim.t[source].bufs, c), "the source tab forgot the moved buffer")
  end)
end)

describe("ui.bindings.keymaps <leader>bu, typed", function()
  local dir = vim.fn.stdpath("run") .. "/ui-keymaps-feedkeys-spec"
  local path

  before_each(function()
    reset_layout()
    keymaps.setup()
    require("ui.tabline.reopen").clear()
    vim.fn.mkdir(dir, "p")
    path = dir .. "/reopen-me.txt"
    vim.fn.writefile({ "one", "two" }, path)
  end)

  after_each(function()
    reset_layout()
    require("ui.tabline.reopen").clear()
    vim.fn.delete(dir, "rf")
  end)

  it("reopens the most recently closed file", function()
    vim.cmd.edit(vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    vim.cmd("bdelete! " .. buf)
    assert.is_true(require("ui.tabline.reopen").has_any())

    press("<leader>bu")
    local name = vim.api.nvim_buf_get_name(0)
    assert.equals(
      vim.fs.normalize(vim.uv.fs_realpath(path) or path),
      vim.fs.normalize(vim.uv.fs_realpath(name) or name)
    )
    assert.is_true(vim.bo.buflisted)
    assert.is_false(require("ui.tabline.reopen").has_any(), "the entry left the ring")
  end)
end)

describe("ui.bindings.keymaps theme keys, typed", function()
  local config = require("ui.config")
  local saved

  before_each(function()
    reset_layout()
    saved = config.__save_state()
    -- Two colorschemes every Neovim ships, instead of the default pair's
    -- tokyonight, which a bare headless run does not have.
    config.setup({ theme = { theme_toggle = { "default", "blue" } } })
    keymaps.setup()
    vim.cmd.colorscheme("default")
  end)

  after_each(function()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(winid).relative ~= "" then
        pcall(vim.api.nvim_win_close, winid, true)
      end
    end
    vim.wait(50)
    config.__restore_state(saved)
    pcall(vim.cmd.colorscheme, "default")
    reset_layout()
  end)

  it("<leader>ut switches between the two configured themes", function()
    press("<leader>ut")
    assert.equals("blue", vim.g.colors_name)
    press("<leader>ut")
    assert.equals("default", vim.g.colors_name)
  end)

  it("<leader>uP opens the theme picker float on the current theme", function()
    local before = vim.api.nvim_get_current_win()
    press("<leader>uP")
    local win = vim.api.nvim_get_current_win()
    assert.are_not.equal(before, win)
    assert.are_not.equal("", vim.api.nvim_win_get_config(win).relative, "a float")
    local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
    local joined = table.concat(lines, "\n")
    assert.truthy(joined:find("blue", 1, true), "lists the colorschemes")
    assert.truthy(joined:find("default", 1, true), "lists the colorschemes")
  end)
end)

describe("ui.bindings.keymaps sticky-context keys, typed", function()
  local context = require("ui.context")

  before_each(function()
    reset_layout()
    keymaps.setup()
    context.disable()
  end)

  after_each(function()
    context.disable()
  end)

  for _, lhs in ipairs({ "<M-p>", "<leader>us" }) do
    it(lhs .. " switches the sticky context on and off", function()
      press(lhs)
      assert.is_true(context.is_enabled())
      press(lhs)
      assert.is_false(context.is_enabled())
    end)
  end
end)
