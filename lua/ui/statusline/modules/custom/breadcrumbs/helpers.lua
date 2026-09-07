---@module 'ui.statusline.modules.custom.breadcrumbs.helpers'
-------------------------------------
-- BREADCRUMBS HELPER
-------------------------------------

local M = {}

local fnamemodify = vim.fn.fnamemodify

--- Escape % so user text cannot break statusline sequences.
--- @param s string
--- @return string
function M.stl_escape(s)
  return (s:gsub("%%", "%%%%"))
end

--- Ellipsize in the middle to a maximum length (display width aware enough for ASCII).
--- @param s string
--- @param max integer
--- @return string
function M.ellipsize_middle(s, max)
  if #s <= max then
    return s
  end
  local head = math.floor((max - 1) / 2)
  local tail = max - head - 1
  return string.sub(s, 1, head) .. "…" .. string.sub(s, #s - tail + 1, #s)
end

--- Repo-/project-relative path (fallback: path relative to cwd; final fallback: tail).
--- @param path string
--- @return string
function M.repo_relative(path)
  if path == "" then
    return "[No Name]"
  end
  local dir = fnamemodify(path, ":h")
  local gitdir = vim.fs.find(".git", { upward = true, path = dir })[1]
  if gitdir then
    local root = fnamemodify(gitdir, ":h")
    local rel = fnamemodify(path, (":~:%s"):format(root))
    if rel == path then
      return fnamemodify(path, ":t")
    end
    rel = rel:gsub("^%./", ""):gsub("^/", "")
    return rel
  else
    return fnamemodify(path, ":~:.")
  end
end

--- Try to extract a concise symbol path near the cursor (Treesitter → LSP → nil).
--- Only keeps named semantic nodes; avoids generic "block" noise.
--- @return string|nil
function M.symbol_context()
  local ok_ts = pcall(require, "vim.treesitter")
  local ok_utils, tsu = pcall(require, "nvim-treesitter.ts_utils")
  if not ok_ts or not ok_utils or not tsu then
    return nil
  end

  local node = tsu.get_node_at_cursor()
  if not node then
    return nil
  end

  local keep = {
    function_declaration = true,
    function_definition = true,
    method_declaration = true,
    method_definition = true,
    class_declaration = true,
    class_specifier = true,
    struct_specifier = true,
    interface_declaration = true,
    module_declaration = true,
    namespace_definition = true,
    impl_item = true, -- rust
  }

  --- CDX: revival-target cleanup (see custom/init.lua) -- this is defined as a
  --- module field inside symbol_context(), so every call re-assigns
  --- M.ts_identifier_of. Should be `local function ts_identifier_of`
  --- (as in ../../lsp/symbols/treesitter.lua).
  function M.ts_identifier_of(n)
    -- 1) Named field "name"
    local named = n:field("name")
    if named and named[1] then
      local t = vim.treesitter.get_node_text(named[1], 0)
      if t and #t > 0 then
        return t
      end
    end
    -- 2) Shallow search for common identifier-like node types
    local want = {
      "identifier",
      "property_identifier",
      "field_identifier",
      "type_identifier",
      "name",
    }
    local function in_list(x)
      for _, w in ipairs(want) do
        if x == w then
          return true
        end
      end
    end
    local function first_ident(m, depth)
      depth = depth or 0
      if depth > 2 then
        return nil
      end
      if in_list(m:type()) then
        local t = vim.treesitter.get_node_text(m, 0)
        if t and #t > 0 then
          return t
        end
      end
      for i = 0, m:child_count() - 1 do
        local r = first_ident(m:child(i), depth + 1)
        if r then
          return r
        end
      end
      return nil
    end
    local t = first_ident(n, 0)
    if t and #t > 0 then
      return t
    end
    -- 3) Final fallback: first plausible token from the line
    local raw = vim.treesitter.get_node_text(n, 0) or ""
    raw = raw:gsub("^%s+", ""):gsub("\n.*", "")
    local guess = raw:match("^%w+%s+([%w_]+)%s*%(")
      or raw:match("^%w+%s+([%w_]+)%s*[={:]")
      or raw:match("^([%w_%.:]+)%s*%(")
      or raw:match("^([%w_%.:]+)")
    return guess
  end

  local names = {}
  local u = node
  while u do
    local t = u:type()
    if keep[t] then
      local ident = M.ts_identifier_of(u)
      if ident and #ident > 0 then
        if t:find("function") or t:find("method") then
          if not ident:find("%)$") then
            ident = ident .. "()"
          end
        end
        table.insert(names, 1, ident)
      end
    end
    local p = u:parent()
    if not p or p == u then
      break
    end
    u = p
  end

  if #names == 0 then
    return nil
  end
  return table.concat(names, " → ")
end

return M
