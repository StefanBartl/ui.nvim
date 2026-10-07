---@module 'ui.slots.store'
--- The slot table: which number holds which action, which slots are fixed, and
--- how the rest is kept on disk. No windows, no keymaps; the views and the
--- commands sit on top and subscribe to `on_change`.
---
--- Two kinds of slot:
---
---   * **fixed** -- from `setup({ slots = { [3] = ... } })`. They keep their
---     number, may carry any kind (`cmd`, `lua` included), are never written
---     and cannot be changed or cleared through the store.
---   * **dynamic** -- everything added at runtime. They are written to
---     `stdpath("data")/ui/slots/<scope>.json`, one file per scope (`global`,
---     or one per project root), but only when their kind is persistable.
---
--- There is no upper bound on the number. `add()` takes the lowest free
--- positive number, a cleared slot leaves a gap, and `list()` holds only
--- occupied slots in ascending order.
---
--- The data file is treated as untrusted input: a size cap before reading, the
--- format marker checked, every entry validated, strings capped, and entries of
--- a kind that is not persistable dropped (reported once) -- a file that was
--- copied or edited elsewhere can never introduce a `cmd` or `lua` slot. A file
--- at the path that is not ours is never overwritten: persistence for that
--- scope is switched off and the reason reported once.
---
--- Writes are batched over `save_delay_ms`, go through `lib.nvim.fs.json`
--- (temp file, then rename) and `flush()` runs on `VimLeavePre` (wired by
--- `ui.slots`) and before the scope changes. A failed write is reported and
--- the slots stay dirty, so the next change tries again; nothing here claims
--- "saved" before the write succeeded.

require("ui.slots.@types")

local config = require("ui.slots.config")

local uv = vim.uv or vim.loop

local M = {}

local FORMAT = "ui.slots"
local VERSION = 1
-- Larger numbers are never produced by `add()`; a data file naming one is
-- corrupt or hostile and the entry is dropped.
local MAX_N = config.MAX_N

---@class Ui.Slots.Store.State
---@field fixed table<integer, Ui.Slots.Slot>
---@field dynamic table<integer, Ui.Slots.Slot>
---@field path string|nil            # data file of the loaded scope; nil when not persisted
---@field root string|nil            # project root of the loaded scope (nil for "global")
---@field blocked string|nil         # why persistence is off for this scope
---@field dirty boolean
---@field gen integer                # bumped on every scope change; discards an overtaken save
---@field timer uv.uv_timer_t|nil
---@field listeners table<integer, fun(event: string, n: integer|nil)>
---@field next_listener integer
---@field reported table<string, boolean>
local S = {
  fixed = {},
  dynamic = {},
  path = nil,
  root = nil,
  blocked = nil,
  dirty = false,
  gen = 0,
  timer = nil,
  listeners = {},
  next_listener = 1,
  reported = {},
}

---@param msg string
---@param level integer|nil
local function say(msg, level)
  vim.schedule(function()
    vim.notify("[ui.slots] " .. msg, level or vim.log.levels.WARN)
  end)
end

--- Report a message once per distinct text for the life of the process.
---@param msg string
---@param level integer|nil
local function say_once(msg, level)
  if S.reported[msg] then
    return
  end
  S.reported[msg] = true
  say(msg, level)
end

---@param event string
---@param n integer|nil
local function emit(event, n)
  for _, fn in pairs(S.listeners) do
    pcall(fn, event, n)
  end
end

--- A value is safe to write as JSON when it is a string, a finite number, a
--- boolean, or a table of such (no functions, no cycles). Returns the cleaned
--- copy, or nil when the value cannot be kept.
---@param v any
---@param depth integer
---@return any
local function clean(v, depth)
  local t = type(v)
  if t == "string" or t == "boolean" then
    return v
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then
      return nil
    end
    return v
  elseif t == "table" and depth < 8 then
    -- A JSON null decodes to lib.lua.null.NULL, an empty table with a
    -- metatable: it is "no value", not an empty table.
    if getmetatable(v) ~= nil then
      return nil
    end
    local out = {}
    for k, x in pairs(v) do
      if type(k) == "string" or type(k) == "number" then
        local c = clean(x, depth + 1)
        if c ~= nil then
          out[k] = c
        end
      end
    end
    return out
  end
  return nil
