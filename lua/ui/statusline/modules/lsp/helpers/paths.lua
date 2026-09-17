---@module 'ui.statusline.modules.lsp.helpers.paths'
--- Optimized path helpers with buffer-tick-aware caching

local M = {}

local api, fn, fs, uv = vim.api, vim.fn, vim.fs, vim.uv or vim.loop

-- Cache with buffer-tick awareness
local path_cache = require("lib.lua.memo.lru").new(128)
local Autocmd = require("lib.nvim.bindings.autocmd")
local tick_cache = {} -- bufnr -> { tick, abs_path }

--- Get current buffer tick (for cache invalidation)
---@param bufnr integer
---@return integer
local function get_tick(bufnr)
  local ok, b = pcall(vim.api.nvim_buf_get_var, bufnr, "changedtick")
  if ok and type(b) == "number" then
    return b
  end
  return vim.b[bufnr] and vim.b[bufnr].changedtick or 0
end

--- Normalize separators (pure function)
---@param s string
---@return string
local function norm_sep(s)
  s = tostring(s or ""):gsub("\\", "/")
  s = s:gsub("([^:])/+", "%1/")
  s = s:gsub("/%./", "/")
  s = s:gsub("^([A-Za-z]):/", function(d)
    return string.upper(d) .. ":/"
  end)
  return s
end

---@nodiscard
--- Make absolute path with buffer-tick caching
---@param path_or_buf integer|string
---@return string
function M.path_absolute(path_or_buf)
  -- Fast path for buffers, with tick check
  if type(path_or_buf) == "number" then
    local bufnr = path_or_buf

    -- Validate buffer
    local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
    if not ok_valid or not is_valid then
      return ""
    end

    -- Check tick cache
    local current_tick = get_tick(bufnr)
    local cached = tick_cache[bufnr]

    if cached and cached.tick == current_tick then
      return cached.abs_path
    end

    -- Cache miss → compute
    local ok_name, path = pcall(api.nvim_buf_get_name, bufnr)
    if not ok_name or not path or path == "" then
      return ""
    end

    local abs = fn.fnamemodify(path, ":p")
    local ok_real, real = pcall(uv.fs_realpath, abs)
    local canon = ok_real and real or abs
    local result = norm_sep(tostring(canon))

    -- Update tick cache
    tick_cache[bufnr] = {
      tick = current_tick,
      abs_path = result,
    }

    return result
  end

  -- String path → use LRU cache
  local path = tostring(path_or_buf or "")
  if path == "" then
    return ""
  end

  local cache_key = "abs:" .. path
  local cached = path_cache:get(cache_key)
  if cached then
    return cached
  end

  local abs = fn.fnamemodify(path, ":p")
  local ok_real, real = pcall(uv.fs_realpath, abs)
  local canon = ok_real and real or abs
  local result = norm_sep(tostring(canon))

  path_cache:put(cache_key, result)
  return result
end

---@nodiscard
--- Find Git root with aggressive caching
---@param path string
---@return string|nil
local function find_git_root(path)
  -- Cache key is per-directory, not per-file
  local dir = fn.fnamemodify(path, ":h")
  local cache_key = "git:" .. dir
  -- `~= nil`, not a truthiness test: the "no root" result below is cached as
  -- `false`, which a truthiness test reads as a cache miss -- so every file
  -- outside a git repo re-ran the upward `.git` scan on every redraw, which
  -- is exactly the case the negative entry exists to avoid.
  local cached = path_cache:get(cache_key)
  if cached ~= nil then
    return cached or nil
  end

  local froot = nil
  if fs.root then
    froot = fs.root(dir, ".git")
  else
    local git_hit = (fs.find(".git", { upward = true, path = dir }) or {})[1]
    if git_hit then
      froot = fn.fnamemodify(git_hit, ":h")
    end
  end

  if not froot or froot == "" then
    path_cache:put(cache_key, false) -- cache the explicit "no root" result
    return nil
  end

  -- Worktree check
  local git_path = norm_sep(froot .. "/.git")
  local stat = uv.fs_stat(git_path)

  if stat and stat.type == "file" then
    local fd = uv.fs_open(git_path, "r", 438)
    if fd then
      local content = uv.fs_read(fd, stat.size or 4096, 0) or ""
      uv.fs_close(fd)
      local gitdir = content:match("gitdir:%s*(.-)%s*$")
      if gitdir and #gitdir > 0 then
        local result = norm_sep(froot)
        path_cache:put(cache_key, result)
        return result
      end
    end
  end

  local result = norm_sep(froot)
  path_cache:put(cache_key, result)
  return result
end

