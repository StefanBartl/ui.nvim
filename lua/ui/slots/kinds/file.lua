---@module 'ui.slots.kinds.file'
--- Kind `file`: open a file. `{ kind = "file", path = "~/notes.md" }`.
---
--- `path` may hold placeholders (`{root}/TODO.md`) and `~`/environment
--- variables. The file is opened in the window the config's `target` names
--- (`current`, `split`, `vsplit`, `tab`; a slot's own `target` wins). A file
--- that does not exist is reported, never created.
---
--- The cursor goes back to where it was last time: the slot's own `line`/`col`
--- (1-based, written by `remember_current()` for slots in the data file), else
--- the position remembered for this session, else the buffer's `"` mark.

local config = require("ui.slots.config")
local resolve = require("ui.slots.resolve")
local util = require("ui.slots.util")

local uv = vim.uv or vim.loop

local M = {}

local TARGETS = { current = "edit", split = "split", vsplit = "vsplit", tab = "tabedit" }

--- Where the cursor was when each file was last left this session.
---@type table<string, { line: integer, col: integer }>
local positions = {}

---@param path string
---@return string
local function key(path)
  return require("lib.nvim.fs.normkey")(path)
end

--- `key()` asks the file system (a real path), and the views ask for the key of
--- every slot on a redraw: remembered for a moment, and bounded.
local KEY_TTL_MS = 2000
local KEY_MAX = 2048
local key_cache, key_count = {}, 0

---@param path string
---@return string
local function cached_key(path)
  local now = uv.now()
  local hit = key_cache[path]
  if hit and now - hit.at < KEY_TTL_MS then
    return hit.k
  end
  if key_count >= KEY_MAX then
    key_cache, key_count = {}, 0
  end
  local k = key(path)
  if not key_cache[path] then
    key_count = key_count + 1
  end
  key_cache[path] = { k = k, at = now }
  return k
end

--- The last component of a path as written, found from the end (a pattern for it
--- backtracks quadratically on a long first segment, and a data file may hold
--- one).
---@param p string
---@return string
local function basename(p)
  local e = #p
  while e > 0 do
    local c = p:byte(e)
    if c == 47 or c == 92 then
      e = e - 1
    else
      break
    end
  end
  local b = e
  while b > 0 do
    local c = p:byte(b)
    if c == 47 or c == 92 then
      break
    end
    b = b - 1
  end
  local name = p:sub(b + 1, e)
  return name ~= "" and name or p
end

--- A network (UNC) path: `\\host\share` or `//host/share`. Touching one is a
--- synchronous connection to that host -- twenty seconds when it is gone, and
--- on Windows a place the account's credentials are offered -- so only a slot
--- from `setup()` may name one.
---@param path any
---@return boolean
local function is_network(path)
  return type(path) == "string" and path:match("^[\\/][\\/]") ~= nil
end

--- Placeholders whose value is text the user (or a page) put somewhere, not a
--- place the user is in: a path made of them may name any host.
---@param path string
---@return boolean
local function has_content_placeholder(path)
  return path:find("{clip}", 1, true) ~= nil
    or path:find("{sel}", 1, true) ~= nil
    or path:find("{word}", 1, true) ~= nil
end

---@param slot table
---@param ctx Ui.Slots.Ctx|nil
---@return string path
---@return string[] unknown
---@return string|nil refused  # why the path is empty although the slot names one
local function target_path(slot, ctx)
  local resolved, unknown = resolve.resolve(slot.path, ctx)
  -- Absolute: a relative name that starts with "+" would be read by :edit as
  -- a +cmd argument, and the position memory needs one spelling per file.
  if resolved == "" then
    -- Nothing to open (every placeholder was empty): not the current directory.
    return "", unknown
  end
  -- A network path is not followed for a slot that does not come from setup()
  -- -- unless it is where the user's own tree is: `{root}/TODO.md` in a project
  -- on `\\wsl$\...` names no other host than the one the user is working on. What
  -- is written out as a network path, or comes from `{clip}`, `{sel}` or
  -- `{word}`, may name any host.
  if
    slot.fixed ~= true
    and is_network(resolved)
    and (is_network(slot.path) or has_content_placeholder(slot.path))
  then
    return "", unknown, "a network path can only be set in setup()"
  end
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fs.normalize(resolved), ":p")), unknown
end

--- A path on another machine only comes from `setup()` (see `is_network`).
---@param slot table
---@return string|nil
function M.trusted_only(slot)
  if is_network(slot.path) then
    return "a network path (\\\\host\\share) can only be set in setup()"
  end
  return nil
end

