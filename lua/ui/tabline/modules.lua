---@module 'ui.tabline.modules'
--- The four built-in tabline segments -- `tree_offset`, `buffers`, `tabs`,
--- `btns` -- each `fun(cfg: Ui.Tabline.Config): string`, ported from
--- `nvchad.tabufline.modules`. Kept in one file rather than one per segment
--- (unlike the statusline's `modules/` tree): all four share `cfg` and
--- `available_space()`, and NvChad's own upstream keeps them together too.

local utils = require("ui.tabline.utils")
local api = vim.api

local M = {}

---@param ft string
---@return integer # 0 when no window in the current tab has this filetype
local function filetree_window_width(ft)
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(win)].filetype == ft then
      return api.nvim_win_get_width(win)
    end
  end
  return 0
end

--- Columns left over for buffer chips once every other module in `cfg.order`
--- has rendered -- "buffers" itself is skipped so it does not measure its
--- own, not-yet-decided width. Resolves `cfg.modules` overrides the same way
--- `ui.tabline.render.generate()` does, so a custom module in `order`
--- affects the space `buffers()` sees too.
---@param cfg Ui.Tabline.Config
---@return integer
local function available_space(cfg)
  local str = {}
  for _, key in ipairs(cfg.order or {}) do
    if key ~= "buffers" then
      local mod = (cfg.modules and cfg.modules[key]) or M[key]
      if type(mod) == "function" then
        local ok, rendered = pcall(mod, cfg)
        str[#str + 1] = ok and rendered or ""
      end
    end
  end

  local width = api.nvim_eval_statusline(table.concat(str), { use_tabline = true }).width
  return vim.o.columns - width
end

--- A blank strip the width of the file-tree window, so the buffer chips
--- start after it instead of drawing underneath -- `filetree.nvim`'s own
--- window by default (`cfg.tree_offset_ft`), any filetype otherwise.
---@param cfg Ui.Tabline.Config
---@return string
function M.tree_offset(cfg)
  local ft = cfg.tree_offset_ft or "filetree"
  local width = filetree_window_width(ft)
  if width == 0 then
    return ""
  end
  return "%#UiTbTreeOffset#" .. string.rep(" ", width) .. "%#UiTbFill#"
end

--- The buffer chip list. Drops chips from the front once the list would
--- overflow the columns left by the other modules, keeping the current
--- buffer visible -- ported from `nvchad.tabufline.modules.buffers`'s own
--- overflow handling.
---@param cfg Ui.Tabline.Config
---@return string
function M.buffers(cfg)
  local bufwidth = cfg.bufwidth or 21
  local bufs = vim.tbl_filter(api.nvim_buf_is_valid, vim.t.bufs or {})
  vim.t.bufs = bufs

  local chips = {}
  local seen_current = false
  local cur = api.nvim_get_current_buf()

  for i, bufnr in ipairs(bufs) do
    if (#chips + 1) * bufwidth > available_space(cfg) then
      if seen_current then
        break
      end
      table.remove(chips, 1)
    end

    seen_current = seen_current or (cur == bufnr)
    chips[#chips + 1] = utils.style_buf(bufnr, i, bufwidth)
  end

  return table.concat(chips) .. "%#UiTbFill#%="
end

--- Tab-page buttons: one per tab plus a "new tab" and a "collapse" button --
--- rendered only when there is more than one tab, same as NvChad's own.
---@param cfg Ui.Tabline.Config
---@return string
function M.tabs(_cfg)
  local total = vim.fn.tabpagenr("$")
  if total <= 1 then
    return ""
  end

  utils.register_click_handlers()

  if vim.g.ui_tb_tabs_toggled == 1 then
    return utils.btn(" 󰅁 ", "Title", "ToggleTabs")
  end

  local current = vim.fn.tabpagenr()
  local buttons = {}
  for nr = 1, total do
    local hl = (nr == current) and "TabOn" or "TabOff"
    buttons[#buttons + 1] = utils.btn(" " .. nr .. " ", hl, "GotoTab", nr)
  end

  return utils.btn(" 󰐕 ", "TabNewBtn", "NewTab")
    .. utils.btn(" TABS ", "Title", "ToggleTabs")
    .. table.concat(buttons)
end

--- The two right-aligned buttons: theme toggle, close all buffers.
---@param cfg Ui.Tabline.Config
---@return string
function M.btns(_cfg)
  utils.register_click_handlers()
  return utils.btn("  ", "ThemeToggleBtn", "ToggleTheme")
    .. utils.btn(" 󰅖 ", "CloseAllBufsBtn", "CloseAllBufs")
end

return M
