---@module 'ui.bindings.keymaps'
--- Buffer/tab navigation and the theme-toggle keymap, through
--- `lib.nvim.bindings.keymap.register()` -- this ecosystem's own mechanism
--- for "a plugin ships named, overridable actions", the same shape
--- `my.nvim`'s `bindings/keymaps.lua` already uses. `opts` is `register()`'s
--- own `user` table, handed straight through, unwrapped: absent (`nil`,
--- `{}`, or `true`) binds every action below at its shipped default,
--- `false` binds none of them, `{ next = "<C-Right>", close = false }`
--- remaps one action and drops another, leaving the rest untouched. No
--- `all`/`buffers`/`tabs`/`theme` group flags on top of that -- an earlier
--- version of this module invented its own `{ all = true, keys = {...} }`
--- shape instead of just being another `register()` caller, which meant a
--- host had to write `{ all = true }` to get anything at all instead of
--- getting every default for free the way `register()` -- and every other
--- plugin here that uses it -- already behaves.

local notify = require("lib.nvim.notify").create("[ui.bindings.keymaps]")
local keymap = require("lib.nvim.bindings.keymap")
local lazy = require("lib.lua.lazy")

local custom_tabufline = lazy.require("ui.bindings.keymaps.tabufline")
local tabufline_state = lazy.require("ui.bindings.keymaps.tabufline.state")
local move_buf_tab = lazy.require("lib.nvim.buf_win_tab.move_buffer_to_tab")

local M = {}

---@nodiscard
---@return integer
local function get_count()
  return vim.v.count1
end

--- Register every buffer/tab/theme action.
---
--- `opts == false` is handled before reaching `register()` at all, same as
--- `my.nvim`'s own `bindings/keymaps.lua`: `tabufline_state.setup()` below
--- still has to run for the tabline renderer's `vim.t.bufs` bookkeeping even
--- when a host wants no keymaps bound, and `register()` would otherwise do
--- the work of resolving and skip-recording seven actions for nothing.
---@param opts Ui.Keymaps.Keys|boolean|nil
---@return nil
function M.setup(opts)
  if opts == false then
    return
  end

  -- Every action below reads or writes vim.t.bufs (via custom_tabufline);
  -- without this, that list is never populated and each one silently does
  -- nothing. See tabufline/state.lua's doc comment for why.
  tabufline_state.setup()

  local ok, err = pcall(keymap.register, "ui.nvim", {
    order = {
      "next",
      "prev",
      "close",
      "move_right",
      "move_left",
      "move_to_tab",
      "toggle_theme",
      "theme_picker",
    },
    actions = {
      next = {
        default = "<Tab>",
        mode = "n",
        desc = "next buffer",
        rhs = function()
          local ok2, err2 = pcall(custom_tabufline.move_next_n, get_count())
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Buffer navigation failed: " .. tostring(err2))
          end
        end,
      },
      prev = {
        default = "<S-Tab>",
        mode = "n",
        desc = "previous buffer",
        rhs = function()
          local ok2, err2 = pcall(custom_tabufline.move_prev_n, get_count())
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Buffer navigation failed: " .. tostring(err2))
          end
        end,
      },
      close = {
        default = "<leader>bc",
        mode = "n",
        desc = "close buffer(s), count-aware",
        rhs = function()
          local ok2, err2 = pcall(custom_tabufline.close_n_buffers, get_count())
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Buffer close failed: " .. tostring(err2))
          end
        end,
      },
      move_right = {
        default = "<leader>tr",
        mode = "n",
        desc = "move buffer one position right in the tabline",
        rhs = function()
          local ok2, err2 = pcall(tabufline_state.move_buf, 1)
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Move tab right failed: " .. tostring(err2))
          end
        end,
      },
      move_left = {
        default = "<leader>tl",
        mode = "n",
        desc = "move buffer one position left in the tabline",
        rhs = function()
          local ok2, err2 = pcall(tabufline_state.move_buf, -1)
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Move tab left failed: " .. tostring(err2))
          end
        end,
      },
      move_to_tab = {
        default = "<leader>tt",
        mode = "n",
        desc = "move current buffer into a new tab",
        rhs = function()
          local ok2, err2 = pcall(move_buf_tab)
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Move buffer to tab failed: " .. tostring(err2))
          end
        end,
      },
      toggle_theme = {
        default = "<leader>ut",
        mode = "n",
        desc = "toggle between the two configured themes",
        rhs = function()
          local ok2, err2 = pcall(require("ui.bindings.usrcmds.themes").toggle_theme)
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Theme toggle failed: " .. tostring(err2))
          end
        end,
      },
      theme_picker = {
        default = "<leader>uP",
        mode = "n",
        desc = "open the visual theme picker (live preview)",
        rhs = function()
          local ok2, err2 = pcall(require("ui.bindings.usrcmds.themes.picker").open)
          if not ok2 then
            notify.warn("[ui.bindings.keymaps] Theme picker failed: " .. tostring(err2))
          end
        end,
      },
    },
  }, opts)

  if not ok then
    notify.error("[ui.bindings.keymaps] setup failed: " .. tostring(err))
  end
end

return M
