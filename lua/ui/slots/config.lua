---@module 'ui.slots.config'
--- Defaults and validation of `ui.slots`. Pure data, no windows, nothing is
--- registered when this is required.
---
--- `setup(opts)` deep-merges `opts` over the shipped defaults; `get()` returns
--- the live table. `issues()` lists what is wrong with the merged result as
--- strings (it never raises) so `:checkhealth ui` and `setup()` can both
--- report it.

require("ui.slots.@types")

local M = {}

---@type Ui.Slots.Config
local DEFAULTS = {
  enabled = false,
  show = false,
  layout = "chips",
  side = "right",
  width = 0.25,
  style = "rounded",
  scope = "project",
  persist = true,
  target = "current",
  clipboard = { "+", "*", '"' },
  preview = { mode = "key", delay = 150, max_kb = 1536, max_lines = 4000, fetch = false },
  overflow = "accordion",
  keys = {},
  slots = {},
  kinds = {},
  -- `cmd` and `lua` run code, so a data file may never introduce them: they
  -- come from `setup()` only.
  persistable_kinds = { "file", "url", "yank", "mark" },
  save_delay_ms = 100,
  max_file_kb = 256,
  max_string_len = 4096,
}

M.DEFAULTS = DEFAULTS

---@type Ui.Slots.Config
local current = vim.deepcopy(DEFAULTS)

local ENUMS = {
  layout = { "chips", "panel" },
  side = { "left", "right" },
  scope = { "project", "global" },
  target = { "current", "split", "vsplit", "tab" },
  overflow = { "accordion" },
}

local PREVIEW_MODES = { "key", "auto", "off" }

---@param list string[]
---@param value any
---@return boolean
local function one_of(list, value)
  return vim.tbl_contains(list, value)
end

--- Highest slot number anywhere (the store, a data file and `slots` agree on it).
M.MAX_N = 1000000

local MINIMA = { width = 0, save_delay_ms = 0, max_file_kb = 1, max_string_len = 1 }
local PREVIEW_MINIMA = { delay = 0, max_kb = 0, max_lines = 0 }

---@param v any
---@param min number
---@return boolean
local function valid_number(v, min)
  return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v >= min
end

--- Findings of the last `setup()`, collected before invalid values were
--- replaced by their defaults.
---@type string[]
local last_issues = {}

--- Replace every invalid value of `cfg` by its default, so nothing downstream
--- ever does arithmetic on a string. `M.issues()` still reports what was wrong.
---@param cfg table
local function sanitize(cfg)
  for key, list in pairs(ENUMS) do
    if not one_of(list, cfg[key]) then
      cfg[key] = DEFAULTS[key]
    end
  end
  for _, key in ipairs({ "enabled", "show", "persist" }) do
    if type(cfg[key]) ~= "boolean" then
      cfg[key] = DEFAULTS[key]
    end
  end
  for key, min in pairs(MINIMA) do
    if not valid_number(cfg[key], min) then
      cfg[key] = DEFAULTS[key]
    end
  end
  if type(cfg.style) ~= "string" and type(cfg.style) ~= "table" then
    cfg.style = DEFAULTS.style
  end
  if type(cfg.preview) ~= "table" then
    cfg.preview = vim.deepcopy(DEFAULTS.preview)
  end
  if not one_of(PREVIEW_MODES, cfg.preview.mode) then
    cfg.preview.mode = DEFAULTS.preview.mode
  end
  for key, min in pairs(PREVIEW_MINIMA) do
    if not valid_number(cfg.preview[key], min) then
      cfg.preview[key] = DEFAULTS.preview[key]
    end
  end
  if type(cfg.preview.fetch) ~= "boolean" then
    cfg.preview.fetch = DEFAULTS.preview.fetch
  end
  local ok_clip = type(cfg.clipboard) == "table" and #cfg.clipboard > 0
  if ok_clip then
    for _, reg in ipairs(cfg.clipboard) do
      if type(reg) ~= "string" or #reg ~= 1 then
        ok_clip = false
      end
    end
  end
  if not ok_clip then
    cfg.clipboard = vim.deepcopy(DEFAULTS.clipboard)
  end
  if type(cfg.persistable_kinds) ~= "table" then
    cfg.persistable_kinds = vim.deepcopy(DEFAULTS.persistable_kinds)
  end
  for _, key in ipairs({ "keys", "slots", "kinds" }) do
    if type(cfg[key]) ~= "table" then
      cfg[key] = {}
    end
  end
  if cfg.data_dir ~= nil and (type(cfg.data_dir) ~= "string" or cfg.data_dir == "") then
    cfg.data_dir = nil
  end
end

