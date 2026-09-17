---@module 'ui.statusline.modules.runtime_analysis_ampel'
--- A tiny traffic-light glyph (\xF0\x9F\x9F\xA2/\xF0\x9F\x9F\xA1/\xF0\x9F\x94\xB4) for whether any
--- runtime-analysis.nvim-instrumented plugin looks unhealthy right now --
--- before reaching for `:RATelemetry` explicitly. From IDEEN-statusline.md's
--- "Segmente, die dieses Ökosystem einzigartig machen" bucket.
---
--- Renders empty when runtime-analysis.nvim is not installed, and empty
--- again when it is installed but nothing has ever wrapped/started a
--- telemetry instance (`known_namespaces()` empty) -- an ampel with no
--- plugin to watch is not a signal, just clutter.
---
--- HONEST LIMITS
--- "Right now" here means "any function called today (`Data.days[today]`)
--- whose LIFETIME error count is above zero, or whose LIFETIME mean call
--- time is above `SLOW_MEAN_MS`" -- runtime-analysis.telemetry aggregates
--- calls, it does not timestamp each one, so today's activity is the
--- closest honest proxy for "currently" this data actually supports. A
--- function that errored once months ago and has not been called since
--- will not turn this red -- it has to be called again today to count.
---
--- Only the public `runtime-analysis.telemetry` facade is used (`get`,
--- `load`, `known_namespaces` -- never its internal `.store`/`.report`
--- submodules), so this degrades gracefully across that plugin's own
--- version changes the same way any other soft dependency here does.

--- Red circle -- any namespace has an error today.
local ERROR_GLYPH = " \xF0\x9F\x94\xB4 "
--- Yellow circle -- no errors, but something is running noticeably slow today.
local SLOW_GLYPH = " \xF0\x9F\x9F\xA1 "
--- Green circle -- everything instrumented looks fine.
local OK_GLYPH = " \xF0\x9F\x9F\xA2 "

--- Above this lifetime mean call time (ms), a function counts as "auffällig
--- langsam" for today's ampel state.
local SLOW_MEAN_MS = 50

--- `entries_from_disk` below (namespace with no live telemetry instance) is
--- a real disk read (`telemetry.load`) with no cache of its own, unlike the
--- in-memory `inst.report()` branch -- and the statusline redraws on nearly
--- every event, so without a TTL this would shell out to disk on every
--- cursor move for each such namespace. Short enough to stay "right now"
--- per this module's own doc comment, long enough to absorb a redraw burst.
local DISK_TTL_SECONDS = 5
---@type table<string, { entries: Ui.Statusline.RuntimeAnalysisAmpel.Entry[], expires_at: integer }>
local disk_cache = {}

---@class Ui.Statusline.RuntimeAnalysisAmpel.Entry
---@field errors integer
---@field mean_ms number|nil

---Fold one namespace's entries into the running `state`.
---@param entries Ui.Statusline.RuntimeAnalysisAmpel.Entry[]
---@param state { error: boolean, slow: boolean }
local function classify(entries, state)
  for _, e in ipairs(entries) do
    if (e.errors or 0) > 0 then
      state.error = true
    end
    if e.mean_ms and e.mean_ms > SLOW_MEAN_MS then
      state.slow = true
    end
  end
end

---Today's active entries for a namespace with no live instance -- read
---straight off disk (`telemetry.load`, read-only, no flush) and filtered to
---keys `Data.days[today]` marks as called today.
---@param telemetry table # `require("runtime-analysis.telemetry")`, untyped: a soft dependency's module is not on this project's own LSP path.
---@param namespace string
---@param today string
---@return Ui.Statusline.RuntimeAnalysisAmpel.Entry[]
local function entries_from_disk(telemetry, namespace, today)
  local cached = disk_cache[namespace]
  local now = os.time()
  if cached and cached.expires_at > now then
    return cached.entries
  end

  local data = telemetry.load(namespace)
  if not data then
    disk_cache[namespace] = { entries = {}, expires_at = now + DISK_TTL_SECONDS }
    return {}
  end

  local active = (data.days and data.days[today]) or {}
  local entries = {}
  for key in pairs(active) do
    local stats = data.functions and data.functions[key]
    if stats then
      local mean_ms = nil
      if stats.timing and (stats.timing.n or 0) > 0 then
        mean_ms = stats.timing.total_ms / stats.timing.n
      end
      entries[#entries + 1] = { errors = stats.errors or 0, mean_ms = mean_ms }
    end
  end
  disk_cache[namespace] = { entries = entries, expires_at = now + DISK_TTL_SECONDS }
  return entries
end

---Today's entries for `namespace`, live instance or not.
---@param telemetry table # see `entries_from_disk`'s own note on this parameter.
---@param namespace string
---@param today string
---@return Ui.Statusline.RuntimeAnalysisAmpel.Entry[]
local function entries_for(telemetry, namespace, today)
  local inst = telemetry.get(namespace)
  if inst then
    -- In-memory only (base + pending), never flushes -- safe to call on
    -- every render.
    return inst.report({ since = "1d" }).entries
  end
  return entries_from_disk(telemetry, namespace, today)
end

---@return string
return function()
  local telemetry = require("ui.util.soft_require").try("runtime-analysis.telemetry")
  if not telemetry then
    return ""
  end

  local namespaces = telemetry.known_namespaces()
  if #namespaces == 0 then
    return ""
  end

  local today = os.date("%Y-%m-%d") --[[@as string]]
  local state = { error = false, slow = false }
  for _, namespace in ipairs(namespaces) do
    classify(entries_for(telemetry, namespace, today), state)
  end

  if state.error then
    return ERROR_GLYPH
  elseif state.slow then
    return SLOW_GLYPH
  end
  return OK_GLYPH
end
