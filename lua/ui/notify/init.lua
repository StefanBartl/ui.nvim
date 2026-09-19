---@module 'ui.notify'
--- `vim.notify` as stacked toasts with a history. Enabled, every
--- `vim.notify(msg, level)` becomes a `ui.kit.toast` in the top-right
--- corner, coloured by level, auto-dismissed after a per-level timeout --
--- and is recorded in a ring buffer that `:UI notify history` opens as a
--- scrollable viewer, so a message that vanished can be read back.
---
--- The idea is rcarriga/nvim-notify's; the pieces are this plugin's:
--- `ui.kit.toast` already stacks and reflows non-focusable corner floats,
--- and `ui.kit.viewer` is the read-only float the history opens in. What
--- this module adds is the `vim.notify` seam, the level -> colour/timeout
--- mapping, and the history itself.
---
--- Explicit-only, like `ui.context`: `ui.setup({ notify = true })` or
--- `:UI notify on`. `disable()` puts the previous `vim.notify` back exactly
--- as it was, so a host that routes notifications elsewhere (noice, snacks)
--- can try this for a session and leave again.

local M = {}

---@class Ui.Notify.Entry
---@field time integer      # os.time()
---@field level integer     # vim.log.levels.*
---@field msg string
---@field title string|nil

---@class Ui.Notify.Opts
---@field history_size? integer
---@field min_level? integer                  # levels below this are recorded, not shown
---@field timeouts? table<integer, integer>   # ms per level; 0 = stays until cleared
---@field titles? table<integer, string>      # toast title per level

---@class Ui.Notify.Config: Ui.Notify.Opts
local cfg = {
  history_size = 200,
  min_level = vim.log.levels.INFO,
  timeouts = {
    [vim.log.levels.TRACE] = 2000,
    [vim.log.levels.DEBUG] = 2000,
    [vim.log.levels.INFO] = 3000,
    [vim.log.levels.WARN] = 5000,
    [vim.log.levels.ERROR] = 8000,
    [vim.log.levels.OFF] = 0,
  },
  titles = {
    [vim.log.levels.TRACE] = "Trace",
    [vim.log.levels.DEBUG] = "Debug",
    [vim.log.levels.INFO] = "Info",
    [vim.log.levels.WARN] = "Warning",
    [vim.log.levels.ERROR] = "Error",
  },
}

local LEVEL_NAMES = {
  [vim.log.levels.TRACE] = "TRACE",
  [vim.log.levels.DEBUG] = "DEBUG",
  [vim.log.levels.INFO] = "INFO",
  [vim.log.levels.WARN] = "WARN",
  [vim.log.levels.ERROR] = "ERROR",
}

local GROUPS = {
  [vim.log.levels.TRACE] = "UiNotifyTrace",
  [vim.log.levels.DEBUG] = "UiNotifyDebug",
  [vim.log.levels.INFO] = "UiNotifyInfo",
  [vim.log.levels.WARN] = "UiNotifyWarn",
  [vim.log.levels.ERROR] = "UiNotifyError",
}

---@type Ui.Notify.Entry[]
local history = {}

---@type function|nil  the vim.notify this module replaced
local previous = nil

---@type boolean
local enabled = false

---@type table|nil  hl.persist handle
local hl_handle = nil

---@internal
local function groups_spec()
  return {
    UiNotifyTrace = { link = "Comment", default = true },
    UiNotifyDebug = { link = "Comment", default = true },
    UiNotifyInfo = { link = "DiagnosticInfo", default = true },
    UiNotifyWarn = { link = "DiagnosticWarn", default = true },
    UiNotifyError = { link = "DiagnosticError", default = true },
  }
end

---@internal
local function ensure_groups()
  if hl_handle then
    return
  end
  local ok, hl = pcall(require, "lib.nvim.ui.hl")
  if ok and type(hl.persist) == "function" then
    hl_handle = hl.persist(groups_spec, { name = "ui_notify" })
  else
    for group, opts in pairs(groups_spec()) do
      vim.api.nvim_set_hl(0, group, opts)
    end
  end
end

---@internal
---@param level any
---@return integer
local function norm_level(level)
  if type(level) == "string" then
    local up = level:upper()
    for l, name in pairs(LEVEL_NAMES) do
      if name == up then
        return l
      end
    end
    return vim.log.levels.INFO
  end
  if type(level) ~= "number" then
    return vim.log.levels.INFO
  end
  return level
end

