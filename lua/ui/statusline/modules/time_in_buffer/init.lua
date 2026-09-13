---@module 'ui.statusline.modules.time_in_buffer'
--- "12m" -- elapsed time since this buffer was first entered, this session.
--- `os.time()` recorded at the first `BufEnter`, formatted compactly at
--- render time. Not persisted across restarts or aggregated across
--- sessions -- IDEEN-statusline.md's own note floats a `sessions.nvim`-based
--- cross-session total as a follow-up, deliberately not built here.

local Autocmd = require("lib.nvim.bindings.autocmd")
local primitives = require("ui.statusline.utils.primitives")

---@type table<integer, integer>
local entered_at = {}
local registered = false

--- "45s" / "12m" / "1h" / "1h5m" -- never more than two units, since a
--- statusline segment is not the place for exact durations.
---@param seconds integer
---@return string
local function format_duration(seconds)
  if seconds < 60 then
    return seconds .. "s"
  end

  local minutes = math.floor(seconds / 60)
  if minutes < 60 then
    return minutes .. "m"
  end

  local hours = math.floor(minutes / 60)
  local rem_minutes = minutes % 60
  if rem_minutes == 0 then
    return hours .. "h"
  end
  return hours .. "h" .. rem_minutes .. "m"
end

--- Register once: `BufEnter` seeds a buffer's start time the first time it
--- is entered (never overwrites one already set -- re-entering a buffer must
--- not restart its clock), `BufDelete`/`BufWipeout` forgets it so the table
--- does not grow for the life of a long session.
---@return nil
local function ensure_autocmds()
  if registered then
    return
  end
  registered = true

  local group = Autocmd.group("ui_statusline_time_in_buffer", true)

  Autocmd.create("BufEnter", function(args)
    if not entered_at[args.buf] then
      entered_at[args.buf] = os.time()
    end
  end, {
    group = group,
    desc = "ui.statusline: remember when a buffer was first entered this session",
  })

  Autocmd.create({ "BufDelete", "BufWipeout" }, function(args)
    entered_at[args.buf] = nil
  end, {
    group = group,
    desc = "ui.statusline: forget a buffer's first-entered time once it is gone",
  })
end

---@return string
return function()
  ensure_autocmds()

  local buf = primitives.stbufnr()
  -- Covers a buffer that was already open before this module was ever
  -- required (and so never got a `BufEnter` this module was listening for) --
  -- the same "seed on first read, not just on the event" fallback
  -- `ui.statusline.modules.macro_counter` does not need but this does.
  if not entered_at[buf] then
    entered_at[buf] = os.time()
  end

  return " " .. format_duration(os.time() - entered_at[buf]) .. " "
end
