---@module 'ui.slots'
--- Numbered slots: each one a configurable action (open a file or an address,
--- copy text, run a command or a function, jump to a mark) instead of just a
--- path. This module is the public face: the Lua API and the `:UI slots`
--- command. Behind it, `ui.slots.store` holds the table and the data file,
--- `ui.slots.kinds.registry` knows what each kind does and
--- `ui.slots.config` the options. See `slots-design.md` for the whole picture.
---
--- Off until asked: `ui.setup({ slots = true })` (or a table with
--- `enabled = true`) switches it on at startup; `:UI slots ...` and every API
--- function switch it on for the session when it is not. Requiring this module
--- registers nothing -- no command, no keymap, no autocommand.
---
---```lua
--- local slots = require("ui.slots")
--- slots.setup({ slots = { [1] = { kind = "file", path = "~/notes.md" } } })
--- slots.apply(1)
--- slots.add()                  -- the current file, next free number
--- slots.yank(2)                -- copy what slot 2 stands for
---```

require("ui.slots.@types")

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local resolve = require("ui.slots.resolve")
local store = require("ui.slots.store")
local util = require("ui.slots.util")

local M = {}

local enabled = false

--- The slot applied last, for the views (the bar follows it).
---@type integer|nil
local last_applied = nil

---@param msg string
---@param level integer|nil
local function say(msg, level)
  util.notify(msg, level)
end

--- A whole number from a command word, or nil (`0x10` and `1e3` are not numbers here).
---@param s any
---@return integer|nil
local function number(s)
  local n = s
  if type(s) == "string" and s:match("^%d+$") then
    n = tonumber(s)
  end
  if type(n) == "number" and n == math.floor(n) and n >= 1 and n <= config.MAX_N then
    return n
  end
  return nil
end

-- Lifecycle -------------------------------------------------------------

---@return boolean
function M.is_enabled()
  return enabled
end

--- Switch the feature on: kinds from the config, the slots, keymaps and
--- autocommands. Idempotent.
function M.enable()
  if enabled then
    return
  end
  enabled = true
  for _, err in ipairs(registry.load(config.get().kinds)) do
    say(err)
  end
  store.reload()
  if config.get().show then
    require("ui.slots.view.chips").open()
  end
  require("ui.slots.bindings").attach({
    apply = function(n, opts)
      return M.apply(n, opts)
    end,
    add = function()
      return M.add()
    end,
    panel = function()
      return M.panel()
    end,
  })
end

--- Switch the feature off: pending changes are written, keymaps and
--- autocommands removed. The slots stay in the data file.
function M.disable()
  if not enabled then
    return
  end
  enabled = false
  store.flush()
  local bar = package.loaded["ui.slots.view.chips"]
  if bar then
    bar.close()
  end
  require("ui.slots.bindings").detach()
end

--- Configure, and switch on when `enabled = true`. Problems with the options
--- are reported, never raised; a wrong value is replaced by its default.
---@param opts Ui.Slots.Opts|nil
---@return Ui.Slots.Config
function M.setup(opts)
  local was_enabled = enabled
  -- A setup() in the middle of a session must not close a bar the user opened.
  local bar = package.loaded["ui.slots.view.chips"]
  local bar_was_open = bar ~= nil and bar.wanted()
  if was_enabled then
    M.disable()
  end
  local cfg = config.setup(opts)
  for _, issue in ipairs(config.issues()) do
    say("setup(): " .. issue)
  end
  if cfg.enabled or was_enabled then
    M.enable()
    if bar_was_open then
      require("ui.slots.view.chips").open()
    end
  end
  return cfg
end

local function ensure()
  if not enabled then
    M.enable()
  end
end

-- Using slots -----------------------------------------------------------

---@param n integer|string
---@return Ui.Slots.Slot|nil
function M.get(n)
  ensure()
  local num = number(n)
  return num and store.get(num) or nil
end

---@return Ui.Slots.Slot[]
function M.list()
  ensure()
  return store.list()
end

--- Run slot `n`.
---@param n integer|string
---@param opts { count?: integer }|nil
---@return boolean ok
---@return string|nil err
function M.apply(n, opts)
  ensure()
  local num = number(n)
  if not num then
    say(("%s is not a slot number"):format(vim.inspect(n)))
    return false, "not a slot number"
  end
  local slot = store.get(num)
  if not slot then
    say(("slot %d is empty"):format(num))
    return false, "empty"
  end
  local ok, err = registry.apply(slot, { count = opts and opts.count })
  if not ok then
    say(("slot %d: %s"):format(num, err))
    return false, err
  end
  last_applied = num
  local bar = package.loaded["ui.slots.view.chips"]
  if bar then
    bar.set_focus(num)
  end
  return true
end

--- The slot applied last this session.
---@return integer|nil
function M.last_applied()
  return last_applied
