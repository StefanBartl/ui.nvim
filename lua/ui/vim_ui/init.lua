---@module 'ui.vim_ui'
--- `vim.ui.select` and `vim.ui.input` through the kit, so the dozens of plugin calls that go through them look
--- like every other dialog without being changed.
---
---   * `vim.ui.select`: a short list (up to `buttons_max` entries whose button row fits the screen) is a
---     button dialog (`kit.confirm`), a medium one (up to `chooser_max`) the kit's chooser (`kit.select`), a longer
---     one goes to `fallback_select` (a picker such as `Snacks.picker.select`) or to the `vim.ui.select` that
---     was there when this was switched on. A `kind` listed in `passthrough_kinds` (`opts.kind` of a caller:
---     "codeaction", ...) always goes to that fallback.
---   * `vim.ui.input`: `kit.input` with `prompt`, `default` and `completion`.
---
--- The contract of the two functions is kept: `on_choice(item, idx)` with the ORIGINAL entry (`format_item` only
--- decides what is shown), `on_choice(nil, nil)` and `on_confirm(nil)` when dismissed, each called once. A float
--- that cannot open hands the call to the fallback instead of answering "cancelled".
---
--- Explicit-only, like `ui.notify`: `ui.setup({ vim_ui = true })` or `require("ui.vim_ui").enable()`.
--- `disable()` puts the previous functions back; one somebody else wrapped on top of ours is left alone.
---
--- This does not use `lib.nvim.ui.dialog`: its native fallback asks through `vim.ui.select`, which would be this
--- provider again. It talks to the kit directly and has its own fallback.

local M = {}

---@class Ui.VimUi.Opts
---@field select? boolean # replace `vim.ui.select` (default true)
---@field input? boolean # replace `vim.ui.input` (default true)
---@field buttons_max? integer # up to this many entries (and only if the buttons fit) the choice is a button dialog; 0: never (default 4)
---@field chooser_max? integer # up to this many entries the kit's chooser; more go to the fallback (default 12)
---@field fallback_select? fun(items: any[], opts: table, on_choice: fun(item: any, idx: integer|nil)) # for the long lists and `passthrough_kinds`; default: the `vim.ui.select` found when this was switched on
---@field passthrough_kinds? string[] # `opts.kind` values that always go to the fallback

---@type Ui.VimUi.Opts
local DEFAULTS = {
  select = true,
  input = true,
  buttons_max = 4,
  chooser_max = 12,
  fallback_select = nil,
  passthrough_kinds = {},
}

---@type Ui.VimUi.Opts
local cfg = vim.deepcopy(DEFAULTS)

local enabled = false

--- What was in `vim.ui.select` / `vim.ui.input` before this took them over.
---@type { select: function|nil, input: function|nil }
local previous = {}

--- The runtime's own functions, for a fallback that has nothing else (never ours: that would loop).
local native = { select = vim.ui.select, input = vim.ui.input }

local function warn(msg)
  vim.notify("[ui.vim_ui] " .. msg, vim.log.levels.WARN)
end

---@param opts table|nil
---@return Ui.VimUi.Opts
local function normalize(opts)
  -- every `enable(opts)` starts from the defaults, like a `setup()`: options of an earlier call do not stay
  local out = vim.deepcopy(DEFAULTS)
  if type(opts) ~= "table" then
    return out
  end
  for _, key in ipairs({ "select", "input" }) do
    if opts[key] ~= nil then
      if type(opts[key]) == "boolean" then
        out[key] = opts[key]
      else
        warn(("%s must be true or false, ignored"):format(key))
      end
    end
  end
  for _, key in ipairs({ "buttons_max", "chooser_max" }) do
    local v = opts[key]
    if v ~= nil then
      if type(v) == "number" and v >= 0 and v == math.floor(v) then
        out[key] = v
      else
        warn(("%s must be a whole number >= 0, ignored"):format(key))
      end
    end
  end
  if opts.fallback_select ~= nil then
    if type(opts.fallback_select) == "function" then
      out.fallback_select = opts.fallback_select
    else
      warn("fallback_select must be a function, ignored")
    end
  end
  if opts.passthrough_kinds ~= nil then
    if type(opts.passthrough_kinds) == "table" then
      out.passthrough_kinds = vim.deepcopy(opts.passthrough_kinds)
    else
      warn("passthrough_kinds must be a list of strings, ignored")
    end
  end
  return out
end

---@return function
local function fallback_select()
  local fn = cfg.fallback_select or previous.select
  if fn == nil or fn == M.select then
    return native.select
  end
  return fn
end

---@return function
local function fallback_input()
  local fn = previous.input
  if fn == nil or fn == M.input then
    return native.input
  end
  return fn
end

---@param kind any
---@return boolean
local function passes_through(kind)
  return type(kind) == "string" and vim.tbl_contains(cfg.passthrough_kinds or {}, kind)
end

---@param item any
---@param format_item? fun(item: any): any
---@return string
local function label_of(item, format_item)
  local shown = format_item and format_item(item) or item
  if type(shown) ~= "string" then
    shown = tostring(shown)
  end
  return (shown:gsub("[\r\n]+", " "))
end