--- Merge `opts` over the defaults. A `slots` table is taken as given: it is the
--- user's list, not a set of overrides, and its integer keys must not be
--- merged with the (empty) default.
---
--- Never raises and never hands out an unusable value: what is wrong (an
--- unknown option, a value of the wrong type or range) is replaced by the
--- default and listed by `M.issues()`.
---@param opts Ui.Slots.Opts|nil
---@return Ui.Slots.Config
function M.setup(opts)
  opts = type(opts) == "table" and opts or {}
  local found = {}

  for key in pairs(opts) do
    if DEFAULTS[key] == nil and key ~= "data_dir" then
      found[#found + 1] = ("unknown option '%s'"):format(tostring(key))
    end
  end
  if type(opts.preview) == "table" then
    for key in pairs(opts.preview) do
      if DEFAULTS.preview[key] == nil then
        found[#found + 1] = ("preview: unknown option '%s'"):format(tostring(key))
      end
    end
  end
  for _, key in ipairs({ "slots", "kinds", "keys", "clipboard", "persistable_kinds" }) do
    if opts[key] ~= nil and type(opts[key]) ~= "table" then
      found[#found + 1] = ("%s: %s is not a table"):format(key, vim.inspect(opts[key]))
    end
  end

  local slots = opts.slots
  local kinds = opts.kinds
  local keys = opts.keys
  local clipboard = opts.clipboard
  local persistable = opts.persistable_kinds
  local rest = vim.tbl_extend("force", {}, opts)
  rest.slots, rest.kinds, rest.keys, rest.clipboard, rest.persistable_kinds =
    nil, nil, nil, nil, nil

  local merged = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), rest)
  merged.slots = type(slots) == "table" and slots or {}
  merged.kinds = type(kinds) == "table" and kinds or {}
  merged.keys = type(keys) == "table" and vim.deepcopy(keys) or {}
  if type(clipboard) == "table" then
    merged.clipboard = vim.deepcopy(clipboard)
  end
  if type(persistable) == "table" then
    merged.persistable_kinds = vim.deepcopy(persistable)
  end

  vim.list_extend(found, M.issues(merged))
  sanitize(merged)
  last_issues = found
  current = merged
  return current
end

---@return Ui.Slots.Config
function M.get()
  return current
end

--- Back to the shipped defaults (tests, and `setup()` of a host that reloads).
function M.reset()
  current = vim.deepcopy(DEFAULTS)
  last_issues = {}
end

---@param cfg table
---@param key string
---@param issues string[]
local function check_enum(cfg, key, issues)
  if not one_of(ENUMS[key], cfg[key]) then
    issues[#issues + 1] = ("%s: %s is not one of %s"):format(
      key,
      vim.inspect(cfg[key]),
      table.concat(ENUMS[key], ", ")
    )
  end
end

---@param cfg table
---@param key string
---@param min number
---@param issues string[]
local function check_number(cfg, key, min, issues)
  local v = cfg[key]
  if not valid_number(v, min) then
    issues[#issues + 1] = ("%s: %s is not a number >= %s"):format(
      key,
      vim.inspect(v),
      tostring(min)
    )
  end
end

--- What is wrong, as plain strings. With a table: that table, checked as it
--- stands. Without: what the last `setup()` found in the options it was given
--- (the config in use has been repaired by then, so it is always usable).
---@param cfg table|nil
---@return string[]
function M.issues(cfg)
  if cfg == nil then
    return vim.list_slice(last_issues)
  end
  local issues = {}

  for key in pairs(ENUMS) do
    check_enum(cfg, key, issues)
  end
  for _, key in ipairs({ "enabled", "show", "persist" }) do
    if type(cfg[key]) ~= "boolean" then
      issues[#issues + 1] = ("%s: %s is not a boolean"):format(key, vim.inspect(cfg[key]))
    end
  end

  check_number(cfg, "width", 0, issues)
  check_number(cfg, "save_delay_ms", 0, issues)
  check_number(cfg, "max_file_kb", 1, issues)
  check_number(cfg, "max_string_len", 1, issues)

  if type(cfg.style) ~= "string" and type(cfg.style) ~= "table" then
    issues[#issues + 1] = "style: must be a preset name or a table"
  end

  if type(cfg.clipboard) ~= "table" or #cfg.clipboard == 0 then
    issues[#issues + 1] = "clipboard: must be a non-empty list of registers"
  else
    for _, reg in ipairs(cfg.clipboard) do
      if type(reg) ~= "string" or #reg ~= 1 then
        issues[#issues + 1] = ("clipboard: %s is not a one-character register"):format(
          vim.inspect(reg)
        )
      end
    end
  end

  local pv = cfg.preview
  if type(pv) ~= "table" then
    issues[#issues + 1] = "preview: must be a table"
  else
    if not one_of(PREVIEW_MODES, pv.mode) then
      issues[#issues + 1] = ("preview.mode: %s is not one of %s"):format(
        vim.inspect(pv.mode),
        table.concat(PREVIEW_MODES, ", ")
      )
    end
    for _, key in ipairs({ "delay", "max_kb", "max_lines" }) do
      check_number(pv, key, 0, issues)
    end
    if type(pv.fetch) ~= "boolean" then
      issues[#issues + 1] = ("preview.fetch: %s is not a boolean"):format(vim.inspect(pv.fetch))
    end
  end

  if type(cfg.persistable_kinds) ~= "table" then
    issues[#issues + 1] = "persistable_kinds: must be a list of kind names"
  end

  if type(cfg.keys) == "table" then
    vim.list_extend(issues, require("ui.slots.bindings").issues(cfg.keys))
  end

  if type(cfg.slots) ~= "table" then
    issues[#issues + 1] = "slots: must be a table of [n] = { kind = ..., ... }"
  else
    for n, slot in pairs(cfg.slots) do
      if type(n) ~= "number" or n < 1 or n > M.MAX_N or n ~= math.floor(n) then
        issues[#issues + 1] = ("slots: key %s is not a whole number from 1 to %d"):format(
          vim.inspect(n),
          M.MAX_N
        )
      elseif type(slot) ~= "table" or type(slot.kind) ~= "string" or slot.kind == "" then
        issues[#issues + 1] = ("slots[%d]: needs a table with a kind"):format(n)
      end
    end
  end

  return issues
end

return M
