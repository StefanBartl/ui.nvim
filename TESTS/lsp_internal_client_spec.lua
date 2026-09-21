-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Regression coverage for lsp.nvim's `code_actions.gitsigns` client
--- (`lsp.nvim-gitsigns`): an in-process client with no process and no
--- language, attached to every buffer gitsigns tracks regardless of
--- filetype. Before this fix, ui.nvim read `vim.lsp.get_clients()` directly
--- in two places and could not tell it apart from a real language server --
--- the statusline's LSP label showed "lsp.nvim-gitsigns" instead of the
--- actual server (or instead of staying blank on a buffer with no server
--- at all), and the file-icon-when-attached variant lit up on every
--- gitsigns-tracked buffer. lsp.nvim's own fix (`9b60d98`) only covers its
--- own winbar and `:Lsp stop`/`restart`; ui.nvim has to apply the same
--- "lsp.nvim-*" contract (`ui.util.lsp`) independently, since it must not
--- depend on lsp.nvim.

describe("ui.util.lsp.is_internal_client", function()
  local is_internal = require("ui.util.lsp").is_internal_client

  it("recognizes lsp.nvim's in-process client prefix", function()
    assert.is_true(is_internal({ name = "lsp.nvim-gitsigns" }))
    assert.is_true(is_internal({ name = "lsp.nvim-anything-else" }))
  end)

  it("does not flag a real language server", function()
    assert.is_false(is_internal({ name = "lua_ls" }))
    assert.is_false(is_internal({ name = "ts_ls" }))
  end)
end)

describe("bug: statusline LSP label showed lsp.nvim's own in-process client", function()
  local primitives = require("ui.statusline.utils.primitives")
  local _ = vim.lsp -- see bugfix_regressions_spec.lua for why this read is needed first

  it("skips an internal client and shows the real server behind it", function()
    -- M.lsp() only names the client past 100 columns (see M.lsp's own gate).
    local original_columns = vim.o.columns
    vim.o.columns = 200

    local original = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return {
        {
          name = "lsp.nvim-gitsigns",
          attached_buffers = { [vim.api.nvim_get_current_buf()] = true },
        },
        {
          name = "lua_ls",
          attached_buffers = { [vim.api.nvim_get_current_buf()] = true },
        },
      }
    end

    local out = primitives.lsp()
    vim.lsp.get_clients = original
    vim.o.columns = original_columns

    assert.is_true(out:find("lua_ls", 1, true) ~= nil, out)
    assert.is_nil(out:find("lsp.nvim-gitsigns", 1, true), out)
  end)

  it("renders blank when only an internal client is attached", function()
    local original = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return {
        {
          name = "lsp.nvim-gitsigns",
          attached_buffers = { [vim.api.nvim_get_current_buf()] = true },
        },
      }
    end

    local out = primitives.lsp()
    vim.lsp.get_clients = original

    assert.are.equal("", out)
  end)
end)

describe("bug: file-icon-when-attached lit up on lsp.nvim's in-process client", function()
  local devicons = require("ui.statusline.modules.file_icons.devicons")

  -- file_icon_segment_lsp() returns "" for an unnamed buffer regardless of
  -- clients, so a named scratch buffer is needed to isolate the client check.
  local buf
  before_each(function()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "_lsp_icon_test.lua")
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("stays blank when the only client attached is internal", function()
    local original = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return { { name = "lsp.nvim-gitsigns" } }
    end

    local out = devicons.file_icon_segment_lsp()
    vim.lsp.get_clients = original

    assert.are.equal("", out)
  end)

  it("renders when a real server is also attached", function()
    local original = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return { { name = "lsp.nvim-gitsigns" }, { name = "lua_ls" } }
    end

    local out = devicons.file_icon_segment_lsp()
    vim.lsp.get_clients = original

    assert.is_true(#out > 0, out)
  end)
end)