end

--- Put a slot in the next free number (or at `n`, when that is free). Without
--- a slot: the file of the current buffer.
---@param slot table|nil
---@param n integer|string|nil
---@return integer|nil n
---@return string|nil err
function M.add(slot, n)
  ensure()
  if slot == nil then
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" or vim.bo.buftype ~= "" then
      say("this buffer has no file")
      return nil, "no file"
    end
    local path = vim.fs.normalize(name)
    -- Braces in a file name are written doubled: `{{` is a literal `{`.
    slot = { kind = "file", path = (path:gsub("{", "{{"):gsub("}", "}}")) }
    -- Already there? Say which slot instead of adding a twin.
    local normkey = require("lib.nvim.fs.normkey")
    local key = normkey(path)
    for _, existing in ipairs(store.list()) do
      -- Only slots whose path is a plain path: one with a placeholder stands
      -- for whatever the editor looks like when it runs, not for this file.
      if
        existing.kind == "file"
        and type(existing.path) == "string"
        and not resolve.has_placeholder(existing.path)
      then
        local text = resolve.resolve(existing.path, {})
        if text ~= "" and normkey(vim.fs.normalize(text)) == key then
          say(("already in slot %d"):format(existing.n), vim.log.levels.INFO)
          return existing.n
        end
      end
    end
  end

  -- Whether a slot is trusted is not for the caller to say: `fixed` is what the
  -- store sets for the slots of setup(), and a copy of one of them (`add(get(n))`)
  -- is not one.
  if type(slot) ~= "table" then
    say("a slot needs a kind")
    return nil, "a slot needs a kind"
  end
  slot = vim.deepcopy(slot)
  slot.fixed = nil
  local err = registry.validate(slot)
  if err then
    say(err)
    return nil, err
  end

  local num
  if n ~= nil then
    num = number(n)
    if not num then
      say(("%s is not a slot number"):format(vim.inspect(n)))
      return nil, "not a slot number"
    end
    if store.get(num) then
      say(("slot %d is taken; clear it first"):format(num))
      return nil, "taken"
    end
    local ok, set_err = store.set(num, slot)
    if not ok then
      say(set_err)
      return nil, set_err
    end
  else
    local add_err
    num, add_err = store.add(slot)
    if not num then
      say(add_err)
      return nil, add_err
    end
  end
  local r = registry.render(store.get(num))
  say(("slot %d: %s"):format(num, r.label), vim.log.levels.INFO)
  return num
end

--- Copy what slot `n` stands for (its path, address or text).
---@param n integer|string
---@return boolean ok
---@return string|nil err
function M.yank(n)
  ensure()
  local num = number(n)
  local slot = num and store.get(num)
  if not slot then
    say(("slot %s is empty"):format(tostring(n)))
    return false, "empty"
  end
  local text, err = registry.text(slot)
  if not text then
    say(("slot %d: %s"):format(num, err))
    return false, err
  end
  local ok, put_err = require("ui.slots.kinds.yank").put(text)
  if not ok then
    say(("slot %d: %s"):format(num, put_err))
  end
  return ok, put_err
end

--- Empty slot `n`.
---@param n integer|string
---@return boolean ok
---@return string|nil err
function M.clear(n)
  ensure()
  local num = number(n)
  if not num then
    say(("%s is not a slot number"):format(vim.inspect(n)))
    return false, "not a slot number"
  end
  local ok, err = store.clear(num)
  if not ok then
    say(err)
  end
  return ok, err
end

--- Empty every slot that is not fixed in `setup()`.
---@return integer removed
function M.clear_all()
  ensure()
  local removed = store.clear_all()
  say(("%d slot(s) cleared"):format(removed), vim.log.levels.INFO)
  return removed
end

--- Move slot `from` to number `to` (the two swap when `to` is taken).
---@param from integer|string
---@param to integer|string
---@return boolean ok
---@return string|nil err
function M.move(from, to)
  ensure()
  local a, b = number(from), number(to)
  if not (a and b) then
    say("move needs two slot numbers")
    return false, "not a slot number"
  end
  local ok, err = store.move(a, b)
  if not ok then
    say(err)
  end
  return ok, err
end

--- Open the slot panel (the working view), or close it.
---@return boolean now_open
function M.panel()
  ensure()
  return require("ui.slots.view.panel").toggle()
end

--- Add a slot in the editor (`n` nil), or change slot `n`.
---@param n integer|string|nil
---@param opts { kind?: string }|nil
function M.edit(n, opts)
  ensure()
  local num = n ~= nil and number(n) or nil
  if n ~= nil and not num then
    say(("%s is not a slot number"):format(vim.inspect(n)))
    return
  end
  local path = nil
  local name = vim.api.nvim_buf_get_name(0)
  if not num and name ~= "" and vim.bo.buftype == "" then
    path = vim.fs.normalize(name)
  end
  require("ui.slots.view.editor").open({
    n = num,
    kind = opts and opts.kind or nil,
    defaults = path and { path = path } or nil,
  })
