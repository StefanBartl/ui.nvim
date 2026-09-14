---@module 'ui.statusline.modules.casedesk'
--- Statusline segment: current case's short number + company + how many
--- files sit in its Replies/ folder, plus an SLA badge when a P1/P2 clock
--- is urgent (docs/ROADMAP/casedesk/SLA.md §6C) — empty string whenever the
--- focused buffer isn't inside a known case (ROADMAP.md v7's
--- "Statusline-Badge").
---
--- `casedesk.resolve.sync` is the same buffer -> case lookup
--- `:Case`'s routes use (registry membership, not a marker file), just
--- called for its synchronous half only — no kit.select fallback, a
--- statusline redraw can't prompt.
---
--- Cached by buffer name AND a coarse time bucket: the base label only
--- changes on a buffer switch (same "recompute only when the cheap key
--- changes" shape as the sibling `plugin_summary` module), but an SLA
--- deadline keeps ticking while you sit in the same buffer — without a
--- time component the badge would freeze at whatever it showed when you
--- last switched in, which defeats the point for a P1 case worked for an
--- hour straight. `SLA_REFRESH_SECONDS` bounds how stale it can get without
--- recomputing (meta read + a stream reparse) on every single redraw.

local uv = vim.uv or vim.loop

local SLA_REFRESH_SECONDS = 60

---@type string|nil bufname the cached text was last derived from
local cached_bufname = nil
---@type integer time bucket the cached text was last derived from
local cached_bucket = -1
local cached_text = ""

---@param dir string
---@return integer
local function count_files(dir)
  local n = 0
  local fd = uv.fs_scandir(dir)
  if fd then
    while true do
      local name, typ = uv.fs_scandir_next(fd)
      if not name then
        break
      end
      if typ == "file" then
        n = n + 1
      end
    end
  end
  return n
end

--- SLA.md §6C: only P1/P2 (config.sla_active_priorities) and only once a
--- clock is under config.sla_warn_at of its budget — a badge that's always
--- on for a 6-week Korrekturmaßnahme budget is just noise, and stops being
--- looked at within a week (same reasoning SLA.md §6C gives for capping
--- active notifications to one per threshold).
--- The part of casedesk.nvim's registry entry this segment reads.
---
--- Declared here rather than named across the repository boundary: casedesk
--- is a soft dependency, so its types are not on this plugin's check path and
--- `Casedesk.RegistryEntry` resolves to nothing. A blanket suppression would
--- also hide a typo in a field name, which is the failure this shape catches.
---@class Ui.Casedesk.Entry
---@field dir string # Absolute path of the case directory
---@field short string # Short label shown in the badge

---@param entry Ui.Casedesk.Entry
---@return string
local function sla_badge(entry)
  local ok_sla, sla = pcall(require, "casedesk.sla")
  if not ok_sla then
    return ""
  end
  local ok_status, status = pcall(sla.status, entry)
  if not ok_status or not status then
    return ""
  end

  -- pcall like the `sla` require above: this segment is part of the
  -- statusline framework, which lives in the configuration and has to keep
  -- drawing on a machine that has no casedesk checkout at all.
  local ok_config, config = pcall(require, "casedesk.config")
  if not ok_config then
    return ""
  end
  local active = false
  for _, p in ipairs(config.sla_active_priorities) do
    if p == status.digit then
      active = true
      break
    end
  end
  if not active then
    return ""
  end

  local worst = sla.most_urgent(status)
  if not worst or not sla.under_threshold(worst, config.sla_warn_at) then
    return ""
  end

  -- IDEEN-statusline.md's "farbcodierter Countdown, grün -> gelb -> rot"
  -- minus the green: the badge staying hidden until `under_threshold` is
  -- SLA.md §6C's own explicit anti-noise design ("sonst ist es
  -- Dauerrauschen"), not something this segment should override. What is a
  -- genuine "weiterdenken" on top of it is the two-stage color inside that
  -- already-visible window -- overdue is a materially different situation
  -- from merely urgent, and a reader scanning the statusline shouldn't have
  -- to read the duration text to tell them apart.
  local overdue = worst.remaining < 0
  local marker = overdue and "SLA!" or "SLA"
  -- DiagnosticError/DiagnosticWarn: existing groups carrying the theme's
  -- error/warning colors, same "no new highlight group" convention the base
  -- label follows below.
  local hl = overdue and "%#DiagnosticError#" or "%#DiagnosticWarn#"
  return " " .. hl .. marker .. " " .. sla.format_duration(worst.remaining) .. " "
end

---@param entry Ui.Casedesk.Entry
---@return string
local function compute(entry)
  -- Plain require, unlike the guarded ones above: `compute` only runs once
  -- `resolve.sync` has returned an entry, which already proves casedesk is on
  -- the runtimepath.
  local meta = require("casedesk.meta")
  local m = meta.read(entry.dir)

  local label = (m and m.company) and (entry.short .. " " .. m.company) or entry.short
  local count = count_files(entry.dir .. "/Replies")
  local reply_word = count == 1 and "reply" or "replies"

  -- Same highlight convention as the `lsp` segment (custom.lua) — no new
  -- theme color, this reuses an existing group.
  return " %#St_Lsp#" .. label .. " · " .. count .. " " .. reply_word .. " " .. sla_badge(entry)
end

return function()
  local bufname = vim.api.nvim_buf_get_name(0)
  local bucket = math.floor(os.time() / SLA_REFRESH_SECONDS)
  if bufname == cached_bufname and bucket == cached_bucket then
    return cached_text
  end
  cached_bufname = bufname
  cached_bucket = bucket

  local ok_resolve, resolve = pcall(require, "casedesk.resolve")
  if not ok_resolve then
    cached_text = ""
    return cached_text
  end

  local ok_entry, entry = pcall(resolve.sync, nil)
  if not ok_entry or not entry then
    cached_text = ""
    return cached_text
  end

  cached_text = compute(entry)
  return cached_text
end
