---@module 'ui.statusline.modules.idle_clock'
--- Wall-clock time ("14:32"), shown only once the editor has been idle
--- (`CursorHold`/`CursorHoldI`, i.e. `updatetime` ms with no input) and
--- hidden again on the very next keystroke or cursor move --
--- IDEEN-statusline.md's "Idle-Erweiterung nach N Sekunden Inaktivität",
--- using its own first example payload ("Uhrzeit"). The idle detection
--- itself lives in `ui.statusline.utils.idle`, reusable by any other
--- idle-only segment (a mini git log, extra breadcrumb room, ...) the same
--- bucket floats without needing its own CursorHold wiring.

local idle = require("ui.statusline.utils.idle")

return idle.wrap(function()
  return " " .. os.date("%H:%M") .. " "
end)
