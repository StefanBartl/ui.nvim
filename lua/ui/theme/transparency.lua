---@module 'ui.theme.transparency'
--- Background transparency for the groups this plugin's own frame draws: the
--- editor body, statusline, tabline, winbar.
---
--- Deliberately NOT full-UI transparency -- every plugin's floating windows,
--- popup menus, and so on. That was base46's job (recompiling hundreds of
--- highlight groups per theme); replicating it here would make this plugin a
--- second copy of whatever floating-window highlighting each of those
--- plugins already owns, which is exactly the "frame, not content" line this
--- repository's README already draws elsewhere. A plugin's own float
--- highlighting stays that plugin's job.

local M = {}

---@type string[]
local GROUPS = {
  "Normal",
  "NormalNC",
  "StatusLine",
  "StatusLineNC",
  "WinBar",
  "WinBarNC",
  "TabLine",
  "TabLineFill",
  "TabLineSel",
}

--- The bg each group had before transparency was turned on, so turning it
--- off restores the theme's own value rather than guessing at one.
---@type table<string, string|integer|nil>
local _saved_bg = {}
local _enabled = false

---@return boolean
function M.is_enabled()
  return _enabled
end

---@param enabled boolean
---@return nil
function M.set(enabled)
  if enabled == _enabled then
    return
  end
  _enabled = enabled

  for _, group in ipairs(GROUPS) do
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if ok then
      if enabled then
        _saved_bg[group] = hl.bg
        hl.bg = nil
      else
        hl.bg = _saved_bg[group]
        _saved_bg[group] = nil
      end
      pcall(vim.api.nvim_set_hl, 0, group, hl)
    end
  end
end

---@return boolean new_state
function M.toggle()
  M.set(not _enabled)
  return _enabled
end

--- A `:colorscheme` switch re-applies every group above with the new theme's
--- own background -- the exact failure mode ROADMAP.md's "Theme" section
--- calls out ("a theme change leaving half the statusline in the old
--- palette"). Re-strip immediately after, rather than leaving transparency
--- silently lost until the next manual toggle.
--- Through `hl.persist`, which adds the `OptionSet background` case this
--- block was missing: a light/dark flip repaints the same groups and would
--- have left transparency off until the next explicit toggle.
require("lib.nvim.ui.hl").persist(function()
  if _enabled then
    _enabled = false
    M.set(true)
  end
end, { name = "UiTransparencyReapply", immediate = false })

return M
