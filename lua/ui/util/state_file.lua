---@module 'ui.util.state_file'
--- The persistence both small state files share (`ui.context.state`,
--- `ui.statusline.state`): a host-editable JSON object that outlives the code
--- that wrote it. What differs per file -- the keys it owns, its size cap, its
--- default location, how it validates a decoded table -- is a parameter of
--- `new`; the rest is written once here.
---
--- Self-contained on purpose: `vim.json` and `vim.fn` only, so ui.nvim needs no
--- `lib.nvim` for it.
---
--- A missing, unreadable or malformed file reads as "nothing saved" and never
--- raises (this runs during startup). `write`/`remove` only touch a path that is
--- empty or already holds a state file of this module: the default location is
--- ours whatever it holds, a configured path only when it holds a JSON object
--- with just the keys the file owns.

local M = {}

---@alias Ui.StateFile.Kind
---| "absent"   # no file
---| "empty"    # a file with nothing in it
---| "table"    # a file holding a JSON object or array
---| "corrupt"  # a regular file that is too big, unreadable, not JSON, or JSON but not a table
---| "notfile"  # not a regular file: a directory, say

---@class Ui.StateFile.Spec
---@field default_path fun(): string   # the location that is ours whatever it holds
---@field own_keys table<string, true> # the keys `write` produces; any other key is somebody else's
---@field max_bytes integer            # a larger file is not ours and is not read into memory
---@field label string                 # names the file in messages: "ui.nvim <label> state file"
---@field hint? string                 # appended to the refusal messages

---@class Ui.StateFile
---@field read fun(path: string): table|nil
---@field write fun(path: string, value: table): boolean, string|nil
---@field remove fun(path: string): boolean, string|nil

---@param spec Ui.StateFile.Spec
---@return Ui.StateFile
function M.new(spec)
  local hint = spec.hint or ""

  ---@param path string
  ---@return Ui.StateFile.Kind kind
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
    if stat.size > spec.max_bytes then
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

  ---Whether `write` / `remove` may replace what `inspect` found at `path`.
  ---@param path string
  ---@param kind Ui.StateFile.Kind
  ---@param decoded table|nil
  ---@return boolean
  local function may_touch(path, kind, decoded)
    if kind == "absent" or kind == "empty" then
      return true
    end
    if kind == "notfile" then
      return false
    end
    if path == spec.default_path() then
      return true
    end
    if kind ~= "table" or decoded == nil then
      return false
    end
    for key in pairs(decoded) do
      if not spec.own_keys[key] then
        return false
      end
    end
    return true
  end

  ---@type Ui.StateFile
  local file = {}

  ---@param path string
  ---@return table|nil # the decoded JSON object; nil: no file, unreadable, malformed or too big
  function file.read(path)
    local kind, decoded = inspect(path)
    if kind ~= "table" then
      return nil
    end
    return decoded
  end

  ---@param path string
  ---@param value table
  ---@return boolean ok, string|nil err
  function file.write(path, value)
    local kind, decoded = inspect(path)
    if not may_touch(path, kind, decoded) then
      return false,
        ("%s is not a ui.nvim %s state file, so it is not overwritten%s"):format(
          path,
          spec.label,
          hint
        )
    end
    local ok, err = pcall(function()
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      if vim.fn.writefile({ vim.json.encode(value) }, path) ~= 0 then
        error("writefile failed for " .. path)
      end
    end)
    if not ok then
      return false, tostring(err)
    end
    return true, nil
  end

  ---Delete the file. A file that is not there is not an error; one that is not
  ---a state file of this module is left alone.
  ---@param path string
  ---@return boolean ok, string|nil err
  function file.remove(path)
    local kind, decoded = inspect(path)
    if kind == "absent" then
      return true, nil
    end
    if not may_touch(path, kind, decoded) then
      return false,
        ("%s is not a ui.nvim %s state file, so it is not deleted%s"):format(path, spec.label, hint)
    end
    if vim.fn.delete(path) ~= 0 then
      return false, "could not delete " .. path
    end
    return true, nil
  end

  return file
end

return M
