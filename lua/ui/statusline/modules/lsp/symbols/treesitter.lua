---@module 'ui.statusline.modules.lsp.symbols.treesitter'
--- Breadcrumb of the treesitter node context around the cursor (function/
--- class/block names), the fallback the statusline's symbol module reaches
--- for when no LSP is attached to supply the same thing.

local M = {}

--------------------------------------------------------------------------------
-- Treesitter context (robust fallback)
--------------------------------------------------------------------------------

-- Node types to keep as "semantic anchors" (broadly scoped). Module-level:
-- this runs on every breadcrumb render when no LSP is attached, so the table
-- is built once here instead of being re-allocated on every call.
local TS_KEEP_TYPES = {
  -- Functions/methods/classes/namespaces
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
  impl_item = true,

  -- Common containers/members/calls across grammars
  variable_declaration = true, -- JS/TS/C-like
  lexical_declaration = true, -- JS/TS (let/const)
  local_declaration = true, -- Lua (local ...)
  variable_declarator = true, -- JS/TS/C-like
  init_declarator = true, -- C/C++
  assignment_statement = true, -- Lua/C-like
  declaration = true, -- generic

  member_expression = true, -- JS/TS
  field_expression = true, -- Lua (a.b)
  dot_index_expression = true, -- Lua (a.b)
  method_index_expression = true, -- Lua (a:b)
  index_expression = true, -- Lua/JS (a[b])

  property_declaration = true, -- TS/Java/C#
  field_declaration = true, -- C/C++/Rust
  property_signature = true, -- TS interface

  call_expression = true, -- many languages
  function_call = true, -- Lua
}

-- Common identifier node types, for the shallow search in ts_identifier_of.
local TS_IDENT_TYPES = {
  "identifier",
  "property_identifier",
  "field_identifier",
  "type_identifier",
  "name",
  "shorthand_property_identifier",
  "variable_name",
}

---@param x string
---@return boolean
local function is_ident_type(x)
  for _, w in ipairs(TS_IDENT_TYPES) do
    if x == w then
      return true
    end
  end
  return false
end

---@param m TSNode|nil
---@param depth integer|nil
---@return string|nil
local function first_ident(m, depth)
  depth = depth or 0
  if depth > 2 or not m then
    return nil
  end
  if is_ident_type(m:type()) then
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

--- Extract a useful identifier from a node:
--- 1) "name" field, 2) shallow search for identifier nodes,
--- 3) line-based heuristic (incl. member chains a.b.c[:method]())
---@param n TSNode
---@return string|nil
local function ts_identifier_of(n)
  -- 1) Direct named field
  local named = n:field("name")
  if named and named[1] then
    local t = vim.treesitter.get_node_text(named[1], 0)
    if t and #t > 0 then
      return t
    end
  end

  -- 2) Shallow search for common identifier node types
  local t2 = first_ident(n, 0)
  if t2 and #t2 > 0 then
    return t2
  end

  -- 3) Line/text heuristic (member chains and call signatures)
  local raw = vim.treesitter.get_node_text(n, 0) or ""
  -- Strip whitespace, aim at the last chain near the cursor
  local s = raw:gsub("%s+", "")
  -- Candidates: foo.bar.baz  |  obj:method  |  foo["bar"].baz
  local chain = s:match("([%w_%.:]+)%s*$") or s:match("([%w_]+%b[][%w_%.%[%]]*)%s*$")
  if chain and #chain > 0 then
    -- Drop trailing parens so "method()" -> "method" ("()" re-appended later)
    chain = chain:gsub("%(%s*%)$", "")
    return chain
  end

  -- Generic fallbacks
  local guess = raw:match("^%w+%s+([%w_]+)%s*%(")
    or raw:match("^%w+%s+([%w_]+)%s*[={:]")
    or raw:match("^([%w_%.:]+)%s*%(")
    or raw:match("^([%w_%.:]+)")
  return guess
end

---@nodiscard
---@return string|nil
function M.symbol_context_ts()
  -- Guard: Treesitter & ts_utils must be available
  local ok_ts = pcall(require, "vim.treesitter")
  local ok_utils, tsu = pcall(require, "nvim-treesitter.ts_utils")
  if not ok_ts or not ok_utils or not tsu then
    return nil
  end

  -- Node at cursor
  local node = tsu.get_node_at_cursor()
  if not node then
    return nil
  end

  -- Collect names (prepend outer-to-inner)
  ---@type string[]
  local names = {}
  local u = node
  while u do
    local t = u:type()

    if TS_KEEP_TYPES[t] then
      local ident = ts_identifier_of(u)

      -- For member expressions, prefer just the right end of the chain (e.g. "enable_line").
      -- Optional: show the whole path instead:
      -- ident = ident and ident:gsub("^.+[%.:]", "") or ident
      if ident and #ident > 0 then
        -- Render function/method/call nodes visually as a call
        if t:find("function") or t:find("method") or t:find("call") then
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