end

--- The first string in `v` (nested tables included) that is longer than `max`,
--- as a message; nil when none is. Read and write side use the same rule, so
--- nothing is saved that a restart would drop.
---@param v any
---@param max integer
---@param name string
---@param depth integer
---@return string|nil
local function long_field(v, max, name, depth)
  if type(v) == "string" then
    if #v > max then
      return ("field '%s' is longer than %d bytes"):format(name, max)
    end
  elseif type(v) == "table" and depth < 8 then
    for k, x in pairs(v) do
      local problem = long_field(x, max, name .. "." .. tostring(k), depth + 1)
      if problem then
        return problem
      end
    end
  end
  return nil
end

---@param kind string
---@return boolean
local function persistable(kind)
  if vim.tbl_contains(config.get().persistable_kinds, kind) then
    return true
  end
  -- A kind registered by a host can ask for it itself (`persist = true`).
  return require("ui.slots.kinds.registry").persists(kind)
end

--- Shallow-validate a slot table handed to `set`/`add`.
---@param slot any
---@return boolean ok
---@return string|nil err
local function check_slot(slot)
  if type(slot) ~= "table" then
    return false, "a slot is a table"
  end
  if type(slot.kind) ~= "string" or slot.kind == "" then
    return false, "a slot needs a kind"
  end
  return true
end

--- A slot that would be saved must be readable again: same limit as `read_entry`.
---@param slot table
---@return string|nil
local function check_limits(slot)
  if not persistable(slot.kind) then
    return nil
  end
  return long_field(slot, config.get().max_string_len, "slot", 0)
end

---@param n any
---@return boolean
local function valid_n(n)
  return type(n) == "number" and n >= 1 and n <= MAX_N and n == math.floor(n)
end

--- A slot as the outside sees it: a copy, with its number and `fixed` flag.
---@param n integer
---@param slot table
---@param fixed boolean
---@return Ui.Slots.Slot
local function present(n, slot, fixed)
  local copy = vim.deepcopy(slot)
  copy.n = n
  copy.fixed = fixed or nil
  return copy
end

-- Persistence -----------------------------------------------------------

---@return string
local function data_dir()
  local custom = config.get().data_dir
  if type(custom) == "string" and custom ~= "" then
    -- normalize() expands "~" and environment variables; mkdir/writefile do not.
    -- Absolute, so a pending write cannot land in another directory after a :cd.
    return vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(custom), ":p"))
  end
  return vim.fs.joinpath(vim.fn.stdpath("data"), "ui", "slots")
end

--- Data file and root of the scope that applies right now.
---@return string path
---@return string|nil root
local function scope_path()
  if config.get().scope == "global" then
    return vim.fs.joinpath(data_dir(), "global.json"), nil
  end
  local root = require("lib.nvim.fs.project_key")()
  local key = vim.fn.sha256(root):sub(1, 16)
  return vim.fs.joinpath(data_dir(), "project-" .. key .. ".json"), root
end

--- Cleaned copy of one persisted entry, or nil plus the reason.
---@param entry any
---@return Ui.Slots.Slot|nil
---@return string|nil reason
local function read_entry(entry)
  if type(entry) ~= "table" then
    return nil, "not a table"
  end
  if not valid_n(entry.n) then
    return nil, "bad number " .. vim.inspect(entry.n)
  end
  if type(entry.kind) ~= "string" or entry.kind == "" then
    return nil, ("slot %d has no kind"):format(entry.n)
  end
  if not persistable(entry.kind) then
    return nil,
      ("slot %d is of kind '%s', which a data file may not hold"):format(entry.n, entry.kind)
  end
  local slot = {}
  for k, v in pairs(entry) do
    if type(k) == "string" and k ~= "fixed" then
      local c = clean(v, 0)
      if c ~= nil then
        slot[k] = c
      end
    end
  end
  local problem = long_field(slot, config.get().max_string_len, "slot", 0)
  if problem then
    return nil, ("slot %d: %s"):format(entry.n, problem)
  end
  slot.n = entry.n
  return slot