--- Shorten with home tilde (uses lib.cross for cross-platform).
--- `override`, when not nil, wins over the module's own live config -- lets
--- a caller request a specific style for one call without mutating shared
--- state (see M.display_path, which used to do exactly that).
---@param s string
---@param override? boolean
---@return string
local function home_tilde(s, override)
  local use_tilde
  if override ~= nil then
    use_tilde = override
  else
    local config_mod = require("ui.statusline.modules.lsp.config")
    use_tilde = config_mod.get_cfg().path_home_tilde
  end

  if not use_tilde then
    return s
  end

  local home = norm_sep(uv.os_homedir() or "")
  if home ~= "" and s:sub(1, #home) == home then
    local rest = s:sub(#home + 1)
    if rest == "" then
      return "~"
    end
    if rest:sub(1, 1) == "/" then
      rest = rest:sub(2)
    end
    return "~/" .. rest
  end
  return s
end

--- Relative path computation (pure)
---@param base string
---@param path string
---@return string
local function rel_from(base, path)
  base = norm_sep(base)
  path = norm_sep(path)

  -- Different drives on Windows
  if base:match("^[A-Za-z]:/") and path:match("^[A-Za-z]:/") then
    if base:sub(1, 1) ~= path:sub(1, 1) then
      return path
    end
  end

  if path:sub(1, #base) == base then
    local rest = path:sub(#base + 1)
    if rest == "" then
      return "."
    end
    return (rest:sub(1, 1) == "/") and rest:sub(2) or rest
  end
  return path
end

---@nodiscard
---@param mode '"repo"'|'"cwd"'|'"home"'
---@param path string
---@param home_tilde_override? boolean # see M.display_path
---@return string
function M.path_relative(mode, path, home_tilde_override)
  local abs = M.path_absolute(path)
  if abs == "" then
    return "[No Name]"
  end

  -- The "repo" (no-git-root fallback) and "home" branches both feed through
  -- home_tilde(), whose output depends on home_tilde_override -- the cache
  -- key must include it (PERF-46), or a cached "repo"/"home" result for this
  -- path silently keeps serving the tilde-state from whichever call happened
  -- to run first.
  local cache_key = mode .. ":" .. tostring(home_tilde_override) .. ":" .. abs
  local cached = path_cache:get(cache_key)
  if cached then
    return cached
  end

  local result
  if mode == "repo" then
    local root = find_git_root(abs)
    if root and #root > 0 then
      local rel = rel_from(root, abs)
      if rel == "." then
        result = fn.fnamemodify(abs, ":t")
      else
        result = rel
      end
    else
      result = home_tilde(rel_from(uv.os_homedir() or "", abs), home_tilde_override)
    end
  elseif mode == "cwd" then
    local cwd = norm_sep(fn.getcwd())
    result = rel_from(cwd, abs)
  else -- "home"
    result = home_tilde(abs, home_tilde_override)
  end

  path_cache:put(cache_key, result)
  return result
end

---@nodiscard
--- `cfg`, when given, overrides the module's live config for THIS call only
--- -- it used to write the override into `config_mod` (`config_mod.set(...)`),
--- which meant one caller's one-off style request permanently changed what
--- every other caller of this module saw afterwards. Two statusline segments
--- (or two windows) wanting different path styles at the same time would
--- fight over that shared state; now each call is self-contained.
---@param cfg { path_mode?: string, path_home_tilde?: boolean }|nil
---@param path_or_buf integer|string
---@return string
function M.display_path(cfg, path_or_buf)
  local config_mod = require("ui.statusline.modules.lsp.config")

  local mode = (type(cfg) == "table" and cfg.path_mode) or config_mod.get("path_mode") or "auto"
  local home_tilde_override = type(cfg) == "table" and cfg.path_home_tilde or nil

  local abs = M.path_absolute(path_or_buf)
  if abs == "" then
    return "[No Name]"
  end

  if mode == "absolute" then
    return home_tilde(abs, home_tilde_override)
  elseif mode == "repo" then
    return M.path_relative("repo", abs, home_tilde_override)
  elseif mode == "cwd" then
    return M.path_relative("cwd", abs, home_tilde_override)
  elseif mode == "home" then
    return M.path_relative("home", abs, home_tilde_override)
  else -- "auto"
    local root = find_git_root(abs)
    if root then
      return rel_from(root, abs)
    end
    local cwd = norm_sep(fn.getcwd())
    local rel = rel_from(cwd, abs)
    if rel ~= abs then
      return rel
    end
    return home_tilde(abs, home_tilde_override)
  end
end

---@nodiscard
---@param bufnr integer
---@return string
function M.display_path_for_buf(bufnr)
  local config_mod = require("ui.statusline.modules.lsp.config")
  local options = config_mod.get_cfg()
  return M.display_path(
    { path_mode = options.path_mode, path_home_tilde = options.path_home_tilde },
    bufnr
  )
end

-- Clear tick cache when buffer is deleted
Autocmd.create("BufDelete", function(args)
  tick_cache[args.buf] = nil
end, {
  group = Autocmd.group("UiPathsCache", true),
  desc = "Clear path tick cache on buffer delete",
})

return M
