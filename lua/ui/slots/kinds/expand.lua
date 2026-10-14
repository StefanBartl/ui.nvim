---@module 'ui.slots.kinds.expand'
--- Kind `expand`: a slot that folds a float of look-up text out and in.
--- `{ kind = "expand", path = "{root}/docs/ACRONYMS.md" }` or
--- `{ kind = "expand", fn = function(ctx) return { "API  application ..." } end }`.
---
--- Applying the slot opens a read-only float with the text; applying it again
--- (or `q`/`<Esc>`, or moving to another window) closes it. The float scrolls
--- as any window does, and `/`, `n`, `N` search in it. The text comes from a
--- file (`path`, placeholders put in, read like the preview reads: capped by
--- `preview.max_kb` and `preview.max_lines`) or from `fn`, which gets the same
--- context as a `lua` slot and returns a string or a list of lines. `title`
--- and `ft` (a filetype for highlighting) are optional.
---
--- A `fn` is code, so it comes from `setup()` or Lua and never from a data
--- file; a slot with a `path` is kept out of the data file as well (the kind
--- does not set `persist`).

local config = require("ui.slots.config")
local resolve = require("ui.slots.resolve")
local util = require("ui.slots.util")

local uv = vim.uv or vim.loop

local M = {}

--- Open floats by slot number.
---@type table<integer, Ui.Kit.Surface>
local open = {}

---@param slot table
---@return string|nil
function M.validate(slot)
  local has_path = slot.path ~= nil
  local has_fn = slot.fn ~= nil
  if has_path == has_fn then
    return "an expand slot needs either a path or a fn (not both)"
  end
  if has_path and (type(slot.path) ~= "string" or slot.path == "") then
    return "path must be a non-empty string"
  end
  if has_fn and type(slot.fn) ~= "function" then
    return "fn must be a function (a string is not run)"
  end
  for _, field in ipairs({ "title", "ft" }) do
    if slot[field] ~= nil and type(slot[field]) ~= "string" then
      return field .. " must be a string"
    end
  end
  return nil
end

--- A path on another machine only comes from `setup()` (see the file kind).
---@param slot table
---@return string|nil
function M.trusted_only(slot)
  if type(slot.path) == "string" and slot.path:match("^[\\/][\\/]") then
    return "a network path (\\\\host\\share) can only be set in setup()"
  end
  return nil
end

--- Lines the buffer accepts: no newline or CR inside, NUL shown as `^@`, and no
--- more than `preview.max_lines` of them.
---@param text any  # string or list
---@return string[]
local function to_lines(text)
  local raw = {}
  if type(text) == "string" then
    raw = vim.split(text, "\n", { plain = true })
  elseif type(text) == "table" then
    for _, l in ipairs(text) do
      vim.list_extend(raw, vim.split(tostring(l), "\n", { plain = true }))
    end
  end
  local max = config.get().preview.max_lines
  local out = {}
  for i = 1, math.min(#raw, max) do
    out[i] = (raw[i]:gsub("\r$", ""):gsub("%z", "^@"))
  end
  if #raw > max then
    out[#out + 1] = ("… cut here (limit %d lines)"):format(max)
  end
  return out
end

--- The text of the slot.
---@param slot table
---@param rctx Ui.Slots.Ctx
---@return string[]|nil lines
---@return string|nil err
---@return string title
local function content(slot, rctx)
  if slot.fn then
    local ctx = setmetatable({ slot = slot, n = slot.n }, {
      __index = function(_, key)
        local v = rctx[key]
        if type(v) == "function" then
          local ok, res = pcall(v)
          return ok and res or nil
        end
        return v
      end,
    })
    local ok, res = pcall(slot.fn, ctx)
    if not ok then
      return nil, tostring(res), "expand"
    end
    if type(res) ~= "string" and type(res) ~= "table" then
      return nil, "the function returned no text (a string or a list of lines)", "expand"
    end
    return to_lines(res), nil, "expand"
  end
  local file = require("ui.slots.kinds.file")
  local path, unknown, refused = file.resolve_path(slot, rctx)
  util.warn_unknown(unknown, "expand slot")
  if path == "" then
    return nil, refused or "the path is empty", "expand"
  end
  local title = vim.fs.basename(path)
  local st = uv.fs_stat(path)
  if not st then
    return nil, "file does not exist: " .. path, title
  end
  if st.type ~= "file" then
    return nil, "not a regular file: " .. path, title
  end
  return (file._read(path, st)), nil, title
end

--- Close the float of slot `n` if it is open.
---@param n integer|nil
---@return boolean closed
function M.close(n)
  local surf = n and open[n]
  if n then
    open[n] = nil
  end
  if surf and surf:is_valid() then
    surf:close()
    return true
  end
  return false
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  if M.close(slot.n) then
    return true
  end
  local lines, err, title = content(slot, ctx.resolve or resolve.context())
  if not lines then
    return false, err
  end
  if #lines == 0 then
    return false, "there is nothing to show"
  end
  local width = 20
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  local surf = require("ui.kit.viewer").open({
    title = slot.title or slot.label or title,
    lines = lines,
    width = math.min(width + 2, math.floor(vim.o.columns * 0.8)),
    height = math.min(#lines, math.max(3, math.floor(vim.o.lines * 0.7))),
    filetype = slot.ft,
  })
  if not surf then
    return false, "the float could not be opened"
  end
  if slot.n then
    open[slot.n] = surf
    surf:on_close(function()
      if open[slot.n] == surf then
        open[slot.n] = nil
      end
    end)
  end
  return true
end

---@param slot table
---@param opts { cheap?: boolean, resolve?: Ui.Slots.Ctx }|nil
---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(slot, opts)
  local label = slot.title
  local missing = false
  if type(slot.path) == "string" then
    label = label or vim.fs.basename(slot.path)
    if not (opts and opts.cheap) then
      local path = require("ui.slots.kinds.file").resolve_path(slot, opts and opts.resolve)
      missing = path == "" or not uv.fs_stat(path)
    end
  end
  return {
    label = label or "expand",
    icon = "󰘖",
    hl = missing and "KitMuted" or "KitAccent",
    missing = missing,
  }
end

return M
