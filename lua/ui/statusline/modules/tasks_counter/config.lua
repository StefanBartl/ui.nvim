---@module 'ui.statusline.modules.tasks_counter.config'
--- Options of the `tasks_counter` statusline segment: the shipped defaults,
--- validation, and where the task vault / area are resolved from.
---
--- Kept apart from `init.lua` because that file must return the bare render
--- function (`ui.statusline.render` only accepts a function or a string per
--- module key), so it has no room for a `setup`. A host configures through
--- `require("ui.statusline.modules.tasks_counter.config").setup({...})` or,
--- equivalently, `require("ui").setup({ tasks = {...} })`.
---
--- Nothing here touches the nvim-config task engine (`lua/tasks/`): the
--- segment only reads the vault's Markdown files, so it works on any machine
--- that has the vault checked out and degrades to "" everywhere else.

local notify = require("lib.nvim.notify").create("[ui.statusline.modules.tasks_counter]")

local uv = vim.uv or vim.loop

local M = {}

--- Every option, with its shipped default. Options whose default is `nil`
--- are listed commented out -- a `nil` field cannot appear in a table
--- literal, and the comment is the documentation of "unset".
---@type Ui.Tasks.Opts
M.DEFAULTS = {
  -- vault = nil,          -- vault root (the folder holding `<area>/ROADMAP/`);
  --                       -- unset: $TASKS_VAULT, then
  --                       -- $REPOS_DIR/WKDBooks/Development/wkdbook-myplugins
  -- area = nil,           -- area of the current project: a string, or
  --                       -- fun(root, cwd): string?; unset: the folder name of
  --                       -- the git root above the cwd (else of the cwd)
  areas = {}, --           -- folder name -> area alias, e.g. { nvim = "nvim-config" }
  source = "auto", --      -- "auto" | "index" | "tasks_dir" | fun(ctx, done)
  statuses = { "open", "doing", "blocked", "decision" }, -- counted; "parked" is not
  ttl_ms = 30000, --       -- how long a result is reused before it is re-read
  prefix = "T:", --        -- text in front of the number
  hide_zero = true, --     -- render nothing when the count is 0
  breakdown = false, --    -- append "P1:n" (urgent) and "B:n" (blocked) when non-zero
  urgent_prio = 1, --      -- prio <= this counts as urgent (1 = highest)
  watch_writes = true, --  -- re-read right after a vault Markdown file is saved
  max_files = 500, --      -- cap for the tasks_dir source
}

--- The statuses a task file may carry (Task-System-Konzept, section 3).
---@type table<string, true>
M.KNOWN_STATUSES = { open = true, doing = true, blocked = true, decision = true, parked = true }

---@type Ui.Tasks.Opts
local current = vim.deepcopy(M.DEFAULTS)

-- Fields already warned about, so a bad value does not repeat on every
-- `setup()` call (a host may well call it from several places).
---@type table<string, true>
local warned = {}

---@param field string
---@param msg string
local function warn_once(field, msg)
  if warned[field] then
    return
  end
  warned[field] = true
  notify.warn(("opts.%s %s -- using the default"):format(field, msg))
end

---@param v any
---@return boolean
local function is_nonneg_int(v)
  return type(v) == "number" and v >= 0 and v % 1 == 0
end

--- One validator per field: returns true when the value is acceptable.
---@type table<string, { check: fun(v: any): boolean, expect: string }>
local VALIDATORS = {
  vault = {
    check = function(v)
      return type(v) == "string" and v ~= ""
    end,
    expect = "must be a non-empty string",
  },
  area = {
    check = function(v)
      return (type(v) == "string" and v ~= "") or type(v) == "function"
    end,
    expect = "must be a non-empty string or a function",
  },
  areas = {
    check = function(v)
      if type(v) ~= "table" then
        return false
      end
      for k, val in pairs(v) do
        if type(k) ~= "string" or type(val) ~= "string" then
          return false
        end
      end
      return true
    end,
    expect = "must be a table of string -> string",
  },
  source = {
    check = function(v)
      return v == "auto" or v == "index" or v == "tasks_dir" or type(v) == "function"
    end,
    expect = 'must be "auto", "index", "tasks_dir" or a function',
  },
  statuses = {
    check = function(v)
      if type(v) ~= "table" or #v == 0 then
        return false
      end
      for _, s in ipairs(v) do
        if not M.KNOWN_STATUSES[s] then
          return false
        end
      end
      return true
    end,
    expect = "must be a non-empty list of open/doing/blocked/decision/parked",
  },
  ttl_ms = {
    check = is_nonneg_int,
    expect = "must be a non-negative integer (milliseconds)",
  },
  prefix = {
    check = function(v)
      return type(v) == "string"
    end,
    expect = "must be a string",
  },
  hide_zero = {
    check = function(v)
      return type(v) == "boolean"
    end,
    expect = "must be a boolean",
  },
  breakdown = {
    check = function(v)
      return type(v) == "boolean"
    end,
    expect = "must be a boolean",
  },
  urgent_prio = {
    check = function(v)
      return is_nonneg_int(v)
    end,
    expect = "must be a non-negative integer",
  },
  watch_writes = {
    check = function(v)
      return type(v) == "boolean"
    end,
    expect = "must be a boolean",
  },
  max_files = {
    check = function(v)
      return is_nonneg_int(v) and v > 0
    end,
    expect = "must be a positive integer",
  },
}

