---@module 'ui.bindings.usrcmds.themes.picker'
--- Visual theme picker: every colorscheme `ui.theme.list_themes()` knows
--- about, in a `ui.kit` floating list. The theme under the cursor
--- applies live as the list is navigated -- j/k, arrows, mouse wheel, all of
--- it fires `CursorMoved`, which is all this needs to hook. Confirming
--- (`<CR>`) keeps the highlighted theme; cancelling (`<Esc>`, `q`, a click
--- outside) restores whatever theme was active before the picker opened.
---
--- Deliberately bypasses kit.select's `respect_override`: a foreign picker
--- backend (telescope-ui-select, fzf-lua, ...) has no way to report cursor
--- movement back here, and live preview -- the one thing `:UI theme
--- <Tab-complete>` could never do -- is the entire point of this picker.

local theme = require("ui.bindings.usrcmds.themes")
local select = require("ui.kit.select")
local autocmd = require("lib.nvim.bindings.autocmd")
local debounce = require("lib.nvim.debounce")

local api = vim.api

--- Matches `lib.nvim.ui.kit.picker`'s own debounce for equivalent per-
--- keystroke work: a `:colorscheme` switch re-runs every `ColorScheme`
--- autocmd in the session (transparency, statusline/tabline highlight
--- caches, ...), so holding `j` or spinning the scroll wheel through a long
--- theme list would otherwise fire a full reload per intermediate row.
local PREVIEW_DEBOUNCE_MS = 80

local M = {}

---@internal
---@param themes string[]
---@param current string|nil
---@return integer|nil
local function index_of(themes, current)
  if not current then
    return nil
  end
  for i, name in ipairs(themes) do
    if name == current then
      return i
    end
  end
  return nil
end

--- Open the picker. No-op with no error when there is nothing to pick from
--- (mirrors `kit.select`'s own empty-list contract).
---@return nil
function M.open()
  local themes = theme.list_themes()
  if #themes == 0 then
    return
  end

  local original = theme.get_current_theme()

  local surf = select.open({
    items = themes,
    title = "Theme",
    initial_index = index_of(themes, original),
    on_select = function(name)
      theme.load_theme(name)
    end,
    on_cancel = function()
      -- `original` is nil only when no `:colorscheme` was ever issued this
      -- session -- unusual (a real host sets one at startup) but not
      -- impossible. There is no "unset" colorscheme to fall back to in that
      -- case, so cancelling deliberately leaves the last-previewed theme
      -- applied rather than pretending there is something to restore.
      if original then
        theme.load_theme(original)
      end
    end,
  })

  -- nil means: delegated to a foreign vim.ui.select override, cancelled
  -- before a window ever opened (empty list), or the float failed to open.
  -- Nothing here to attach a preview autocmd to in any of those cases.
  if not surf then
    return
  end

  local preview = debounce.new(function(name)
    theme.load_theme(name)
  end, PREVIEW_DEBOUNCE_MS)

  autocmd.create("CursorMoved", function()
    if not api.nvim_win_is_valid(surf.winid) then
      return
    end
    local row = api.nvim_win_get_cursor(surf.winid)[1]
    local name = themes[row]
    if name then
      preview.call(name)
    end
  end, {
    group = autocmd.group("ui_theme_picker_preview", true),
    buffer = surf.bufnr,
    desc = "ui.nvim: live-preview the theme under the picker's cursor",
  })

  -- Cancel a pending preview before it can fire after the float (and thus
  -- `on_select`/`on_cancel` above) has already settled the final theme --
  -- registered after kit.select's own on_close listeners, so this runs
  -- before their deferred cancel-check (see that module's own comment on
  -- why it defers one tick).
  surf:on_close(preview.cancel)
end

return M