--- The title a dialog shows for a `vim.ui` prompt (they end in ": " or ":" by habit).
---@param prompt any
---@param default string
---@return string
local function title_of(prompt, default)
  if type(prompt) ~= "string" or vim.trim(prompt) == "" then
    return default
  end
  return (vim.trim(prompt):gsub("[:：]%s*$", ""))
end

--- Whether the labels fit as one row of buttons on this screen.
---@param labels string[]
---@return boolean
local function buttons_fit(labels)
  local width = 0
  for _, label in ipairs(labels) do
    width = width + vim.fn.strdisplaywidth(label) + 4
  end
  return width <= math.max(20, vim.o.columns - 12)
end

--- Open a kit dialog whose callback may fire inside the open call. A float that cannot open answers
--- "cancelled" there and returns nil: that answer is dropped and the call goes to the fallback. For a dialog that
--- did open, an answer given inside the call is delivered on the next loop turn, later ones at once, each once.
---@param open fun(answer: fun(...)): any|nil  # opens the dialog, returns its surface (nil: could not open)
---@param deliver fun(...) # the caller's continuation
---@param fallback fun()
local function open_or_fallback(open, deliver, fallback)
  local opening, done, pending = true, false, nil
  local function fire(...)
    if done then
      return
    end
    done = true
    deliver(...)
  end
  local ok, surf = pcall(open, function(...)
    if opening then
      pending = pending or vim.F.pack_len(...)
    else
      fire(...)
    end
  end)
  opening = false
  if not ok then
    error(surf, 0)
  end
  if surf == nil then
    fallback()
  elseif pending then
    local args = pending
    vim.schedule(function()
      fire(vim.F.unpack_len(args))
    end)
  end
end

--- `vim.ui.select` through the kit.
---@param items any[]
---@param opts? table
---@param on_choice fun(item: any|nil, idx: integer|nil)
function M.select(items, opts, on_choice)
  opts = opts or {}
  local function hand_over()
    return fallback_select()(items, opts, on_choice)
  end
  if
    type(on_choice) ~= "function"
    or type(items) ~= "table"
    or #items == 0
    or passes_through(opts.kind)
  then
    return hand_over()
  end

  local n = #items
  local kit = require("ui.kit")
  local title = title_of(opts.prompt, "Select")

  if n <= (cfg.buttons_max or 0) then
    local labels = {}
    for i, item in ipairs(items) do
      labels[i] = label_of(item, opts.format_item)
    end
    if buttons_fit(labels) then
      return open_or_fallback(function(deliver)
        return kit.confirm({
          question = title,
          choices = labels,
          default = 1,
          on_answer = function(_, idx)
            deliver(idx)
          end,
        })
      end, function(idx)
        if idx and items[idx] ~= nil then
          on_choice(items[idx], idx)
        else
          on_choice(nil, nil)
        end
      end, hand_over)
    end
  end

  if n <= math.max(cfg.chooser_max or 0, cfg.buttons_max or 0) then
    return open_or_fallback(function(deliver)
      return kit.select({
        items = items,
        format_item = opts.format_item,
        title = title,
        on_select = function(_, idx)
          deliver(idx)
        end,
        on_cancel = function()
          deliver(nil)
        end,
      })
    end, function(idx)
      if idx and items[idx] ~= nil then
        on_choice(items[idx], idx)
      else
        on_choice(nil, nil)
      end
    end, hand_over)
  end

  return hand_over()
end

--- `vim.ui.input` through the kit.
---@param opts? table
---@param on_confirm fun(input: string|nil)
function M.input(opts, on_confirm)
  opts = opts or {}
  if type(on_confirm) ~= "function" then
    return fallback_input()(opts, on_confirm)
  end
  local kit = require("ui.kit")
  return open_or_fallback(function(deliver)
    return kit.input({
      prompt = title_of(opts.prompt, "Input"),
      default = opts.default,
      completion = opts.completion,
      on_submit = function(value)
        deliver(value)
      end,
      on_cancel = function()
        deliver(nil)
      end,
    })
  end, function(value)
    on_confirm(value)
  end, function()
    return fallback_input()(opts, on_confirm)
  end)
end

--- Install or take out the two functions as `cfg` and `enabled` say.
local function apply()
  for _, slot in ipairs({ "select", "input" }) do
    local want = enabled and cfg[slot]
    local mine = M[slot]
    if want then
      if vim.ui[slot] ~= mine then
        previous[slot] = vim.ui[slot]
        vim.ui[slot] = mine
      end
    elseif vim.ui[slot] == mine then
      vim.ui[slot] = previous[slot] or native[slot]
      previous[slot] = nil
    end
    -- else: nobody of ours is in the slot (or somebody wrapped it): leave it
  end
end

--- Switch the provider on (again, with other options).
---@param opts? Ui.VimUi.Opts
function M.enable(opts)
  cfg = normalize(opts)
  enabled = true
  apply()
end

--- Put the previous `vim.ui.select` / `vim.ui.input` back. A function that somebody installed on top of ours
--- stays; ours forwards to the previous one while it is in the chain.
function M.disable()
  enabled = false
  apply()
end

---@return boolean
function M.is_enabled()
  return enabled
end

--- A copy of the options in force.
---@return Ui.VimUi.Opts
function M.config()
  return vim.deepcopy(cfg)
end

return M