---@internal
---Record one entry, trimming the ring.
---@param entry Ui.Notify.Entry
local function record(entry)
  history[#history + 1] = entry
  local max = cfg.history_size or 200
  while #history > max do
    table.remove(history, 1)
  end
end

---@internal
---Render one entry as a toast. Never raises: a notification must not.
---@param entry Ui.Notify.Entry
local function show(entry)
  local ok, toast = pcall(require, "ui.kit.toast")
  if not ok then
    return
  end
  local title = entry.title or cfg.titles[entry.level] or LEVEL_NAMES[entry.level]
  local surf = toast.open({
    message = entry.msg,
    title = title and (" " .. title .. " ") or nil,
    timeout = cfg.timeouts[entry.level] or 3000,
  })
  if surf and surf:is_valid() then
    local group = GROUPS[entry.level] or "UiNotifyInfo"
    pcall(
      vim.api.nvim_set_option_value,
      "winhighlight",
      ("FloatBorder:%s,FloatTitle:%s"):format(group, group),
      {
        win = surf.winid,
      }
    )
  end
end

---@internal
---True while a `show()` call is on the stack. A toast that itself fails to
---open (e.g. `make_scratch` erroring) reports that failure through
---`lib.nvim.notify`, which calls the very `vim.notify` this module just
---replaced -- routing straight back into `M.handler` from inside the
---`show()` call that is still on the stack. Without this guard that
---re-entrant call would try to show ITS OWN toast, fail the same way, and
---recurse until the stack is exhausted.
---@type boolean
local showing = false

---@internal
---Render one entry as a toast, guarded against the re-entrant recursion
---described above. Never raises: a notification must not.
---@param entry Ui.Notify.Entry
local function show_guarded(entry)
  if showing then
    return
  end
  showing = true
  pcall(show, entry)
  showing = false
end

---The `vim.notify` replacement. Exposed so a host can call it directly.
---@param msg any
---@param level any
---@param opts table|nil
function M.handler(msg, level, opts)
  if not enabled then
    -- Disabled, but something may still be routing calls through us -- a
    -- foreign wrapper installed after enable() ran, that this module was
    -- never able to fully unwind from (see disable()'s own comment).
    -- Forward straight to whatever handler we would have restored instead
    -- of recording/showing anything, so "disabled" is not just cosmetic.
    local fallback = previous
    if fallback and fallback ~= M.handler then
      fallback(msg, level, opts)
    end
    return
  end
  local entry = {
    time = os.time(),
    level = norm_level(level),
    msg = type(msg) == "string" and msg or vim.inspect(msg),
    title = type(opts) == "table" and opts.title or nil,
  }
  record(entry)
  if entry.level >= (cfg.min_level or vim.log.levels.INFO) then
    -- Notifications arrive from fast contexts too; the float has to wait.
    if vim.in_fast_event() then
      vim.schedule(function()
        show_guarded(entry)
      end)
    else
      show_guarded(entry)
    end
  end
end

---Install the handler. Idempotent.
function M.enable()
  if enabled then
    return
  end
  enabled = true
  ensure_groups()
  -- Keep the oldest known original handler across an enable/disable cycle
  -- where disable() could not fully unhook (see disable()'s own comment) --
  -- re-capturing `vim.notify` here would otherwise overwrite it with our
  -- own handler (reached through a foreign wrapper) and lose it for good.
  if previous == nil then
    previous = vim.notify
  end
  if vim.notify ~= M.handler then
    vim.notify = M.handler
  end
end

---Put the previous `vim.notify` back. Idempotent.
function M.disable()
  if not enabled then
    return
  end
  enabled = false
  if vim.notify == M.handler then
    vim.notify = previous or vim.notify
    previous = nil
  end
  -- else: a foreign wrapper now owns vim.notify (installed after enable()
  -- ran) and still calls through to M.handler -- keep `previous` rather
  -- than discard it, so a later disable() can still recover the true
  -- original, and so M.handler's own `not enabled` branch has something
  -- to forward to instead of acting.
end

---@return boolean now_enabled
function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
  return enabled
end

---@return boolean
function M.is_enabled()
  return enabled
end

---The recorded entries, oldest first (a copy).
---@return Ui.Notify.Entry[]
function M.history()
  return vim.list_extend({}, history)
end

---Forget every recorded entry.
function M.clear_history()
  history = {}
end

---The history as viewer lines, newest first.
---@return string[]
function M.history_lines()
  if #history == 0 then
    return { "(no notifications recorded)" }
  end
  local lines = {}
  for i = #history, 1, -1 do
    local e = history[i]
    local stamp = os.date("%H:%M:%S", e.time)
    local head = ("%s  %-5s  %s"):format(
      stamp,
      LEVEL_NAMES[e.level] or "?",
      e.title and (e.title .. ": ") or ""
    )
    local first = true
    for _, l in ipairs(vim.split(e.msg, "\n", { plain = true })) do
      if first then
        lines[#lines + 1] = head .. l
        first = false
      else
        lines[#lines + 1] = string.rep(" ", #head) .. l
      end
    end
  end
  return lines
end

---Open the history in a `ui.kit.viewer`.
---@return Ui.Kit.Surface|nil
function M.show_history()
  local ok, viewer = pcall(require, "ui.kit.viewer")
  if not ok then
    return nil
  end
  local lines = M.history_lines()
  return viewer.open({
    title = ("Notifications (%d)"):format(#history),
    lines = lines,
    filetype = "ui-notify-history",
  })
end

---Override the shipped tunables. Tables are merged.
---@param opts Ui.Notify.Opts|nil
function M.setup(opts)
  opts = opts or {}
  if type(opts.history_size) == "number" then
    cfg.history_size = math.max(1, math.floor(opts.history_size))
  end
  if opts.min_level ~= nil then
    cfg.min_level = norm_level(opts.min_level)
  end
  if type(opts.timeouts) == "table" then
    for k, v in pairs(opts.timeouts) do
      cfg.timeouts[norm_level(k)] = v
    end
  end
  if type(opts.titles) == "table" then
    for k, v in pairs(opts.titles) do
      cfg.titles[norm_level(k)] = v
    end
  end
end

---@return Ui.Notify.Config
function M.config()
  return cfg
end

return M
