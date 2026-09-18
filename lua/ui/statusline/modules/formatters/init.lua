---@module 'ui.statusline.modules.formatters'
--- Statusline formatters with lib integration and performance optimizations

local M = {}

-- Use lib.strings for all string operations
local lib_strings = require("lib.lua.strings")

-- Lazy-load config
local config_module
local function get_config()
  if not config_module then
    ---@type Ui.UI.Stl.Modules.LSP.Cfg.Module
    config_module = require("ui.statusline.modules.lsp.config")
  end
  return config_module
end

-- String pool using lib.memo.lru
local escape_cache = require("lib.lua.memo.lru").new(128)
local ellipsize_cache = require("lib.lua.memo.lru").new(64)

-- Clear on colorscheme change
require("lib.nvim.ui.hl").persist(function()
  escape_cache = require("lib.lua.memo.lru").new(128)
end, { name = "UiFormattersCache", immediate = false })

---@nodiscard
---@param s string
---@return string
function M.stl_escape(s)
  if not s or s == "" then
    return ""
  end

  local cached = escape_cache:get(s)
  if cached then
    return cached
  end

  -- Use lib.strings.replace_all for clarity
  local result = lib_strings.replace_all(s, "%", "%%")
  escape_cache:put(s, result)
  return result
end

---@nodiscard
--- `max` is a display-column budget (statusline space), not a byte count:
--- `#s`/`string.sub` would measure and cut in bytes, which for any
--- multi-byte character (umlauts, CJK, emoji -- all ordinary in filenames
--- and LSP symbol names) either mis-measures the budget or slices a
--- character in half, leaving a dangling UTF-8 continuation byte in the
--- rendered statusline. Walked in codepoints via `lib.lua.strings` so both
--- the head and tail cuts land on a character boundary.
---@param s string
---@param max integer
---@return string
function M.ellipsize_middle(s, max)
  if type(s) ~= "string" then
    return ""
  end

  if max <= 0 or lib_strings.display_width(s) <= max then
    return s
  end

  local cache_key = s .. ":" .. tostring(max)
  local cached = ellipsize_cache:get(cache_key)
  if cached then
    return cached
  end

  -- One forward pass over the codepoints, each paired with its byte start,
  -- so the head walk (forward) and tail walk (backward) below can both
  -- find a safe cut point without re-decoding.
  local chars = {}
  for cp, byte_index in lib_strings.utf8_iter(s) do
    chars[#chars + 1] = { cp = cp, start = byte_index }
  end
  local n = #chars

  ---@param i integer
  ---@return integer # byte index of the last byte of chars[i]
  local function char_end(i)
    return (i < n) and (chars[i + 1].start - 1) or #s
  end

  local ellipsis_w = lib_strings.display_width("…")
  local head_budget = math.floor((max - ellipsis_w) / 2)
  local tail_budget = max - ellipsis_w - head_budget

  local head_end, col = 0, 0
  for i = 1, n do
    local w = lib_strings.char_width(chars[i].cp)
    if col + w > head_budget then
      break
    end
    col = col + w
    head_end = char_end(i)
  end

  local tail_start, col2 = #s + 1, 0
  for i = n, 1, -1 do
    local w = lib_strings.char_width(chars[i].cp)
    if col2 + w > tail_budget then
      break
    end
    col2 = col2 + w
    tail_start = chars[i].start
  end

  -- A very tight budget can make the two walks meet or cross (e.g. `max`
  -- barely bigger than the ellipsis itself) -- never let the tail repeat
  -- bytes the head already kept.
  if tail_start <= head_end then
    tail_start = head_end + 1
  end

  local result = s:sub(1, head_end) .. "…" .. s:sub(tail_start)
  ellipsize_cache:put(cache_key, result)
  return result
end

---@nodiscard
--- Component-aware path ellipsization with proper Windows/POSIX support.
---
--- `max` is a display-column budget, same as `ellipsize_middle` above --
--- every `#x` below against `max`/`room`/`target` measures display width,
--- not bytes, so a path with umlauts/CJK components is not judged "too
--- long" more harshly than it actually renders. Table lengths (`#parts`,
--- `#right`, the component array itself) are left as-is; those count
--- entries, not string bytes, and are unaffected either way. Cuts still
--- only ever happen at a `/` component boundary, so unlike
--- `ellipsize_middle` there is no mid-character byte-split risk here.
---@param path string
---@param max integer
---@return string
function M.ellipsize_path_components(path, max)
  -- Fast path
  if max <= 0 or lib_strings.display_width(path) <= max then
    return path
  end

  -- Normalize separators using lib
  local p = lib_strings.replace_all(path, "\\", "/")

  -- Extract prefix (drive, tilde, root)
  local prefix = ""
  local rest = p

  -- Windows drive (normalized)
  local drive = rest:match("^([A-Za-z]:)/")
  if drive then
    prefix = drive .. "/"
    rest = rest:sub(#drive + 2)
  elseif lib_strings.starts_with(rest, "~/") then
    prefix = "~"
    rest = rest:sub(3)
  elseif lib_strings.starts_with(rest, "/") then
    prefix = "/"
    rest = rest:sub(2)
  end

  -- Split into components using lib.strings
  local parts = lib_strings.split(rest, "/")

  -- Filter empty parts
  local filtered = {}
  for _, part in ipairs(parts) do
    if part ~= "" then
      table.insert(filtered, part)
    end
  end
  parts = filtered

  -- Reconstruct with concat (efficient)
  local function join_all()
    if #parts == 0 then
      return prefix
    end
    return prefix .. table.concat(parts, "/")
  end

  local full = join_all()
  if lib_strings.display_width(full) <= max then
    return full
  end

  -- Need ellipsis
  if #parts <= 1 then
    return M.ellipsize_middle(full, max)
  end

  local first = parts[1]
  local last = parts[#parts]

  -- Minimal form
  local min_parts = { prefix, first, "/…/", last }
  local min_s = table.concat(min_parts, "")

  if lib_strings.display_width(min_s) > max then
    local alt = (prefix ~= "" and (prefix .. "…/" .. last)) or ("…/" .. last)
    if lib_strings.display_width(alt) <= max then
      return alt
    end
    return M.ellipsize_middle(full, max)
  end

  -- Greedy addition from right
  local right = {}
  local cur = lib_strings.display_width(min_s)
  local i = #parts - 1

  while i >= 2 do
    local cand_len = cur + 1 + lib_strings.display_width(parts[i])
    if cand_len > max then
      break
    end
    table.insert(right, 1, parts[i])
    cur = cand_len
    i = i - 1
  end

  if #right == 0 then
    return min_s
  end

  -- Build final with table.concat
  local final_parts = { prefix, first, "/…/", table.concat(right, "/"), "/", last }
  return table.concat(final_parts, "")
end

---@nodiscard
--- Build compact breadcrumb line with intelligent path shortening.
---
--- `target`/`room` are display-column budgets (`vim.o.columns`-derived),
--- so the length checks against them below measure display width, same
--- reasoning as `ellipsize_path_components` above -- `ctx` is LSP/
--- Tree-sitter symbol text and just as capable of holding non-ASCII
--- identifiers as a path component is. `#ctx > 0` stays a plain
--- emptiness check: byte-empty and display-empty are the same string.
---@param rel string
---@param ctx string|nil
---@param sep string
---@param total_maxw integer|nil
---@return string
function M.compact_breadcrumb_line(rel, ctx, sep, total_maxw)
  local cfg = get_config()
  local options = cfg.get_cfg()

  local target = total_maxw
  if not target or target <= 0 then
    local frac = options.center_width_frac or 0.50
    local minw = options.center_width_min or 30
    target = math.max(minw, math.floor(vim.o.columns * frac))
  end

  if ctx and #ctx > 0 then
    local static_len = lib_strings.display_width(sep) + lib_strings.display_width(ctx)
    local room = target - static_len

    if options.path_max_chars then
      room = math.min(room, options.path_max_chars)
    else
      local pfrac = options.path_max_frac or 0.60
      room = math.min(room, math.floor(target * pfrac))
    end

    if room > (options.path_min_room or 8) then
      local rel_compact = M.ellipsize_path_components(rel, room)

      -- Build with table.concat
      local parts = { rel_compact, sep, ctx }
      local candidate = table.concat(parts, "")

      if lib_strings.display_width(candidate) <= target then
        return candidate
      else
        return M.ellipsize_middle(candidate, target)
      end
    else
      -- Build with table.concat
      local parts = { rel, sep, ctx }
      return M.ellipsize_middle(table.concat(parts, ""), target)
    end
  else
    -- No context: only shorten path
    local limit = options.path_max_chars or target
    local compact = M.ellipsize_path_components(rel, limit)

    if lib_strings.display_width(compact) > target then
      compact = M.ellipsize_middle(compact, target)
    end

    return compact
  end
end

return M
