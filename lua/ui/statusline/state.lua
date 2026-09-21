---@module 'ui.statusline.state'
--- The statusline `order` `ui.statusline.menu`'s "Save current layout" entry
--- last wrote, kept in a JSON file so it survives a restart. Mirrors
--- `ui.context.state` (the `:UI sticky depth`/`:UI sticky lines` persistence)
--- closely on purpose -- same shape of problem (a small, host-editable JSON
--- file that outlives the code that wrote it), same answers: a missing,
--- unreadable or malformed file reads as "nothing saved" and never raises
--- (this runs during `render.enable()`, i.e. during startup), and `write`/
--- `remove` only ever touch a path that is empty or already holds a state
--- file of this module.
---
--- Self-contained on purpose: `vim.json` and `vim.fn` only, so ui.nvim needs
--- no `lib.nvim` for it -- same reasoning `ui.context.state`'s own doc
--- comment gives.

local M = {}

---@class Ui.Statusline.Saved
---@field order string[] # a whole `order` list, "%=" entries included

--- A real file is a dozen-ish short strings -- well under a kilobyte. A
--- larger one is not ours, and is not read into memory during startup.
local MAX_BYTES = 16 * 1024

--- More `order` entries than any real statusline would ever have. A file
--- claiming more is not one this module wrote.
local MAX_ENTRIES = 128

--- The keys `write` produces. A file with any other key is somebody else's.
local OWN_KEYS = { order = true }

---Where the saved order lives unless a caller passes a different path.
---@return string
function M.default_path()
  return vim.fs.normalize(vim.fn.stdpath("state") .. "/ui.nvim/statusline_order.json")
end

---@internal
---Keep only what is valid. The file is user-editable and outlives the code
---that wrote it, so a stray value is dropped instead of being trusted.
---@param raw any
---@return Ui.Statusline.Saved|nil # nil when nothing valid is left
local function sanitize(raw)
  if type(raw) ~= "table" or type(raw.order) ~= "table" then
    return nil
  end
  local order = {}
  for _, v in ipairs(raw.order) do
    if type(v) == "string" and v ~= "" then
      order[#order + 1] = v
    end
    if #order > MAX_ENTRIES then
      return nil
    end
  end
  if #order == 0 then
    return nil
  end
  return { order = order }
end

---@alias Ui.Statusline.StateKind
---| "absent"   # no file
---| "empty"    # a file with nothing in it
---| "table"    # a file holding a JSON object or array
---| "corrupt"  # a regular file that is too big, unreadable, not JSON, or JSON but not a table
---| "notfile"  # not a regular file: a directory, say

---@internal
---What is at `path`, without ever raising.
---@param path string
---@return Ui.Statusline.StateKind kind
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
---Whether `write`/`remove` may replace what `inspect` found at `path`.
---Nothing there, or an empty file, always; a directory never. The default
---location is ours whatever it holds; a configured path only when it holds
---a JSON object with just the keys this module writes.
---@param path string
---@param kind Ui.Statusline.StateKind
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

---@param path? string
---@return Ui.Statusline.Saved|nil # nil: no file, unreadable, malformed, too big, or nothing valid in it
function M.read(path)
  path = path or M.default_path()
  local kind, decoded = inspect(path)
  if kind ~= "table" then
    return nil
  end
  return sanitize(decoded)
end

---@param order string[]
---@param path? string
---@return boolean ok, string|nil err
function M.write(order, path)
  path = path or M.default_path()
  local kind, decoded = inspect(path)
  if not may_touch(path, kind, decoded) then
    return false, path .. " is not a ui.nvim statusline state file, so it is not overwritten"
  end
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    if vim.fn.writefile({ vim.json.encode({ order = order }) }, path) ~= 0 then
      error("writefile failed for " .. path)
    end
  end)
  if not ok then
    return false, tostring(err)
  end
  return true, nil
end

---Delete the saved file. A file that is not there is not an error; one that
---is not a state file of this module is left alone.
---@param path? string
---@return boolean ok, string|nil err
function M.remove(path)
  path = path or M.default_path()
  local kind, decoded = inspect(path)
  if kind == "absent" then
    return true, nil
  end
  if not may_touch(path, kind, decoded) then
    return false, path .. " is not a ui.nvim statusline state file, so it is not deleted"
  end
  if vim.fn.delete(path) ~= 0 then
    return false, "could not delete " .. path
  end
  return true, nil
end

return M