end

--- Read the data file of the current scope into `S.dynamic`.
local function load_file()
  S.dynamic, S.blocked, S.path, S.root = {}, nil, nil, nil
  local cfg = config.get()
  if not cfg.persist then
    return
  end

  local path, root = scope_path()
  S.path, S.root = path, root

  local st = uv.fs_stat(path)
  if not st then
    return
  end
  if st.type ~= "file" then
    S.blocked = "the data path is not a file: " .. path
    say_once(S.blocked)
    return
  end
  if st.size > cfg.max_file_kb * 1024 then
    S.blocked = ("the data file is larger than %d KB, not read: %s"):format(cfg.max_file_kb, path)
    say_once(S.blocked)
    return
  end

  local data, err = require("lib.nvim.fs.json").read(path)
  if type(data) ~= "table" or data.format ~= FORMAT or type(data.slots) ~= "table" then
    S.blocked = ("not a ui.slots data file (%s), left untouched: %s"):format(
      err or "wrong format marker",
      path
    )
    say_once(S.blocked)
    return
  end

  for _, entry in ipairs(data.slots) do
    local slot, reason = read_entry(entry)
    if slot then
      if S.fixed[slot.n] then
        say_once(("slot %d is fixed in setup(); the saved one is ignored"):format(slot.n))
      else
        S.dynamic[slot.n] = slot
      end
    else
      say_once(("dropped an entry of %s: %s"):format(path, reason))
    end
  end
end

