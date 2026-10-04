---@module 'ui.statusline.modules.tasks_counter.source'
--- Where the `tasks_counter` segment gets its numbers from: the parsers for
--- the vault's two on-disk shapes, and the async loaders that read them.
---
--- Two shapes, same answer:
---   * `<area>/ROADMAP/TASKS.md` -- the generated overview, one table row per
---     open task (`| status | prio | effort | [title](...) | summary |`).
---     One small file, so it is the default.
---   * `<area>/ROADMAP/tasks/*.md` -- one file per task, frontmatter carrying
---     `status:` and `prio:`. Authoritative, but one read per task.
--- The generated overview is absent when an area has no open task at all
--- (the engine deletes it), which is why `"auto"` falls back to the folder.
---
--- Everything here is `vim.uv` callbacks: nothing blocks the editor, and
--- nothing calls the Neovim API (a luv callback runs in a fast context) --
--- the caller hops back with `vim.schedule`.

local uv = vim.uv or vim.loop

local M = {}

--- A task as the counter needs it.
---@class Ui.Tasks.Entry
---@field status string
---@field prio integer|nil

--- Files larger than this are not read: a task or an index is a few KB, so
--- anything bigger is not what we think it is.
local MAX_BYTES = 1024 * 1024

local STATUSES = require("ui.statusline.modules.tasks_counter.config").KNOWN_STATUSES

--- Rows of the generated `TASKS.md`. The header row ("Status") and the
--- separator row never match a known status, so they drop out by themselves.
---@param text string
---@return Ui.Tasks.Entry[]
function M.parse_index(text)
  local out = {}
  for line in (text:gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
    local status, prio = line:match("^|%s*(%a+)%s*|%s*([^|]-)%s*|")
    if status and STATUSES[status] then
      out[#out + 1] = { status = status, prio = tonumber(prio) }
    end
  end
  return out
end

--- The frontmatter of one task file: `status:` and `prio:` only.
--- `nil` when the file has no frontmatter or no valid status.
---@param text string
---@return Ui.Tasks.Entry|nil
function M.parse_task(text)
  text = text:gsub("\r", "")
  if text:sub(1, 4) ~= "---\n" then
    return nil
  end
  local status, prio
  for line in text:sub(5):gmatch("(.-)\n") do
    if line == "---" then
      break
    end
    local key, value = line:match("^(%a+):%s*(.-)%s*$")
    if key == "status" then
      status = value
    elseif key == "prio" then
      prio = tonumber(value)
    end
  end
  if status and STATUSES[status] then
    return { status = status, prio = prio }
  end
  return nil
end

--- Read a whole file without blocking. `cb(nil)` for anything that goes
--- wrong (missing, unreadable, too large) -- a caller treats all of those as
--- "no data".
---@param path string
---@param cb fun(text: string|nil)
local function read_file(path, cb)
  uv.fs_open(path, "r", 438, function(err, fd)
    if err or not fd then
      return cb(nil)
    end
    uv.fs_fstat(fd, function(err2, stat)
      if err2 or not stat or stat.size > MAX_BYTES then
        return uv.fs_close(fd, function()
          cb(nil)
        end)
      end
      uv.fs_read(fd, stat.size, 0, function(err3, data)
        uv.fs_close(fd, function()
          cb((not err3 and data) or nil)
        end)
      end)
    end)
  end)
end

---@param ctx Ui.Tasks.SourceCtx
---@param done fun(tasks: Ui.Tasks.Entry[]|nil)
local function load_index(ctx, done)
  read_file(ctx.vault .. "/" .. ctx.area .. "/ROADMAP/TASKS.md", function(text)
    done(text and M.parse_index(text) or nil)
  end)
end

---@param ctx Ui.Tasks.SourceCtx
---@param done fun(tasks: Ui.Tasks.Entry[]|nil)
local function load_tasks_dir(ctx, done)
  local dir = ctx.vault .. "/" .. ctx.area .. "/ROADMAP/tasks"
  uv.fs_scandir(dir, function(err, req)
    if err or not req then
      return done(nil)
    end
    local files = {}
    while #files < ctx.max_files do
      local name, kind = uv.fs_scandir_next(req)
      if not name then
        break
      end
      if name:sub(-3) == ".md" and (kind == "file" or kind == nil) then
        files[#files + 1] = name
      end
    end
    if #files == 0 then
      return done({})
    end
    local out, pending = {}, #files
    for _, name in ipairs(files) do
      read_file(dir .. "/" .. name, function(text)
        local entry = text and M.parse_task(text)
        if entry then
          out[#out + 1] = entry
        end
        pending = pending - 1
        if pending == 0 then
          done(out)
        end
      end)
    end
  end)
end

--- Everything a source needs to know, handed to a custom source function.
---@class Ui.Tasks.SourceCtx
---@field vault string # resolved vault root, no trailing slash
---@field area string # area folder name, validated as a single path segment
---@field max_files integer

--- Run one source. `done` is called exactly once, with `nil` when the source
--- found nothing usable (no vault entry for this area, a failing custom
--- source) and with a possibly empty list otherwise.
---@param source "auto"|"index"|"tasks_dir"|fun(ctx: Ui.Tasks.SourceCtx, done: fun(tasks: Ui.Tasks.Entry[]|nil))
---@param ctx Ui.Tasks.SourceCtx
---@param done fun(tasks: Ui.Tasks.Entry[]|nil)
---@return nil
function M.load(source, ctx, done)
  local called = false
  local function once(tasks)
    if called then
      return
    end
    called = true
    done(tasks)
  end

  if type(source) == "function" then
    -- A pluggable source runs user code: a throw must end as "no data", not
    -- as an error inside a luv callback.
    local ok = pcall(source, ctx, once)
    if not ok then
      once(nil)
    end
  elseif source == "index" then
    load_index(ctx, once)
  elseif source == "tasks_dir" then
    load_tasks_dir(ctx, once)
  else
    load_index(ctx, function(tasks)
      if tasks then
        once(tasks)
      else
        load_tasks_dir(ctx, once)
      end
    end)
  end
end

--- Reduce a task list to the numbers the segment shows.
---@param tasks Ui.Tasks.Entry[]
---@param statuses string[] # which statuses count
---@param urgent_prio integer
---@return Ui.Tasks.Counts
function M.tally(tasks, statuses, urgent_prio)
  local counted = {}
  for _, s in ipairs(statuses) do
    counted[s] = true
  end
  local counts = { total = 0, urgent = 0, blocked = 0 }
  for _, t in ipairs(tasks) do
    if type(t) == "table" and counted[t.status] then
      counts.total = counts.total + 1
      if type(t.prio) == "number" and t.prio <= urgent_prio then
        counts.urgent = counts.urgent + 1
      end
      if t.status == "blocked" then
        counts.blocked = counts.blocked + 1
      end
    end
  end
  return counts
end

---@class Ui.Tasks.Counts
---@field total integer
---@field urgent integer
---@field blocked integer

return M
