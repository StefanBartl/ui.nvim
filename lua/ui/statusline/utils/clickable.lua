---@module 'ui.statusline.utils.clickable'
--- Generic click layer for statusline segments. `ui.tabline.utils`' own
--- `btn`/`register_click_handlers` pattern -- one hand-written `UiTb*` global
--- Vimscript function per action -- does not scale to the statusline, where
--- any number of segments might each want click behaviour: a new clickable
--- segment would mean a new named global every time. One global function,
--- `UiSlClick`, dispatches by an integer id into a Lua-side registry instead.
---
--- `wrap(segment_fn, handlers)` is the entry point most modules need: it
--- registers `handlers` once, at wrap time, and returns a new zero-arg
--- function that renders `segment_fn()` wrapped in the
--- `%<id>@UiSlClick@...%X` click protocol -- drop the result straight into a
--- `modules` table entry.

local M = {}

---@alias Ui.Statusline.ClickButton "l"|"r"|"m"
---@alias Ui.Statusline.ClickHandlers table<Ui.Statusline.ClickButton, fun(): nil>

---@type table<integer, Ui.Statusline.ClickHandlers>
local registry = {}
local next_id = 0
local registered_global = false

--- Define the `UiSlClick` global Vimscript function once. Neovim's
--- `'statusline'` click protocol calls a global Vimscript function by name
--- (`%<minwid>@Func@...%X`), not a Lua function directly -- `minwid` is how
--- the registry id this module hands out gets back in.
---@return nil
local function ensure_global()
  if registered_global then
    return
  end
  registered_global = true

  vim.cmd([[
    function! UiSlClick(id, clicks, button, mod)
      call luaeval('require("ui.statusline.utils.clickable")._dispatch(_A[1], _A[2])', [a:id, a:button])
    endfunction
  ]])
end

--- Register a handler table, returning the id future clicks will carry.
--- Exposed mainly for `wrap` below; a module that wants more control than
--- `wrap` gives (its own text-wrapping, several click-carrying pieces in one
--- segment) can call this directly and build the `%id@UiSlClick@...%X`
--- string itself.
---@param handlers Ui.Statusline.ClickHandlers
---@return integer id
function M.register(handlers)
  ensure_global()
  next_id = next_id + 1
  registry[next_id] = handlers
  return next_id
end

--- Reached from the `UiSlClick` global above via `luaeval`. Public only so
--- that call can find it and so tests can drive a click without going
--- through `vim.cmd` -- not meant to be called from a segment itself.
---@param id integer
---@param button Ui.Statusline.ClickButton
---@return nil
function M._dispatch(id, button)
  local handlers = registry[id]
  local fn = handlers and handlers[button]
  if not fn then
    return
  end

  local ok, err = pcall(fn)
  if not ok then
    require("lib.nvim.notify")
      .create("[ui.statusline.utils.clickable]")
      .warn(("click handler for id %d/%s errored: %s"):format(id, button, tostring(err)))
  end
end

--- Wrap a segment-rendering function so its output responds to clicks.
--- Registers `handlers` once, at wrap time -- call this while building a
--- `modules` table (module load / variant setup), not from inside another
--- segment function on every redraw, or the registry grows without bound.
---
--- An empty rendered string is returned unwrapped: there is nothing to click
--- on, and wrapping it anyway would still cost a registry slot for a segment
--- that renders nothing under the buffer/mode currently active.
---
--- Returns the registry id as a second value -- irrelevant to the normal
--- `modules[key] = require(...)`/`clickable.wrap(...)` call sites (an
--- assignment only keeps the first value), but it is what lets a test drive
--- a click without going through `vim.cmd`/a real mouse event: `local _, id
--- = clickable.wrap(...)` followed by `clickable._dispatch(id, "l")`.
---@param segment_fn fun(): string
---@param handlers Ui.Statusline.ClickHandlers
---@return fun(): string render
---@return integer id
function M.wrap(segment_fn, handlers)
  local id = M.register(handlers)
  local render = function()
    local text = segment_fn()
    if text == "" then
      return text
    end
    return "%" .. id .. "@UiSlClick@" .. text .. "%X"
  end
  return render, id
end

return M