--- The serialisable form of the dynamic slots.
---@return table
local function snapshot()
  local numbers = vim.tbl_keys(S.dynamic)
  table.sort(numbers)
  local list = {}
  for _, n in ipairs(numbers) do
    local slot = S.dynamic[n]
    if persistable(slot.kind) then
      local c = clean(slot, 0)
      if c then
        c.n = n
        list[#list + 1] = c
      end
    end
  end
  return { format = FORMAT, version = VERSION, root = S.root, slots = list }
end

--- Write the dynamic slots now. Returns false plus a reason when nothing was
--- written (persistence off, blocked, or the write failed).
---@return boolean ok
---@return string|nil err
function M.flush()
  if S.timer then
    S.timer:stop()
  end
  if not S.dirty then
    return true
  end
  if not S.path or S.blocked then
    S.dirty = false
    return false, S.blocked or "persistence is off"
  end

  local ok_mk, mk_err = pcall(vim.fn.mkdir, vim.fs.dirname(S.path), "p")
  if not ok_mk then
    say("could not create " .. vim.fs.dirname(S.path) .. ": " .. tostring(mk_err))
    return false, tostring(mk_err)
  end

  local snap = snapshot()
  local limit = config.get().max_file_kb * 1024
  local encoded_ok, encoded = pcall(vim.json.encode, snap)
  if encoded_ok and #encoded > limit then
    -- What would not be read back is not written: the next start would block.
    local msg = ("the slots take more than %d KB and are not saved"):format(
      config.get().max_file_kb
    )
    say(msg, vim.log.levels.ERROR)
    return false, msg
  end

  local ok, err = require("lib.nvim.fs.json").write(S.path, snap)
  if not ok then
    -- Every failure is told, not only the first: staying silent here is
    -- what lets someone keep adding slots that never reach the disk.
    say("could not save the slots: " .. tostring(err), vim.log.levels.ERROR)
    return false, err
  end
  S.dirty = false
  return true
end

--- A change happened: mark dirty and (re)start the batching timer.
local function touch()
  if not S.path or not config.get().persist then
    return
  end
  -- Dirty even when blocked: `flush()` must say "not written" instead of
  -- claiming success for a change that cannot reach the disk.
  S.dirty = true
  if S.blocked then
    return
  end
  local delay = config.get().save_delay_ms
  if delay <= 0 then
    M.flush()
    return
  end
  if not S.timer then
    S.timer = uv.new_timer()
  end
  local gen = S.gen
  S.timer:stop()
  S.timer:start(
    delay,
    0,
    vim.schedule_wrap(function()
      -- A scope change flushed already; an overtaken timer must not write the
      -- new scope's state under the old one's expectations.
      if gen == S.gen then
        M.flush()
      end
    end)
  )
end

-- Reading ---------------------------------------------------------------

--- The slot with number `n`, or nil.
---@param n integer
---@return Ui.Slots.Slot|nil
function M.get(n)
  if S.fixed[n] then
    return present(n, S.fixed[n], true)
  end
  if S.dynamic[n] then
    return present(n, S.dynamic[n], false)
  end
  return nil
end

--- Every occupied slot, ascending by number.
---@return Ui.Slots.Slot[]
function M.list()
  local numbers = {}
  for n in pairs(S.fixed) do
    numbers[#numbers + 1] = n
  end
  for n in pairs(S.dynamic) do
    if not S.fixed[n] then
      numbers[#numbers + 1] = n
    end
  end
  table.sort(numbers)
  local out = {}
  for _, n in ipairs(numbers) do
    out[#out + 1] = M.get(n)
  end
  return out
end

---@return integer
function M.count()
  return #M.list()
end

--- The lowest positive number no slot holds.
---@return integer
function M.next_free()
  local n = 1
  while S.fixed[n] or S.dynamic[n] do
    n = n + 1
  end
  return n
end

--- Why persistence is off for the loaded scope, or nil.
---@return string|nil
function M.blocked_reason()
  return S.blocked
end

--- Path of the loaded scope's data file, or nil when nothing is persisted.
---@return string|nil
function M.path()
  return S.path
end

-- Changing --------------------------------------------------------------

--- Put `slot` at number `n`. Fails for a fixed slot.
---@param n integer
---@param slot table
---@return boolean ok
---@return string|nil err
function M.set(n, slot)
  if not valid_n(n) then
    return false, "slot numbers are positive whole numbers"
  end
  local ok, err = check_slot(slot)
  if not ok then
    return false, err
  end
  if S.fixed[n] then
    return false, ("slot %d is fixed in setup()"):format(n)
  end
  local copy = vim.deepcopy(slot)
  copy.n, copy.fixed = nil, nil
  local limit_err = check_limits(copy)
  if limit_err then
    return false, limit_err
  end
  S.dynamic[n] = copy
  touch()
  emit("set", n)
  return true
end

--- Take the lowest free number for `slot`.
---@param slot table
---@return integer|nil n
---@return string|nil err
function M.add(slot)
  local ok, err = check_slot(slot)
  if not ok then
    return nil, err
  end
  local n = M.next_free()
  local set_ok, set_err = M.set(n, slot)
  if not set_ok then
    return nil, set_err
  end
  return n
end

--- Merge `patch` into slot `n`. `vim.NIL` as a value removes that field (a Lua
--- `nil` cannot be told apart from "not given" inside a table).
---@param n integer
---@param patch table
---@return boolean ok
---@return string|nil err
function M.update(n, patch)
  if S.fixed[n] then
    return false, ("slot %d is fixed in setup()"):format(n)
  end
  local slot = S.dynamic[n]
  if not slot then
    return false, ("slot %d is empty"):format(n)
  end
  local next_slot = vim.deepcopy(slot)
  for k, v in pairs(patch) do
    if k ~= "n" and k ~= "fixed" then
      if v == vim.NIL then
        next_slot[k] = nil
      else
        next_slot[k] = vim.deepcopy(v)
      end
    end
  end
  local ok, err = check_slot(next_slot)
  if not ok then
    return false, err
  end
  local limit_err = check_limits(next_slot)
  if limit_err then
    return false, limit_err
  end
  S.dynamic[n] = next_slot
  touch()
  emit("set", n)
  return true
end

--- Empty slot `n`. Fails for a fixed slot, and for a slot that is not there.
---@param n integer
---@return boolean ok
---@return string|nil err
function M.clear(n)
  if S.fixed[n] then
    return false, ("slot %d is fixed in setup()"):format(n)
  end
  if not S.dynamic[n] then
    return false, ("slot %d is empty"):format(n)
  end
  S.dynamic[n] = nil
  touch()
  emit("clear", n)
  return true
end

--- Empty every dynamic slot; the fixed ones stay.
---@return integer removed
function M.clear_all()
  local removed = vim.tbl_count(S.dynamic)
  if removed == 0 then
    return 0
  end
  S.dynamic = {}
  touch()
  emit("clear_all", nil)
  return removed
end

--- Move slot `from` to number `to`; when `to` is occupied the two swap.
--- Neither number may be a fixed slot.
---@param from integer
---@param to integer
---@return boolean ok
---@return string|nil err
function M.move(from, to)
  if not valid_n(to) then
    return false, "slot numbers are positive whole numbers"
  end
  if S.fixed[from] or S.fixed[to] then
    return false, "a fixed slot cannot be moved"
  end
  local a = S.dynamic[from]
  if not a then
    return false, ("slot %d is empty"):format(from)
  end
  if from == to then
    return true
  end
  S.dynamic[to], S.dynamic[from] = a, S.dynamic[to]
  touch()
  emit("move", to)
  return true
end

--- Subscribe to changes. `fn(event, n)` runs after each mutation (event is
--- "set", "clear", "clear_all", "move" or "reload"). Returns an id for
--- `off()`.
---@param fn fun(event: string, n: integer|nil)
---@return integer id
function M.on_change(fn)
  local id = S.next_listener
  S.next_listener = id + 1
  S.listeners[id] = fn
  return id
end

---@param id integer
function M.off(id)
  S.listeners[id] = nil
end

-- Lifecycle -------------------------------------------------------------

--- Install the fixed slots of the current config and read the data file of the
--- current scope. Pending changes of the previous scope are written first.
--- Call it from `setup()` and again whenever the scope may have changed
--- (`DirChanged` for the `project` scope).
function M.reload()
  local flushed = M.flush()
  S.gen = S.gen + 1

  local cfg = config.get()
  S.fixed = {}
  for n, slot in pairs(cfg.slots) do
    if valid_n(n) and type(slot) == "table" and type(slot.kind) == "string" then
      local copy = vim.deepcopy(slot)
      copy.n, copy.fixed = nil, nil
      S.fixed[n] = copy
    else
      say_once(("setup(): slots[%s] is not a valid slot and is ignored"):format(vim.inspect(n)))
    end
  end

  -- A write that failed must not be followed by a read that replaces the
  -- unsaved slots: when the scope is the same file, keep what is in memory
  -- and stay dirty so the next change retries.
  if not flushed and S.dirty and cfg.persist and S.path and S.path == (scope_path()) then
    emit("reload", nil)
    return
  end
  if not flushed and S.dirty then
    say("changes to the slots of the previous scope could not be saved and are lost")
  end

  -- Slots of a kind that never reaches a file (`cmd`, `lua`) were added by the
  -- host in this session: they belong to the session, not to a project, so a
  -- change of project must not make them vanish.
  local carry = {}
  for n, slot in pairs(S.dynamic) do
    if not persistable(slot.kind) then
      carry[n] = slot
    end
  end

  S.dirty = false
  load_file()

  for n, slot in pairs(carry) do
    if S.fixed[n] or S.dynamic[n] then
      -- What is saved wins: writing over it would lose it from the file.
      say(
        ("slot %d (%s, this session only) was replaced by the one saved for this project"):format(
          n,
          slot.kind
        )
      )
    else
      S.dynamic[n] = slot
    end
  end
  emit("reload", nil)
end

--- Would `reload()` read another data file than the one that is loaded? False
--- when nothing is persisted, and for a change of directory inside one project.
---@return boolean
function M.scope_changed()
  if not config.get().persist then
    return false
  end
  return (scope_path()) ~= S.path
end

--- Forget everything and stop the timer (tests, and a host disabling the
--- feature). Pending changes are NOT written.
function M.reset()
  if S.timer then
    S.timer:stop()
    S.timer:close()
    S.timer = nil
  end
  S.fixed, S.dynamic = {}, {}
  S.path, S.root, S.blocked = nil, nil, nil
  S.dirty = false
  S.gen = S.gen + 1
  S.listeners, S.reported = {}, {}
end

return M
