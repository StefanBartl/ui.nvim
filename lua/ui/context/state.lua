---@module 'ui.context.state'
--- The values `:UI sticky depth` / `:UI sticky lines` were last set to, kept in
--- a JSON file so they survive a restart (`persist = true` in `ui.context`'s
--- options). Only what a command changed is stored -- the host's own
--- configuration stays in its config -- and `:UI sticky reset` deletes the file.
---
--- Self-contained on purpose: `vim.json` and `vim.fn` only, so ui.nvim needs no
--- lib.nvim for it. A missing, unreadable or malformed file reads as "nothing
--- saved" and never raises: this runs during startup.
---
--- The path is the host's to choose (`state_file`), so it can point at any file.
--- `write` and `remove` therefore only touch a configured path that is empty or
--- already holds a state file of this module; anything else is left alone and
--- reported. The default location is this plugin's own directory, so a file there
--- is ours whatever it holds (a corrupt one is replaced, not stuck for good).

local M = {}

---@class Ui.Context.Saved
---@field max_level? integer               # deepest Markdown heading level pinned, 1..6
---@field lines? table<string, integer>    # filetype -> row cap; `default` is the fallback entry

local MAX_HEADING_LEVEL = 6

--- A real file is a level and a few filetypes -- well under a kilobyte. A larger
--- one is not ours, and is not read into memory during startup.
local MAX_BYTES = 16 * 1024

--- Most filetype entries a file may carry. More than that is not a file this
--- module wrote, and `lines` is ignored as a whole rather than truncated at an
--- arbitrary entry.
local MAX_FILETYPES = 64

--- The keys `write` produces. A file with any other key is somebody else's.
local OWN_KEYS = { max_level = true, lines = true }

---Where the values live unless `state_file` says otherwise.
---@return string
function M.default_path()
  return vim.fs.normalize(vim.fn.stdpath("state") .. "/ui.nvim/sticky.json")
end

---A configured path as an absolute one: `~` and `$VAR` are expanded, and a
---relative path is anchored at the current directory, so a later `:cd` does not
---move the file (nor does a `~` end up as a directory of that name).
---@param path string
---@return string
function M.resolve(path)
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(path), ":p"))
end

---@internal
---A finite whole number, or nil. `inf` and `nan` are numbers too, but neither can
---be written back as JSON.
---@param v any
---@return integer|nil
local function whole(v)
  if type(v) == "number" and v == math.floor(v) and math.abs(v) ~= math.huge then
    return v
  end
  return nil
end

---@internal
---Keep only what is valid. The file is user-editable and outlives the code that
---wrote it, so a stray value is dropped instead of being trusted.
---@param raw any
---@return Ui.Context.Saved|nil # nil when nothing valid is left
local function sanitize(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local out = {} ---@type Ui.Context.Saved
  local level = whole(raw.max_level)
  if level and level >= 1 and level <= MAX_HEADING_LEVEL then
    out.max_level = level
  end
  if type(raw.lines) == "table" then
    local lines, count = {}, 0
    for ft, n in pairs(raw.lines) do
      local rows = whole(n)
      if type(ft) == "string" and rows and rows >= 0 then
        lines[ft] = rows
        count = count + 1
      end
    end
    if count > 0 and count <= MAX_FILETYPES then
      out.lines = lines
    end
  end
  if out.max_level == nil and out.lines == nil then
    return nil
  end
  return out
end

---@alias Ui.Context.StateKind
---| "absent"   # no file
---| "empty"    # a file with nothing in it
---| "table"    # a file holding a JSON object or array
---| "corrupt"  # a regular file that is too big, unreadable, not JSON, or JSON but not a table
---| "notfile"  # not a regular file: a directory, say

---@internal
---What is at `path`, without ever raising.
---@param path string
---@return Ui.Context.StateKind kind
---@return table|nil decoded # the JSON content when `kind` is "table"
local function inspect(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return "absent"
  end
  if stat.type ~= "file" then
    return "notfile"
  end
  if stat.size == 0 then
    return "empty"
  end
  if stat.size > MAX_BYTES then
    return "corrupt"
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return "corrupt"
  end
  local text = table.concat(lines, "\n")
  if text:match("^%s*$") then
    return "empty"
  end
  local decoded_ok, decoded = pcall(vim.json.decode, text)
  if not decoded_ok or type(decoded) ~= "table" then
    return "corrupt"
  end
  return "table", decoded
end

---@internal
---Whether `write` / `remove` may replace what `inspect` found at `path`. Nothing
---there, or an empty file, always; a directory never. Beyond that the default
---location is ours whatever it holds, and a configured path only when it holds
---a JSON object with just the keys this module writes.
---@param path string
---@param kind Ui.Context.StateKind
---@param decoded table|nil
---@return boolean
local function may_touch(path, kind, decoded)
  if kind == "absent" or kind == "empty" then
    return true
  end
  if kind == "notfile" then
    return false
  end
  if path == M.default_path() then
    return true
  end
  if kind ~= "table" or decoded == nil then
    return false
  end
  for key in pairs(decoded) do
    if not OWN_KEYS[key] then
      return false
    end
  end
  return true
end

---@param path string
---@return Ui.Context.Saved|nil # nil: no file, unreadable, malformed, too big, or nothing valid in it
function M.read(path)
  local kind, decoded = inspect(path)
  if kind ~= "table" then
    return nil
  end
  return sanitize(decoded)
end

---@param path string
---@param saved Ui.Context.Saved
---@return boolean ok, string|nil err
function M.write(path, saved)
  if not may_touch(path, inspect(path)) then
    return false,
      path
        .. " is not a ui.nvim sticky state file, so it is not overwritten (point `state_file` elsewhere)"
  end
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    if vim.fn.writefile({ vim.json.encode(saved) }, path) ~= 0 then
      error("writefile failed for " .. path)
    end
  end)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

---Delete the file. A file that is not there is not an error; one that is not a
---state file of this module is left alone.
---@param path string
---@return boolean ok, string|nil err
function M.remove(path)
  local kind, decoded = inspect(path)
  if kind == "absent" then
    return true, nil
  end
  if not may_touch(path, kind, decoded) then
    return false,
      path
        .. " is not a ui.nvim sticky state file, so it is not deleted (point `state_file` elsewhere)"
  end
  if vim.fn.delete(path) ~= 0 then
    return false, "could not delete " .. path
  end
  return true, nil
end

return M
