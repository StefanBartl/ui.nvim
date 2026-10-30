---@module 'ui.statusline.modules.idle_git_log'
--- The last one to three commits of the repo the statusline's buffer lives
--- in (`a1b2c3d Fix the parser · 9f8e7d6 Add tests`), shown only once the
--- editor has been idle (`CursorHold`/`CursorHoldI`) and hidden again on the
--- next keystroke -- the second payload of IDEEN-statusline.md's
--- "Idle-Erweiterung nach N Sekunden Inaktivität", on the same
--- `ui.statusline.utils.idle` primitive as `idle_clock`.
---
--- No steady load: `git log` runs at most once per repo per idle phase
--- (`idle.phase()`), asynchronously through `lib.nvim.git.log_async` (an argv
--- list, never a shell string), and the result is cached for the rest of
--- that phase. Every redraw while active is `idle.wrap`'s cheap early
--- return; the first idle redraw starts the read and renders "" until it
--- answers, then the finished read repaints the statusline once. A buffer
--- outside any repo renders "" without spawning git at all.

local git = require("lib.nvim.git")
local idle = require("ui.statusline.utils.idle")
local primitives = require("ui.statusline.utils.primitives")
local safe = require("lib.lua.strings.safe")

-- The upper bound the idea names ("letzte ein bis drei Commits"): more would
-- crowd every other segment out of a statusline.
local MAX_COMMITS = 3
local DEFAULT_SUBJECT_WIDTH = 32
-- A read that has not answered by then is not worth waiting for: the idle
-- phase it was for is most likely over already.
local TIMEOUT_MS = 2000
-- Three subjects of a sane repo are well below this; one commit with a
-- multi-megabyte message must not be held in memory just to show 32 columns.
local MAX_OUTPUT_BYTES = 64 * 1024
local SEPARATOR = " · "

---@class Ui.Statusline.IdleGitLog.Opts
---@field max_count? integer # commits shown, clamped to 1..3. Default 3.
---@field subject_width? integer # display columns per subject before it is cut with "…". Default 32.

---@class Ui.Statusline.IdleGitLog.Entry
---@field done boolean # false while the read is still running
---@field lines { sha: string, subject: string }[]
---@field handle? { stop: fun() }

-- Reads of the current idle phase, keyed by repo root. Replaced wholesale
-- when a new phase starts, so a commit made while active shows up on the
-- next idle phase and nothing older is ever kept.
---@type table<string, Ui.Statusline.IdleGitLog.Entry>
local cache = {}
---@type integer|nil
local cache_phase = nil

---@param value any
---@param default integer
---@param lo integer
---@param hi integer
---@return integer
local function clamp_int(value, default, lo, hi)
  if type(value) ~= "number" or value ~= value then
    return default
  end
  return math.max(lo, math.min(hi, math.floor(value)))
end

--- The directory the statusline's buffer belongs to: its file's directory
--- for a file buffer, the statusline window's cwd otherwise (a terminal, a
--- scratch buffer, a file tree).
---@return string
local function buffer_dir()
  local buf = primitives.stbufnr()
  if vim.bo[buf].buftype == "" then
    local name = vim.api.nvim_buf_get_name(buf)
    if name ~= "" then
      local dir = vim.fs.dirname(name)
      if dir and vim.fn.isdirectory(dir) == 1 then
        return dir
      end
    end
  end
  local winid = vim.g.statusline_winid
  if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) then
    return vim.fn.getcwd(winid)
  end
  return vim.fn.getcwd()
end

--- The work tree root `dir` belongs to, or nil outside any repo. A plain
--- upward filesystem lookup for `.git` (a directory, or the file a worktree
--- or submodule has) -- no process, so a non-repo buffer costs nothing.
---@param dir string
---@return string|nil
local function repo_root(dir)
  local found = vim.fs.find(".git", { path = dir, upward = true, limit = 1 })[1]
  return found and vim.fs.dirname(found) or nil
end

--- Start a new idle phase's cache once `idle.phase()` moved on, stopping any
--- read the previous phase left running.
---@param phase integer
local function roll_phase(phase)
  if cache_phase == phase then
    return
  end
  for _, entry in pairs(cache) do
    if entry.handle then
      pcall(entry.handle.stop)
    end
  end
  cache = {}
  cache_phase = phase
end

---@param root string
---@param phase integer
---@param max_count integer
---@return Ui.Statusline.IdleGitLog.Entry
local function start_read(root, phase, max_count)
  ---@type Ui.Statusline.IdleGitLog.Entry
  local entry = { done = false, lines = {} }
  cache[root] = entry
  entry.handle = git.log_async(nil, {
    dir = root,
    max_count = max_count,
    timeout_ms = TIMEOUT_MS,
    max_output_bytes = MAX_OUTPUT_BYTES,
    no_lazy_fetch = true,
  }, function(commits)
    entry.done = true
    entry.handle = nil
    -- A read of an earlier phase answering late is dropped: its phase's
    -- cache is gone, and the new phase reads for itself.
    if cache_phase ~= phase or cache[root] ~= entry then
      return
    end
    for _, c in ipairs(commits or {}) do
      if type(c.sha) == "string" and type(c.subject) == "string" then
        entry.lines[#entry.lines + 1] = { sha = c.sha:sub(1, 7), subject = c.subject }
      end
    end
    if #entry.lines > 0 and idle.is_idle() and idle.phase() == phase then
      -- `!`: the repo may belong to another window's statusline.
      vim.cmd("redrawstatus!")
    end
  end)
  return entry
end

---@param entry Ui.Statusline.IdleGitLog.Entry
---@param max_count integer
---@param subject_width integer
---@return string
local function format(entry, max_count, subject_width)
  local parts = {}
  for i = 1, math.min(max_count, #entry.lines) do
    local line = entry.lines[i]
    -- Commit text is foreign: `safe.clean` strips escape sequences and
    -- invisible characters and cuts to `subject_width`; `%` would otherwise
    -- be read as a statusline item.
    -- A cut right after a word would leave "First …"; keep the ellipsis on
    -- the word.
    local subject =
      safe.clean(line.subject, subject_width):gsub("%s+…$", "…"):gsub("%%", "%%%%")
    parts[#parts + 1] = line.sha .. " " .. subject
  end
  if #parts == 0 then
    return ""
  end
  return " " .. table.concat(parts, SEPARATOR) .. " "
end

---@param opts Ui.Statusline.IdleGitLog.Opts|nil
---@return string
return idle.wrap(function(opts)
  opts = type(opts) == "table" and opts or {}
  local max_count = clamp_int(opts.max_count, MAX_COMMITS, 1, MAX_COMMITS)
  local subject_width = clamp_int(opts.subject_width, DEFAULT_SUBJECT_WIDTH, 1, 200)

  local phase = idle.phase()
  roll_phase(phase)

  local root = repo_root(buffer_dir())
  if not root then
    return ""
  end

  -- Always read the maximum: a host showing one commit in one window and
  -- three in another still costs one process per repo and phase.
  local entry = cache[root] or start_read(root, phase, MAX_COMMITS)
  if not entry.done then
    return ""
  end
  return format(entry, max_count, subject_width)
end)
