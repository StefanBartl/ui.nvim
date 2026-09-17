-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.lsp.symbols.treesitter` -- the statusline's
--- breadcrumb fallback for buffers with no LSP attached, against a real
--- parsed tree.
---
--- It was dead in every live session and nothing noticed. The node was
--- resolved through `nvim-treesitter.ts_utils`, and nvim-treesitter's `main`
--- branch removed that module -- so the `pcall` answered "absent" on every
--- call and `symbol_context_ts()` returned nil forever. The breadcrumb
--- simply had no fallback, with no error anywhere to say so.
---
--- A unit test could not have caught it: with no node the function returns
--- nil, which is also what it correctly returns when there is nothing to
--- say. So these assertions use a real buffer with a real parsed tree and
--- check that a chain actually comes back.
---
--- Same defect and same fix as `my.nvim@c622695` in the sibling breadcrumb
--- pipeline -- which is where the spec shape below comes from too.

local ts_symbols = require("ui.statusline.modules.lsp.symbols.treesitter")

describe("ui.statusline.modules.lsp.symbols.treesitter over a real tree", function()
  local SRC = {
    "local M = {}", -- 1
    "", -- 2
    "function M.run(a)", -- 3
    "  local x = a + 1", -- 4
    "  return x", -- 5
    "end", -- 6
    "", -- 7
    "local Klass = {}", -- 8
    "", -- 9
    "function Klass:method()", -- 10
    "  return self.field", -- 11
    "end", -- 12
    "", -- 13
    "return M", -- 14
  }

  --- Put the cursor somewhere in a freshly parsed Lua buffer.
  ---@param line integer
  ---@param col integer
  local function at(line, col)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, SRC)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "lua"
    vim.treesitter.start(buf, "lua")
    -- Headless never redraws, so nothing would parse the tree for us.
    vim.treesitter.get_parser(buf, "lua"):parse()
    vim.api.nvim_win_set_cursor(0, { line, col })
  end

  it("does not need nvim-treesitter", function()
    -- The module the old implementation required. Absent here, exactly as it
    -- now is in a real session -- and the assertions below still pass.
    assert.is_false((pcall(require, "nvim-treesitter.ts_utils")))
  end)

  it("names the enclosing function", function()
    at(4, 9)
    local ctx = ts_symbols.symbol_context_ts()
    assert.is_not_nil(ctx)
    assert.is_true(ctx:find("run", 1, true) ~= nil)
  end)

  it("names the enclosing method", function()
    at(11, 10)
    local ctx = ts_symbols.symbol_context_ts()
    assert.is_not_nil(ctx)
    assert.is_true(ctx:find("method", 1, true) ~= nil)
  end)

  it("renders a function node as a call", function()
    at(4, 9)
    local ctx = ts_symbols.symbol_context_ts()
    assert.is_true(ctx:find("()", 1, true) ~= nil)
  end)

  it("returns nil in a buffer with no parser rather than erroring", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "nothing to parse here" })
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = ""
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local ok, ctx = pcall(ts_symbols.symbol_context_ts)
    assert.is_true(ok)
    assert.is_nil(ctx)
  end)
end)