---@param slot table
---@return string|nil
function M.validate(slot)
  if type(slot.path) ~= "string" or slot.path == "" then
    return "a file slot needs a path"
  end
  if slot.target ~= nil and TARGETS[slot.target] == nil then
    return ("target '%s' is not one of current, split, vsplit, tab"):format(tostring(slot.target))
  end
  for _, field in ipairs({ "line", "col" }) do
    local v = slot[field]
    if v ~= nil and (type(v) ~= "number" or v < 1 or v ~= math.floor(v)) then
      return ("%s must be a positive whole number"):format(field)
    end
  end
  return nil
end

--- Put the cursor of the current window where it was, clamped to the buffer.
---@param slot table
---@param path string
local function jump(slot, path)
  local buf = vim.api.nvim_get_current_buf()
  local line, col = slot.line, slot.col
  if not line then
    local seen = positions[key(path)]
    if seen then
      line, col = seen.line, seen.col
    else
      local mark = vim.api.nvim_buf_get_mark(buf, '"')
      if mark[1] > 0 then
        line, col = mark[1], mark[2] + 1
      end
    end
  end
  if not line then
    return
  end
  line = math.min(line, vim.api.nvim_buf_line_count(buf))
  local text = vim.api.nvim_buf_get_lines(buf, line - 1, line, false)[1] or ""
  local zero_col = math.max(0, math.min((col or 1) - 1, math.max(#text - 1, 0)))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, zero_col })
end

--- The path this slot opens, placeholders put in.
---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return string
function M.text(slot, ctx)
  local path, unknown = target_path(slot, ctx.resolve)
  util.warn_unknown(unknown, "file slot")
  return path
end

---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return boolean ok
---@return string|nil err
function M.apply(slot, ctx)
  local path, unknown, refused = target_path(slot, ctx.resolve)
  util.warn_unknown(unknown, "file slot")
  if refused then
    return false, refused
  end
  local st = uv.fs_stat(path)
  if not st then
    return false, "file does not exist: " .. path
  end

  local cmd = TARGETS[slot.target or config.get().target] or "edit"
  local ok, err = pcall(vim.cmd, { cmd = cmd, args = { path }, magic = { file = false } })
  if not ok then
    return false, tostring(err)
  end
  jump(slot, path)
  return true
end

---@param slot table
---@return { label: string, icon: string, hl: string, missing: boolean }
function M.render(slot, opts)
  if opts and opts.cheap and type(slot.path) == "string" then
    -- The name as written (a placeholder stays as it is): nothing put in, no
    -- absolute path made, no stat -- the row is corrected when it comes into view.
    return { label = basename(slot.path), icon = "󰈔", hl = "KitAccent", missing = false }
  end
  local path = target_path(slot)
  local missing = not uv.fs_stat(path)
  return {
    label = vim.fs.basename(path) ~= "" and vim.fs.basename(path) or path,
    icon = "󰈔",
    hl = missing and "KitMuted" or "KitAccent",
    missing = missing,
  }
end

--- A file read for the preview: at most `preview.max_kb` bytes and `max_lines`
--- lines, every line one the buffer accepts (a NUL byte shows as `^@`, a `\r` is
--- dropped, a very long line is cut), and a last line that says where it was cut.
---@param path string
---@param st table  # fs_stat of `path`
---@return string[] lines
---@return boolean cut
function M._read(path, st)
  local pv = config.get().preview
  local limit = pv.max_kb * 1024
  local fd = io.open(path, "rb")
  if not fd then
    return { "cannot read: " .. path }, false
  end
  local data = fd:read(limit) or ""
  fd:close()
  local cut_bytes = st.size > limit
  local lines = vim.split(data, "\n", { plain = true })
  if cut_bytes then
    -- The last line stops mid-way -- unless it is the only one (a minified file
    -- on one line): then a piece of it is all there is to show.
    if #lines > 1 then
      table.remove(lines)
    end
  elseif lines[#lines] == "" then
    table.remove(lines) -- the newline that ends the file
  end
  local cut_lines = #lines > pv.max_lines
  if cut_lines then
    lines = vim.list_slice(lines, 1, pv.max_lines)
  end
  for i, line in ipairs(lines) do
    line = line:gsub("\r$", ""):gsub("%z", "^@")
    if #line > 2000 then
      line = line:sub(1, 2000) .. "…"
    end
    lines[i] = line
  end
  local cut = cut_bytes or cut_lines
  if cut then
    lines[#lines + 1] = ("… cut here (limit %d KB, %d lines)"):format(pv.max_kb, pv.max_lines)
  end
  return lines, cut
end

--- What the preview pane shows for this slot: the file, at the position it was
--- last left at.
---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }
---@return Ui.Slots.Preview
function M.preview(slot, ctx)
  local path, _, refused = target_path(slot, ctx.resolve)
  if path == "" then
    return { lines = { refused and ("(" .. refused .. ")") or "(the path is empty)" } }
  end
  local st = uv.fs_stat(path)
  if not st then
    return { lines = { "file does not exist: " .. path } }
  end
  if st.type == "directory" then
    -- Only as many entries as will be shown are read: a directory with a hundred
    -- thousand files must not stall the editor on a cursor move.
    local max = config.get().preview.max_lines
    local entries, cut = {}, false
    local handle = uv.fs_scandir(path)
    while handle do
      local name = uv.fs_scandir_next(handle)
      if not name then
        break
      end
      if #entries >= max then
        cut = true
        break
      end
      entries[#entries + 1] = name
    end
    table.sort(entries)
    if cut then
      entries[#entries + 1] = "… cut here"
    end
    return { lines = entries }
  end
  if st.type ~= "file" then
    return { lines = { "not a regular file: " .. path } }
  end
  local lines = M._read(path, st)
  local line = type(slot.line) == "number" and slot.line or nil
  local at = line and { line, type(slot.col) == "number" and slot.col or 1 } or nil
  if not at then
    local seen = positions[key(path)]
    at = seen and { seen.line, seen.col } or nil
  end
  local ft = vim.filetype.match({ filename = path })
  return { lines = lines, ft = ft, pos = at }
end

--- A spelling of a slot's path that compares without asking the file system
--- anything, or nil when only the file system can say (a placeholder in it).
local win_or_mac = vim.fn.has("win32") == 1 or vim.fn.has("mac") == 1
local CHEAP_MAX = 20000
local cheap_memo, cheap_count = {}, 0

---@param path string
---@return string
local function fold(path)
  path = vim.fs.normalize(path)
  return win_or_mac and path:lower() or path
end

---@param slot table
---@return string|nil
local function cheap_slot_key(slot)
  local p = slot.path
  if type(p) ~= "string" or p:find("{", 1, true) then
    return nil
  end
  if p:match("^[/\\~]") or p:match("^%a:[/\\]") then
    local hit = cheap_memo[p]
    if hit then
      return hit
    end
    if cheap_count >= CHEAP_MAX then
      cheap_memo, cheap_count = {}, 0
    end
    local k = fold(p)
    cheap_memo[p], cheap_count = k, cheap_count + 1
    return k
  end
  -- Relative to the working directory, which can change.
  return fold(uv.cwd() .. "/" .. p)
end

--- The file slots of `list` that point at the file `name` (a buffer's name).
--- A slot is known by the path as written, which costs nothing; only up to
--- `exact_max` of the slots that do not match that way are asked again by their
--- real path (a link to the file, a placeholder, another spelling). A list of
--- ten thousand slots is walked on every window switch: this must stay cheap.
---@param name string
---@param list Ui.Slots.Slot[]
---@param first_only boolean|nil
---@param exact_max integer|nil  # default 30
---@return Ui.Slots.Slot[]
function M.matching(name, list, first_only, exact_max)
  local out = {}
  if type(name) ~= "string" or name == "" then
    return out
  end
  local want = fold(name)
  local real
  local budget = exact_max or 30
  for _, slot in ipairs(list) do
    if slot.kind == "file" and type(slot.path) == "string" then
      local hit = false
      local cheap = cheap_slot_key(slot)
      if cheap ~= nil and cheap == want then
        hit = true
      elseif budget > 0 then
        budget = budget - 1
        local path = target_path(slot)
        if path ~= "" then
          real = real or key(name)
          hit = cached_key(path) == real
        end
      end
      if hit then
        out[#out + 1] = slot
        if first_only then
          return out
        end
      end
    end
  end
  return out
end

--- Remember where the cursor is in the current buffer, for the file slot(s)
--- that point at it. Slots in the data file keep it across restarts; fixed
--- slots (which cannot be changed) and every other file keep it for the
--- session. Meant for `BufLeave`.
---@return nil
function M.remember_current()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" or vim.bo.buftype ~= "" then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line, col = cursor[1], cursor[2] + 1
  positions[cached_key(name)] = { line = line, col = col }

  local store = require("ui.slots.store")
  for _, slot in ipairs(M.matching(name, store.list())) do
    if not slot.fixed and (slot.line ~= line or slot.col ~= col) then
      store.update(slot.n, { line = line, col = col })
    end
  end
end

--- Where the cursor was last left in `path` this session, or nil.
---@param path string
---@return { line: integer, col: integer }|nil
function M.position(path)
  return positions[key(path)]
end

--- Forget the session positions (tests).
function M.forget_positions()
  positions = {}
  key_cache, key_count = {}, 0
  cheap_memo, cheap_count = {}, 0
end

return M