end

--- Register a kind (see `ui.slots.kinds.registry`).
---@param name string
---@param kind Ui.Slots.Kind
---@param opts { force?: boolean }|nil
---@return boolean ok
---@return string|nil err
function M.register_kind(name, kind, opts)
  return registry.register(name, kind, opts)
end

-- :UI slots -------------------------------------------------------------

--- One line per slot, for `:UI slots` without an argument.
---@return string[]
function M.describe()
  local lines = {}
  for _, slot in ipairs(store.list()) do
    local r = registry.render(slot)
    lines[#lines + 1] = ("%3d  %s %s  (%s%s%s)"):format(
      slot.n,
      r.icon,
      r.label,
      slot.kind,
      slot.fixed and ", fixed" or "",
      r.missing and ", missing" or ""
    )
  end
  return lines
end

--- `:UI slots ...`. `args[1]` is "slots", the rest is what the user typed.
---@param args string[]
function M.command(args)
  local was_enabled = enabled
  ensure()
  local sub = args[2]

  if sub == nil or sub == "" or sub == "list" then
    local lines = M.describe()
    if #lines == 0 then
      say("no slots yet; :UI slots add puts the current file in one", vim.log.levels.INFO)
    else
      say("slots\n" .. table.concat(lines, "\n"), vim.log.levels.INFO)
    end
    return
  end

  local num = number(sub)
  if num then
    M.apply(num, { count = vim.v.count })
    return
  end

  if sub == "add" then
    M.add(nil, args[3])
  elseif sub == "yank" then
    M.yank(args[3])
  elseif sub == "clear" then
    if args[3] == "all" then
      M.clear_all()
    else
      M.clear(args[3])
    end
  elseif sub == "move" then
    M.move(args[3], args[4])
  elseif sub == "kinds" then
    say("kinds: " .. table.concat(registry.names(), ", "), vim.log.levels.INFO)
  elseif sub == "panel" then
    M.panel()
  elseif sub == "edit" then
    M.edit(args[3])
  elseif
    (sub == "toggle" or sub == "open" or sub == "close") and config.get().layout == "panel"
  then
    -- layout = "panel": the working view instead of the bar.
    local panel = require("ui.slots.view.panel")
    if sub == "close" then
      panel.close()
    elseif sub == "open" and not panel.is_open() or sub == "toggle" then
      panel.toggle()
    end
  elseif sub == "toggle" or sub == "open" or sub == "close" then
    local bar = require("ui.slots.view.chips")
    if sub == "open" then
      bar.open()
    elseif sub == "close" then
      bar.close()
    elseif was_enabled or not bar.wanted() then
      bar.toggle()
    end
    -- (else: `show = true` opened the bar when this very command switched the
    -- feature on -- that was the toggle.)
    if bar.wanted() and not bar.is_open() then
      say("the bar is on, and shows up with the first slot", vim.log.levels.INFO)
    end
  else
    say(("unknown subcommand '%s'"):format(sub))
  end
end

local SUBCOMMANDS = {
  "list",
  "add",
  "yank",
  "clear",
  "move",
  "kinds",
  "toggle",
  "open",
  "close",
  "panel",
  "edit",
}

--- Completion for `:UI slots`. `parts` is the command line split into words
--- (`UI`, `slots`, ...), `index` the position of the word being completed
--- within the arguments after `slots` (1 = the subcommand).
---@param arglead string
---@param sub string|nil  # the subcommand typed so far (nil while completing it)
---@param index integer
---@return string[]
function M.complete(arglead, sub, index)
  -- The numbers come from the data file; reading it does not need the
  -- keymaps and autocommands, so completion does not switch the feature on.
  if not enabled then
    store.reload()
  end
  local out = {}
  if index == 1 then
    vim.list_extend(out, SUBCOMMANDS)
    for _, slot in ipairs(store.list()) do
      out[#out + 1] = tostring(slot.n)
    end
  elseif sub == "clear" and index == 2 then
    out[#out + 1] = "all"
    for _, slot in ipairs(store.list()) do
      out[#out + 1] = tostring(slot.n)
    end
  elseif sub == "yank" or sub == "move" or sub == "edit" then
    for _, slot in ipairs(store.list()) do
      out[#out + 1] = tostring(slot.n)
    end
  elseif sub == "clear" then
    return {}
  end
  return vim.tbl_filter(function(item)
    return vim.startswith(item, arglead)
  end, out)
end

--- Forget the session state (tests).
function M.reset()
  M.disable()
  local bar = package.loaded["ui.slots.view.chips"]
  if bar then
    bar.reset()
  end
  last_applied = nil
  enabled = false
end

return M
