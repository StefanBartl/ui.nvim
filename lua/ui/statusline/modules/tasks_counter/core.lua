---@module 'ui.statusline.modules.tasks_counter.core'
--- State, cache and rendering of the `tasks_counter` segment.
---
--- The statusline redraws on nearly every keystroke, so `render()` only ever
--- reads a table: it never touches a file, resolves a path or starts a job
--- itself. When the cached result is missing or older than `ttl_ms` it
--- *schedules* a refresh (so the filesystem work happens after the redraw,
--- not inside it) and keeps showing the old number until the new one lands.
--- The refresh reads through `vim.uv` callbacks and redraws the statusline
--- only if the numbers actually changed.
---
--- A result belongs to one (vault, area) pair. `DirChanged` drops it -- the
--- old project's count must never show next to the new project's name -- and
--- a generation counter makes a slow read that was started before the
--- change discard its own result instead of overwriting the new state.

local config = require("ui.statusline.modules.tasks_counter.config")
local source = require("ui.statusline.modules.tasks_counter.source")
local Autocmd = require("lib.nvim.bindings.autocmd")

local uv = vim.uv or vim.loop

local M = {}

---@class Ui.Tasks.State
---@field counts Ui.Tasks.Counts|nil # last result for the current project; nil = nothing to show
---@field loaded_at integer|nil # ms timestamp of the last finished refresh (also after a failed one)
---@field scheduled boolean # a refresh is queued or running
---@field gen integer # bumped by every invalidate/refresh; a late result from an older one is dropped
---@field vault string|nil # vault the cached result was read from (for the write watcher)
local state = { counts = nil, loaded_at = nil, scheduled = false, gen = 0, vault = nil }

---@return integer
local function now_ms()
  return math.floor(uv.hrtime() / 1e6)
end

---@param a Ui.Tasks.Counts|nil
---@param b Ui.Tasks.Counts|nil
---@return boolean
local function same(a, b)
  if a == nil or b == nil then
    return a == b
  end
  return a.total == b.total and a.urgent == b.urgent and a.blocked == b.blocked
end

---@return nil
local function redraw()
  pcall(vim.cmd, "redrawstatus")
end

--- Resolve vault + area and read the numbers. Runs from `vim.schedule`, never
--- from inside a redraw, because resolving does a few `stat` calls.
---@return nil
function M.refresh()
  local cfg = config.get()
  state.gen = state.gen + 1
  local gen = state.gen
  state.scheduled = true

  ---@param counts Ui.Tasks.Counts|nil
  ---@param vault string|nil
  local function finish(counts, vault)
    if gen ~= state.gen then
      return
    end
    state.scheduled = false
    state.loaded_at = now_ms()
    state.vault = vault
    local changed = not same(counts, state.counts)
    state.counts = counts
    if changed then
      redraw()
    end
  end

  local vault = config.resolve_vault(cfg)
  local area = vault and config.resolve_area(cfg) or nil
  if not vault or not area then
    return finish(nil, nil)
  end

  source.load(cfg.source, { vault = vault, area = area, max_files = cfg.max_files }, function(tasks)
    -- luv callback (fast context): hop back before touching any state.
    vim.schedule(function()
      local counts = nil
      if type(tasks) == "table" then
        counts = source.tally(tasks, cfg.statuses, cfg.urgent_prio)
      end
      finish(counts, vault)
    end)
  end)
end

--- Queue a refresh unless one is already queued. Idempotent, cheap.
---@return nil
local function schedule_refresh()
  if state.scheduled then
    return
  end
  state.scheduled = true
  local gen = state.gen
  vim.schedule(function()
    -- An invalidate in between bumped `gen` and queued its own refresh.
    if gen == state.gen then
      M.refresh()
    end
  end)
end

--- Whether the autocmds below are registered. They are created on the first
--- render, not on `require`: the segment is opt-in, so nothing should run
--- before a statusline actually asks for it.
local registered = false

--- Forget the cached result (project switched, config changed) and queue a
--- fresh read. The old number is dropped, not kept: it may belong to another
--- project.
---@return nil
function M.invalidate()
  state.gen = state.gen + 1
  state.counts = nil
  state.loaded_at = nil
  state.scheduled = false
  if registered then
    schedule_refresh()
  end
end

--- Mark the cached result stale but keep showing it, so the number does not
--- blink out while the new one is being read (a vault file was saved).
---@return nil
function M.touch()
  state.loaded_at = nil
  if registered then
    schedule_refresh()
  end
end

---@return nil
local function ensure_autocmds()
  if registered then
    return
  end
  registered = true

  local group = Autocmd.group("UiStatuslineTasksCounter", true)

  Autocmd.create("DirChanged", function()
    M.invalidate()
  end, {
    group = group,
    desc = "ui.statusline: tasks_counter drops its count when the project changes",
  })

  -- Re-read right after a Markdown file inside the vault is saved, so
  -- `:MyPlugins task done` (or a hand edit) shows without waiting for the
  -- TTL. The path test is a plain prefix compare on already-known state.
  Autocmd.create("BufWritePost", function(args)
    local cfg = config.get()
    local vault = state.vault
    if not cfg.watch_writes or not vault or not args.file then
      return
    end
    local file = vim.fs.normalize(args.file):lower()
    if file:sub(1, #vault + 1) == vault:lower() .. "/" then
      M.touch()
    end
  end, {
    group = group,
    pattern = "*.md",
    desc = "ui.statusline: tasks_counter re-reads after a vault Markdown file is saved",
  })
end

---@param n integer
---@param label string
---@param hl string
---@return string
local function chunk(n, label, hl)
  return ("%#" .. hl .. "#" .. label .. n .. " ")
end

--- The statusline text. Pure reads of `state`; see the module header.
---@return string
function M.render()
  ensure_autocmds()
  local cfg = config.get()

  if state.loaded_at == nil or (now_ms() - state.loaded_at) >= cfg.ttl_ms then
    schedule_refresh()
  end

  local counts = state.counts
  if not counts or (counts.total == 0 and cfg.hide_zero) then
    return ""
  end

  -- `%` is the statusline's escape character: a host-supplied prefix must
  -- not be able to open a format item.
  local out = " %#St_TasksCounter#" .. (cfg.prefix:gsub("%%", "%%%%")) .. counts.total .. " "
  if cfg.breakdown then
    if counts.urgent > 0 then
      out = out .. chunk(counts.urgent, "P1:", "St_TasksUrgent")
    end
    if counts.blocked > 0 then
      out = out .. chunk(counts.blocked, "B:", "St_TasksBlocked")
    end
  end
  return out
end

--- A copy of the cached state, for specs and `:checkhealth`.
---@return { counts: Ui.Tasks.Counts|nil, loaded_at: integer|nil, scheduled: boolean, vault: string|nil }
function M.snapshot()
  return {
    counts = state.counts and vim.deepcopy(state.counts) or nil,
    loaded_at = state.loaded_at,
    scheduled = state.scheduled,
    vault = state.vault,
  }
end

--- Back to the cold state, as before the first render. Specs only.
---@return nil
function M._reset()
  state.gen = state.gen + 1
  state.counts = nil
  state.loaded_at = nil
  state.scheduled = false
  state.vault = nil
end

return M
