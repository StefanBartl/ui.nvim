---@module 'ui.context.state'
--- The values `:UI sticky depth` / `:UI sticky lines` were last set to, kept in
--- a JSON file so they survive a restart (`persist = true` in `ui.context`'s
--- options). Only what a command changed is stored -- the host's own
--- configuration stays in its config -- and `:UI sticky reset` deletes the file.
---
--- Self-contained on purpose: `vim.json` and `vim.fn` only, so ui.nvim needs no
--- lib.nvim for it. A missing, unreadable or malformed file reads as "nothing
--- saved" and never raises: this runs during startup.

local M = {}

---@class Ui.Context.Saved
---@field max_level? integer               # deepest Markdown heading level pinned, 1..6
---@field lines? table<string, integer>    # filetype -> row cap; `default` is the fallback entry

local MAX_HEADING_LEVEL = 6

---Where the values live unless `state_file` says otherwise.
---@return string
function M.default_path()
  return vim.fs.normalize(vim.fn.stdpath("state") .. "/ui.nvim/sticky.json")
end

---@internal
---A whole number, or nil.
---@param v any
---@return integer|nil
local function whole(v)
  if type(v) == "number" and v == math.floor(v) then
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
    local lines = {}
    for ft, n in pairs(raw.lines) do
      local count = whole(n)
      if type(ft) == "string" and count and count >= 0 then
        lines[ft] = count
      end
    end
    if next(lines) ~= nil then
      out.lines = lines
    end
  end
  if out.max_level == nil and out.lines == nil then
    return nil
  end
  return out
end

---@param path string
---@return Ui.Context.Saved|nil # nil: no file, unreadable, malformed, or nothing valid in it
function M.read(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  local decoded_ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded_ok then
    return nil
  end
  return sanitize(decoded)
end

---@param path string
---@param saved Ui.Context.Saved
---@return boolean ok, string|nil err
function M.write(path, saved)
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

---Delete the file. A file that is not there is not an error.
---@param path string
---@return boolean ok, string|nil err
function M.remove(path)
  if vim.fn.filereadable(path) ~= 1 then
    return true, nil
  end
  if vim.fn.delete(path) ~= 0 then
    return false, "could not delete " .. path
  end
  return true, nil
end

return M
