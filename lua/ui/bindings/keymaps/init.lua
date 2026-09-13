---@module 'ui.bindings.keymaps'
--- Buffer/tab navigation and the theme-toggle keymap, through
--- `lib.nvim.bindings.keymap.register()` -- the ecosystem's own mechanism
--- for "a plugin ships named, overridable actions" (see that module's own
--- doc comment), not a bespoke one. Three registrations under the plugin
--- name `"ui.nvim"`, one per surface (`opts.surface =
--- "buffers"`/`"tabs"`/`"theme"`) so `:checkhealth`/a generated bindings
--- page can tell the groups apart the way `ui.setup`'s own
--- `buffers`/`tabs`/`theme` toggles already do.
---
--- `opts.keys` is the override table `register()`'s `user` parameter expects:
--- `{ next = "<C-Right>", close = false }` remaps `next` and drops `close`,
--- leaving every other default untouched. An unknown name in it (a typo, or
--- a tabs-surface name reaching the buffers registration) is reported by
--- `register()` itself, not silently ignored -- which is why the table is
--- filtered per surface below rather than handed to all three calls whole:
--- an override meant for a *different* surface would otherwise warn as
--- unknown on this one.
---
--- `toggle_theme` moved here 2026-09-13 from a host-side keymap file
--- (`bindings/mappings/nvchad.lua`, a leftover name from before this plugin
--- had its own `:UI theme`/`:UI toggle` commands to bind a key to) -- the
--- key itself is this plugin's own concern now, configurable the same way
--- as every other action here, not a fixed `<leader>nvt` a host hand-wired.

local notify = require("lib.nvim.notify").create("[ui.bindings.keymaps]")

local M = {}

local keymap = require("lib.nvim.bindings.keymap")
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

--- Action names that belong to the "buffers" surface -- `filter_keys` uses
--- this to keep a "tabs" override out of the "buffers" registration's user
--- table (and vice versa via `TAB_ACTIONS`), so neither call reports the
--- other surface's own valid override as an unknown action.
---@type table<string, true>
local BUFFER_ACTIONS = { next = true, prev = true, close = true }

---@type table<string, true>
local TAB_ACTIONS = { move_right = true, move_left = true, move_to_tab = true }

---@type table<string, true>
local THEME_ACTIONS = { toggle_theme = true }

---@param keys Ui.Keymaps.Keys|nil
---@param allowed table<string, true>
---@return table|nil
local function filter_keys(keys, allowed)
  if type(keys) ~= "table" then
    return keys
  end
  local out = {}
  for name, override in pairs(keys) do
    if allowed[name] then
      out[name] = override
    end
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Buffers
-- ---------------------------------------------------------------------------
---@param keys Ui.Keymaps.Keys|nil
---@return nil
local function attach_buffers(keys)
  -- Every action below reads or writes vim.t.bufs (via custom_tabufline);
  -- without this, that list is never populated and each one silently does
  -- nothing. See tabufline/state.lua's doc comment for why.
  tabufline_state.setup()

  keymap.register("ui.nvim", {
    order = { "next", "prev", "close" },
    actions = {
      next = {
        default = "<Tab>",
        mode = "n",
        desc = "next buffer",
        rhs = function()
          local ok, err = pcall(custom_tabufline.move_next_n, get_count())
          if not ok then
            notify.warn("[ui.bindings.keymaps] Buffer navigation failed: " .. tostring(err))
          end
        end,
      },
      prev = {
        default = "<S-Tab>",
        mode = "n",
        desc = "previous buffer",
        rhs = function()
          local ok, err = pcall(custom_tabufline.move_prev_n, get_count())
          if not ok then
            notify.warn("[ui.bindings.keymaps] Buffer navigation failed: " .. tostring(err))
          end
        end,
      },
      close = {
        default = "<leader>bc",
        mode = "n",
        desc = "close buffer(s), count-aware",
        rhs = function()
          local ok, err = pcall(custom_tabufline.close_n_buffers, get_count())
          if not ok then
            notify.warn("[ui.bindings.keymaps] Buffer close failed: " .. tostring(err))
          end
        end,
      },
    },
  }, filter_keys(keys, BUFFER_ACTIONS), { surface = "buffers" })
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------
---@param keys Ui.Keymaps.Keys|nil
---@return nil
local function attach_tabs(keys)
  -- move_buf() also reads/writes vim.t.bufs; idempotent, so no harm if
  -- attach_buffers() already called this in the same setup() run.
  tabufline_state.setup()

  keymap.register("ui.nvim", {
    order = { "move_right", "move_left", "move_to_tab" },
    actions = {
      move_right = {
        default = "<leader>tr",
        mode = "n",
        desc = "move buffer one position right in the tabline",
        rhs = function()
          local ok, err = pcall(tabufline_state.move_buf, 1)
          if not ok then
            notify.warn("[ui.bindings.keymaps] Move tab right failed: " .. tostring(err))
          end
        end,
      },
      move_left = {
        default = "<leader>tl",
        mode = "n",
        desc = "move buffer one position left in the tabline",
        rhs = function()
          local ok, err = pcall(tabufline_state.move_buf, -1)
          if not ok then
            notify.warn("[ui.bindings.keymaps] Move tab left failed: " .. tostring(err))
          end
        end,
      },
      move_to_tab = {
        default = "<leader>tt",
        mode = "n",
        desc = "move current buffer into a new tab",
        rhs = function()
          local ok, err = pcall(move_buf_tab)
          if not ok then
            notify.warn("[ui.bindings.keymaps] Move buffer to tab failed: " .. tostring(err))
          end
        end,
      },
    },
  }, filter_keys(keys, TAB_ACTIONS), { surface = "tabs" })
end

-- ---------------------------------------------------------------------------
-- Theme
-- ---------------------------------------------------------------------------
---@param keys Ui.Keymaps.Keys|nil
---@return nil
local function attach_theme(keys)
  keymap.register("ui.nvim", {
    order = { "toggle_theme" },
    actions = {
      toggle_theme = {
        default = "<leader>ut",
        mode = "n",
        desc = "toggle between the two configured themes",
        rhs = function()
          local ok, err = pcall(require("ui.bindings.usrcmds.themes").toggle_theme)
          if not ok then
            notify.warn("[ui.bindings.keymaps] Theme toggle failed: " .. tostring(err))
          end
        end,
      },
    },
  }, filter_keys(keys, THEME_ACTIONS), { surface = "theme" })
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
---@param opts Ui.Keymaps.Modules
---@return nil
function M.setup(opts)
  opts = opts or {}

  if opts.all or opts.buffers then
    local ok, err = pcall(attach_buffers, opts.keys)
    if not ok then
      notify.error("[ui.bindings.keymaps] Buffer mappings failed: " .. tostring(err))
    end
  end

  if opts.all or opts.tabs then
    local ok, err = pcall(attach_tabs, opts.keys)
    if not ok then
      notify.error("[ui.bindings.keymaps] Tab mappings failed: " .. tostring(err))
    end
  end

  if opts.all or opts.theme then
    local ok, err = pcall(attach_theme, opts.keys)
    if not ok then
      notify.error("[ui.bindings.keymaps] Theme mapping failed: " .. tostring(err))
    end
  end
end

return M
