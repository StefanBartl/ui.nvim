---@module 'ui.statusline.utils.idle'
--- Idle-detection primitive for "Zweitverwertung" segments
--- (IDEEN-statusline.md's "Idle-Erweiterung nach N Sekunden Inaktivität"):
--- `CursorHold`/`CursorHoldI` mark the editor idle -- Neovim fires those
--- after `updatetime` ms with no input, which is exactly the "N Sekunden
--- Inaktivität" threshold the idea asks for, made configurable for free
--- since it is the user's own `updatetime`, not a value this module
--- invents. Any cursor movement, mode change or entering/leaving insert
--- mode marks it active again.
---
--- `wrap()` is the entry point most segments need: render nothing until
--- idle, then render normally, hidden again on the next keystroke.

local Autocmd = require("lib.nvim.bindings.autocmd")

local M = {}

local is_idle_state = false
local registered = false

---@return nil
local function ensure_autocmds()
  if registered then
    return
  end
  registered = true

  local group = Autocmd.group("UiStatuslineIdle", true)

  Autocmd.create({ "CursorHold", "CursorHoldI" }, function()
    is_idle_state = true
    vim.cmd("redrawstatus")
  end, {
    group = group,
    desc = "ui.statusline: mark the editor idle for idle-only segments",
  })

  Autocmd.create({ "CursorMoved", "CursorMovedI", "InsertEnter", "ModeChanged" }, function()
    is_idle_state = false
    vim.cmd("redrawstatus")
  end, {
    group = group,
    desc = "ui.statusline: mark the editor active again, hiding idle-only segments",
  })
end

---Whether the editor is currently considered idle (no input since the last
---`CursorHold`/`CursorHoldI`).
---@return boolean
function M.is_idle()
  ensure_autocmds()
  return is_idle_state
end

---Wrap a segment so it renders "" until the editor has been idle, and hides
---again on the very next movement/keystroke.
---@param segment_fn fun(): string
---@return fun(): string
function M.wrap(segment_fn)
  return function()
    if not M.is_idle() then
      return ""
    end
    return segment_fn()
  end
end

return M