--- Merge `opts` over the defaults. A field of the wrong type is dropped with
--- one warning and keeps its default; an unknown key is warned about (almost
--- always a typo) and ignored. Never throws.
---@param opts Ui.Tasks.Opts|nil
---@return nil
function M.setup(opts)
  local merged = vim.deepcopy(M.DEFAULTS)
  if opts ~= nil and type(opts) ~= "table" then
    warn_once("<root>", "must be a table, got " .. type(opts))
    opts = nil
  end
  for key, value in pairs(opts or {}) do
    local validator = VALIDATORS[key]
    if not validator then
      warn_once("unknown:" .. tostring(key), "is not a known option (ignored)")
    elseif validator.check(value) then
      merged[key] = value
    else
      warn_once(key, validator.expect .. (", got %s (%s)"):format(tostring(value), type(value)))
    end
  end
  current = merged
  -- A new config can change vault/area/source: whatever was cached is stale.
  local ok, core = pcall(require, "ui.statusline.modules.tasks_counter.core")
  if ok then
    core.invalidate()
  end
end

---@return Ui.Tasks.Opts
function M.get()
  return current
end

---@param path string
---@return boolean
local function is_dir(path)
  local st = uv.fs_stat(path)
  return st ~= nil and st.type == "directory"
end

--- The vault root: `opts.vault`, `$TASKS_VAULT`, then
--- `$REPOS_DIR/WKDBooks/Development/wkdbook-myplugins` -- the same order the
--- nvim-config engine (`tasks.vault`) uses, repeated here instead of
--- required so this plugin keeps no dependency on it. `nil` when none of the
--- three names an existing directory.
---@param cfg Ui.Tasks.Opts
---@return string|nil
function M.resolve_vault(cfg)
  local repos = vim.env.REPOS_DIR
  -- Fixed slots, iterated 1..3: a table constructor with a leading nil has
  -- an ambiguous length.
  local candidates = {
    cfg.vault,
    vim.env.TASKS_VAULT,
    (repos and repos ~= "") and (repos .. "/WKDBooks/Development/wkdbook-myplugins") or nil,
  }
  for i = 1, 3 do
    local path = candidates[i]
    if type(path) == "string" and path ~= "" then
      -- normalize also expands "~" and "$VAR" in the string
      local norm = vim.fs.normalize(path)
      if is_dir(norm) then
        return norm
      end
    end
  end
  return nil
end

--- An area name becomes a path segment, so anything that could leave the
--- vault (separators, "..") is rejected outright.
---@param name any
---@return boolean
function M.valid_area(name)
  return type(name) == "string"
    and name ~= ""
    and name ~= "."
    and not name:find("[/\\]")
    and not name:find("..", 1, true)
end

--- The area of the current project: `opts.area` (string or function), else
--- the folder name of the git root above the cwd (or of the cwd itself),
--- mapped through `opts.areas`. `nil` when the result is not a usable name.
---@param cfg Ui.Tasks.Opts
---@return string|nil
function M.resolve_area(cfg)
  local cwd = uv.cwd() or ""
  local root = (vim.fs.root and vim.fs.root(cwd, ".git")) or cwd
  local name
  if type(cfg.area) == "string" then
    name = cfg.area
  elseif type(cfg.area) == "function" then
    local ok, res = pcall(cfg.area, root, cwd)
    name = ok and res or nil
  else
    name = vim.fs.basename(root)
  end
  if type(name) == "string" and cfg.areas[name] then
    name = cfg.areas[name]
  end
  if M.valid_area(name) then
    return name
  end
  return nil
end

return M
