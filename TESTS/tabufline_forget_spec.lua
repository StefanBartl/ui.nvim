-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.bindings.keymaps.tabufline.state.forget_buffer` -- the repair for a
--- buffer that left a tab without being deleted.
---
--- `lib.nvim.buf_win_tab.move_buffer_to_tab`, which this plugin's
--- "move current buffer into a new tab" keymap calls, moves a buffer
--- across tabs without deleting it. `BufEnter` adds it to the destination
--- tab's `vim.t.bufs`, but nothing removes it from the source: only
--- `BufDelete` does that, and the buffer is very much alive. The result
--- was a tabline chip in the old tab for a buffer no longer in it, for the
--- rest of the session (cross-feature report, finding D1).
---
--- lib.nvim cannot fix it -- `vim.t.bufs` is this plugin's bookkeeping and
--- the dependency only points one way -- so the repair lives here, and
--- these are the cases it has to get right.

local state = require("ui.bindings.keymaps.tabufline.state")

describe("ui.bindings.keymaps.tabufline.state.forget_buffer", function()
  local seq = 0

  ---@return integer
  local function listed_buf()
    seq = seq + 1
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, ("/tmp/forget_spec_%d.lua"):format(seq))
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = buf })
    return buf
  end

  before_each(function()
    state.setup()
  end)

  it("drops the named buffer from that tab's list", function()
    local tab = vim.api.nvim_get_current_tabpage()
    local a = listed_buf()
    local b = listed_buf()

    assert.is_true(vim.tbl_contains(vim.t[tab].bufs, a))
    state.forget_buffer(a, tab)

    assert.is_false(vim.tbl_contains(vim.t[tab].bufs, a))
    assert.is_true(vim.tbl_contains(vim.t[tab].bufs, b), "the other buffer is untouched")
  end)

  -- It runs after a move, and a move can be repeated or retried.
  it("is idempotent", function()
    local tab = vim.api.nvim_get_current_tabpage()
    local a = listed_buf()

    state.forget_buffer(a, tab)
    local after_first = vim.deepcopy(vim.t[tab].bufs)
    state.forget_buffer(a, tab)

    assert.same(after_first, vim.t[tab].bufs)
  end)

  it("ignores a buffer the tab never listed", function()
    local tab = vim.api.nvim_get_current_tabpage()
    listed_buf()
    local before = vim.deepcopy(vim.t[tab].bufs)

    state.forget_buffer(999999, tab)

    assert.same(before, vim.t[tab].bufs)
  end)

  -- The caller captures the source tab before the move, and the move can
  -- close it -- `move_buffer_to_tab` replaces the buffer in every window of
  -- the source tab, and a tab with no windows left is gone.
  it("does not raise for a tabpage that no longer exists", function()
    local a = listed_buf()
    assert.has_no.errors(function()
      state.forget_buffer(a, 999999)
    end)
  end)

  it("does not raise before setup() has populated vim.t.bufs", function()
    vim.api.nvim_command("tabnew")
    local fresh = vim.api.nvim_get_current_tabpage()
    vim.t[fresh].bufs = nil

    assert.has_no.errors(function()
      state.forget_buffer(1, fresh)
    end)

    vim.api.nvim_command("tabclose")
  end)
end)
