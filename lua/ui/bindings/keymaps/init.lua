---@module 'ui.bindings.keymaps'
--- Mappings using lib.map for consistency

local notify = require("lib.nvim.notify").create("[ui.bindings.keymaps]")

local M = {}

-- Use lib for all mappings
local map = require("lib.nvim.bindings.keymap")
local lazy = require("lib.lua.lazy")

-- Lazy-load heavy modules
local custom_tabufline = lazy.require("ui.bindings.keymaps.tabufline")
local tabufline_state = lazy.require("ui.bindings.keymaps.tabufline.state")
local move_buf_tab = lazy.require("lib.nvim.buf_win_tab.move_buffer_to_tab")

---@nodiscard
---@return integer
local function get_count()
  return vim.v.count1
end

-- ---------------------------------------------------------------------------
-- Buffers
-- ---------------------------------------------------------------------------
---@return nil
local function attach_buffers()
  -- Every mapping below reads or writes vim.t.bufs (via custom_tabufline);
  -- without this, that list is never populated and each one silently does
  -- nothing. See tabufline/state.lua's doc comment for why.
  tabufline_state.setup()

  -- <Tab> -> next buffer, supports count
  map("n", "<Tab>", function()
    local cnt = get_count()
    local ok, err = pcall(custom_tabufline.move_next_n, cnt)
    if not ok then
      notify.warn("[ui.bindings.keymaps] Buffer navigation failed: " .. tostring(err))
    end
  end, { desc = "[Buffers] Next" })

  -- <S-Tab> -> previous buffer, supports count
  map("n", "<S-Tab>", function()
    local cnt = get_count()
    local ok, err = pcall(custom_tabufline.move_prev_n, cnt)
    if not ok then
      notify.warn("[ui.bindings.keymaps] Buffer navigation failed: " .. tostring(err))
    end
  end, { desc = "[Buffers] Prev" })

  -- <leader>bc -> close buffers with count support
  map("n", "<leader>bc", function()
    local cnt = get_count()
    local ok, err = pcall(custom_tabufline.close_n_buffers, cnt)
    if not ok then
      notify.warn("[ui.bindings.keymaps] Buffer close failed: " .. tostring(err))
    end
  end, { desc = "[Buffers] Close" })
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------
---@return nil
local function attach_tabs()
  -- move_buf() also reads/writes vim.t.bufs; idempotent, so no harm if
  -- attach_buffers() already called this in the same setup() run.
  tabufline_state.setup()

  map("n", "<leader>tr", function()
    local ok, err = pcall(tabufline_state.move_buf, 1)
    if not ok then
      notify.warn("[ui.bindings.keymaps] Move tab right failed: " .. tostring(err))
    end
  end, { desc = "[Tabs] Move tab right" })

  map("n", "<leader>tl", function()
    local ok, err = pcall(tabufline_state.move_buf, -1)
    if not ok then
      notify.warn("[ui.bindings.keymaps] Move tab left failed: " .. tostring(err))
    end
  end, { desc = "[Tabs] Move tab left" })

  map("n", "<leader>tt", function()
    local ok, err = pcall(move_buf_tab)
    if not ok then
      notify.warn("[ui.bindings.keymaps] Move buffer to tab failed: " .. tostring(err))
    end
  end, { desc = "[Tabs] Move current buffer to new tab" })
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
---@param opts Ui.Keymaps.Modules
---@return nil
function M.setup(opts)
  opts = opts or {}

  if opts.all or opts.buffers then
    local ok, err = pcall(attach_buffers)
    if not ok then
      notify.error("[ui.bindings.keymaps] Buffer mappings failed: " .. tostring(err))
    end
  end

  if opts.all or opts.tabs then
    local ok, err = pcall(attach_tabs)
    if not ok then
      notify.error("[ui.bindings.keymaps] Tab mappings failed: " .. tostring(err))
    end
  end
end

return M
