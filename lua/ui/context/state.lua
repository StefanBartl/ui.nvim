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

local file = require("ui.util.state_file").new({
  -- Looked up on each call: the default location is the module's to move.
  default_path = function()
    return M.default_path()
  end,
  own_keys = OWN_KEYS,
  max_bytes = MAX_BYTES,
  label = "sticky",
  hint = " (point `state_file` elsewhere)",
})

---@param path string
---@return Ui.Context.Saved|nil # nil: no file, unreadable, malformed, too big, or nothing valid in it
function M.read(path)
  return sanitize(file.read(path))
end

---@param path string
---@param saved Ui.Context.Saved
---@return boolean ok, string|nil err
function M.write(path, saved)
  return file.write(path, saved)
end

---Delete the file. A file that is not there is not an error; one that is not a
---state file of this module is left alone.
---@param path string
---@return boolean ok, string|nil err
function M.remove(path)
  return file.remove(path)
end

return M
