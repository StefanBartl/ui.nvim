-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.bindings.keymaps.tabufline.state` — the `vim.t.bufs` bookkeeping and
--- the `close_buffer()`/`move_buf()` this plugin used to reach into
--- `nvchad.tabufline` for, run WITHOUT NvChad. `nvchad.tabufline` never
--- appears anywhere in this file, on purpose: everything here is what used
--- to be entirely that module's job.

local state = require("ui.bindings.keymaps.tabufline.state")

--- Open a fresh scratch buffer, named so `close_buffer()`'s "unlisted, no
--- window" path is never hit by accident, and switch to it -- which is what
--- drives the `BufAdd`/`BufEnter` autocmds `state.setup()` registers.
---@param name string
---@return integer bufnr
local function open_named_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

--- Wipe every given buffer (varargs, not a table): a caller nils out a
--- variable the moment its test already closed that buffer, and a table
--- LITERAL with a nil hole (`{a, nil, c}`) is exactly the case `ipairs`
--- silently stops short on -- `c` would never be reached. Varargs don't have
--- that problem: `select('#', ...)` counts every position, nil or not.
---@param ... integer|nil
local function wipe(...)
  local n = select("#", ...)
  for i = 1, n do
    local b = select(i, ...)
    if b then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
end

describe("ui.bindings.keymaps.tabufline.state.setup", function()
  it("is safe to call more than once", function()
    assert.has_no.errors(function()
      state.setup()
      state.setup()
    end)
  end)
end)

describe("ui.bindings.keymaps.tabufline.state buffer tracking", function()
  local a, b, c

  before_each(function()
    vim.cmd("tabnew")
    state.setup()
    a = open_named_buffer("ui-tabufline-spec-a.txt")
    b = open_named_buffer("ui-tabufline-spec-b.txt")
    c = open_named_buffer("ui-tabufline-spec-c.txt")
  end)

  after_each(function()
    wipe(a, b, c)
    pcall(vim.cmd, "tabclose")
  end)

  it("appends each opened buffer to vim.t.bufs, in order", function()
    assert.same({ a, b, c }, vim.t.bufs)
  end)

  it("drops a buffer from vim.t.bufs on BufDelete", function()
    vim.api.nvim_buf_delete(b, { force = true })
    assert.same({ a, c }, vim.t.bufs)
    b = nil -- already wiped; after_each must not wipe it again
  end)

  it("keeps quickfix buffers out of vim.t.bufs", function()
    vim.cmd("copen")
    local qf_buf = vim.api.nvim_get_current_buf()
    assert.equals("qf", vim.bo[qf_buf].filetype)
    assert.is_false(vim.tbl_contains(vim.t.bufs, qf_buf))
    vim.cmd("cclose")
  end)

  describe("move_buf", function()
    it("swaps the current buffer with its right neighbour", function()
      vim.api.nvim_set_current_buf(b) -- middle of { a, b, c }
      state.move_buf(1)
      assert.same({ a, c, b }, vim.t.bufs)
    end)

    it("swaps the current buffer with its left neighbour", function()
      vim.api.nvim_set_current_buf(b)
      state.move_buf(-1)
      assert.same({ b, a, c }, vim.t.bufs)
    end)

    it("wraps from the last slot to the first on a rightward move", function()
      vim.api.nvim_set_current_buf(c) -- last of { a, b, c }
      state.move_buf(1)
      assert.same({ c, b, a }, vim.t.bufs)
    end)

    it("wraps from the first slot to the last on a leftward move", function()
      vim.api.nvim_set_current_buf(a) -- first of { a, b, c }
      state.move_buf(-1)
      assert.same({ c, b, a }, vim.t.bufs)
    end)

    it("does nothing when vim.t.bufs is unset, without throwing", function()
      assert.has_no.errors(function()
        vim.t.bufs = nil
        state.move_buf(1)
      end)
    end)
  end)

  describe("close_buffer", function()
    it("closes the current buffer by default and removes it from vim.t.bufs", function()
      vim.api.nvim_set_current_buf(b)
      state.close_buffer()
      assert.is_false(vim.tbl_contains(vim.t.bufs, b))
      b = nil -- already closed; after_each must not wipe it again
    end)

    it("lands on a remaining listed buffer, not an empty one", function()
      vim.api.nvim_set_current_buf(b)
      state.close_buffer()
      assert.is_true(vim.tbl_contains({ a, c }, vim.api.nvim_get_current_buf()))
      b = nil
    end)

    it("closes an explicit bufnr rather than only the current one", function()
      vim.api.nvim_set_current_buf(c)
      state.close_buffer(a)
      assert.is_false(vim.tbl_contains(vim.t.bufs, a))
      a = nil
    end)

    -- Found live: clicking a tabline "x" while a winfixbuf-locked window (a
    -- file tree sidebar, typically) happens to be the current one raised
    -- E1513 out of the `vim.cmd("b" .. ...)` neighbour-switch below, same
    -- class of problem the goto_buf test right below this one already
    -- covers for goto_buf -- close_buffer just never got the same guard.
    it("does not throw when the current window is winfixbuf-locked", function()
      vim.api.nvim_set_current_buf(b)
      vim.wo.winfixbuf = true
      assert.has_no.errors(function()
        state.close_buffer()
      end)
      vim.wo.winfixbuf = false
      b = nil -- close_buffer already ran on it
    end)
  end)

  describe("goto_buf", function()
    it("switches the current buffer directly", function()
      vim.api.nvim_set_current_buf(a)
      state.goto_buf(c)
      assert.equals(c, vim.api.nvim_get_current_buf())
    end)

    it("does not throw when the current window is winfixbuf-locked", function()
      vim.api.nvim_set_current_buf(a)
      vim.wo.winfixbuf = true
      assert.has_no.errors(function()
        state.goto_buf(b)
      end)
      vim.wo.winfixbuf = false
    end)
  end)

  describe("close_all_bufs", function()
    it("closes every listed buffer in the tab, current one included", function()
      state.close_all_bufs()
      local remaining = vim.t.bufs or {}
      assert.is_false(vim.tbl_contains(remaining, a))
      assert.is_false(vim.tbl_contains(remaining, b))
      assert.is_false(vim.tbl_contains(remaining, c))
      a, b, c = nil, nil, nil
    end)

    it("keeps the current buffer when include_cur_buf is false", function()
      vim.api.nvim_set_current_buf(b)
      state.close_all_bufs(false)
      assert.is_true(vim.tbl_contains(vim.t.bufs, b))
      assert.is_false(vim.tbl_contains(vim.t.bufs, a))
      assert.is_false(vim.tbl_contains(vim.t.bufs, c))
      a, c = nil, nil
    end)
  end)
end)
