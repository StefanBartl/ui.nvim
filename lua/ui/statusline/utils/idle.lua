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
-- Counts active->idle transitions: one number per idle phase, so a payload
-- that does real work (`idle_git_log`'s `git log`) can cache "already done
-- for this phase" without its own CursorHold wiring.
local phase_counter = 0

---@return nil
local function ensure_autocmds()
  if registered then
    return
  end
  registered = true

  local group = Autocmd.group("UiStatuslineIdle", true)

  Autocmd.create({ "CursorHold", "CursorHoldI" }, function()
    if not is_idle_state then
      is_idle_state = true
      phase_counter = phase_counter + 1
      vim.cmd("redrawstatus")
    end
  end, {
    group = group,
    desc = "ui.statusline: mark the editor idle for idle-only segments",
  })

  -- CursorMoved/CursorMovedI fire on every single cursor step (holding a
  -- movement key, scrolling), so only redraw on the actual idle->active
  -- transition -- redrawing unconditionally here would re-run the whole
  -- statusline render on every keystroke just to reconfirm a boolean that
  -- was already false.
  Autocmd.create({ "CursorMoved", "CursorMovedI", "InsertEnter", "ModeChanged" }, function()
    if is_idle_state then
      is_idle_state = false
      vim.cmd("redrawstatus")
    end
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

---Identity of the current (or, while active, the most recent) idle phase:
---0 before the editor has ever gone idle, then incremented on every
---active->idle transition. A payload compares it with the phase it last did
---its work in to do that work once per idle phase instead of on every
---redraw.
---@return integer
function M.phase()
  ensure_autocmds()
  return phase_counter
end

---Wrap a segment so it renders "" until the editor has been idle, and hides
---again on the very next movement/keystroke. Arguments the wrapper is
---called with (a host's own `opts`, say) are passed through to `segment_fn`.
---@param segment_fn fun(...): string
---@return fun(...): string
function M.wrap(segment_fn)
  return function(...)
    if not M.is_idle() then
      return ""
    end
    return segment_fn(...)
  end
end

return M
