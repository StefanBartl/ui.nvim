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

local file = require("ui.util.state_file").new({
  -- Looked up on each call: the default location is the module's to move.
  default_path = function()
    return M.default_path()
  end,
  own_keys = OWN_KEYS,
  max_bytes = MAX_BYTES,
  label = "statusline",
})

---@param path? string
---@return Ui.Statusline.Saved|nil # nil: no file, unreadable, malformed, too big, or nothing valid in it
function M.read(path)
  return sanitize(file.read(path or M.default_path()))
end

---@param order string[]
---@param path? string
---@return boolean ok, string|nil err
function M.write(order, path)
  return file.write(path or M.default_path(), { order = order })
end

---Delete the saved file. A file that is not there is not an error; one that
---is not a state file of this module is left alone.
---@param path? string
---@return boolean ok, string|nil err
function M.remove(path)
  return file.remove(path or M.default_path())
end

return M
