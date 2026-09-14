---@module 'ui.statusline.modules.since_last_save'
--- A duration since the buffer became modified, escalating from a muted
--- color to a warning to an error the longer the change sits unsaved --
--- IDEEN-statusline.md's "'Seit letztem Save'-Indikator, der mit der Zeit
--- wächst": softer than a plain `[+]` modified flag, which never
--- distinguishes "just typed a character" from "forgot to save for twenty
--- minutes". Renders empty whenever the buffer is not modified (right
--- after a save, or before the first edit) or is not a normal file buffer.
---
--- No autocmd needed to DETECT "just became modified": the statusline
--- redraws on virtually every buffer-changing event already, so the first
--- render that observes `modified == true` records that moment -- the same
--- "compute lazily at read time" shape
--- `ui.statusline.modules.filetree_cwd_mode` uses to seed its own history.
--- `BufDelete`/`BufWipeout` still need an explicit autocmd, since nothing
--- else would ever prune a deleted buffer's entry.

local Autocmd = require("lib.nvim.bindings.autocmd")
local primitives = require("ui.statusline.utils.primitives")

---@type table<integer, integer> bufnr -> epoch when it was first observed modified since its last save
local became_modified_at = {}

Autocmd.create({ "BufDelete", "BufWipeout" }, function(args)
  became_modified_at[args.buf] = nil
end, {
  group = Autocmd.group("UiStatuslineSinceLastSave", true),
  desc = "ui.statusline: forget a deleted buffer's since_last_save clock",
})

--- "45s" / "12m" / "1h5m" -- same compact, at-most-two-units shape
--- `ui.statusline.modules.time_in_buffer` uses; duplicated rather than
--- shared, since sharing it would mean reaching across two otherwise
--- unrelated modules for four lines of arithmetic.
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

--- Bullet, same glyph `ui.statusline.modules.filetree_cwd_mode`'s history
--- dots use -- a small "there is state here" marker, not a warning icon in
--- its own right (the color carries that).
local GLYPH = "\xE2\x97\x8F"

---@param opts { warn_after_seconds?: integer, critical_after_seconds?: integer }?
---  warn_after_seconds: elapsed time (unsaved) after which the color steps
---                       up from muted to DiagnosticWarn. Default 60.
---  critical_after_seconds: elapsed time after which it steps up again to
---                           DiagnosticError. Default 300 (5 minutes).
---@return string
return function(opts)
  opts = opts or {}
  local warn_after = opts.warn_after_seconds or 60
  local critical_after = opts.critical_after_seconds or 300

  local buf = primitives.stbufnr()
  if vim.bo[buf].buftype ~= "" then
    return ""
  end

  if not vim.bo[buf].modified then
    became_modified_at[buf] = nil
    return ""
  end

  local now = os.time()
  if not became_modified_at[buf] then
    became_modified_at[buf] = now
  end

  local elapsed = now - became_modified_at[buf]
  local hl = "Comment"
  if elapsed >= critical_after then
    hl = "DiagnosticError"
  elseif elapsed >= warn_after then
    hl = "DiagnosticWarn"
  end

  return " %#" .. hl .. "#" .. GLYPH .. " " .. format_duration(elapsed) .. " "
end
