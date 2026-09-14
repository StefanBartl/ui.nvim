---@module 'ui.statusline.modules.lsp.symbols.document_symbols'
--- Fully async LSP document symbols with debouncing and proper error handling

local Autocmd = require("lib.nvim.bindings.autocmd")
local debounce_buffer = require("lib.nvim.debounce.buffer")

local M = {}

local api = vim.api

-- Lazy-load config
local options
local function get_options()
  if not options then
    options = require("ui.statusline.modules.lsp.config").get_cfg()
  end
  return options
end

---@enum Ui.UI.Status.Modules.Lsp.Symbols.Kind
local LspKind = {
  File = 1,
  Module = 2,
  Namespace = 3,
  Package = 4,
  Class = 5,
  Method = 6,
  Property = 7,
  Field = 8,
  Constructor = 9,
  Enum = 10,
  Interface = 11,
  Function = 12,
  Variable = 13,
  Constant = 14,
  String = 15,
  Number = 16,
  Boolean = 17,
  Array = 18,
  Object = 19,
  Key = 20,
  Null = 21,
  EnumMember = 22,
  Struct = 23,
  Event = 24,
  Operator = 25,
  TypeParameter = 26,
}

---@type integer[]
local DEFAULT_KEEP_KINDS = {
  LspKind.Namespace,
  LspKind.Module,
  LspKind.Class,
  LspKind.Struct,
  LspKind.Interface,
  LspKind.Enum,
  LspKind.Function,
  LspKind.Method,
  LspKind.Constructor,
  LspKind.Property,
  LspKind.Field,
  LspKind.EnumMember,
}

---@type table<integer, Ui.UI.Status.Modules.Lsp.Symbols.Doc.SymCache>
M.__lsp_doc_cache = M.__lsp_doc_cache or {}

---@nodiscard
---@param bufnr integer
---@return integer
local function current_tick(bufnr)
  local ok, b = pcall(api.nvim_buf_get_var, bufnr, "changedtick")
  if ok and type(b) == "number" then
    return b
  end
  return vim.b[bufnr] and vim.b[bufnr].changedtick or 0
end

---@nodiscard
---@param range table
---@param l integer
---@param c integer
---@return boolean
local function range_contains(range, l, c)
  if not range or not range.start or not range["end"] then
    return false
  end
  local sL, sC = range.start.line, range.start.character
  local eL, eC = range["end"].line, range["end"].character

  if l < sL or (l == sL and c < sC) then
    return false
  end
  if l > eL or (l == eL and c > eC) then
    return false
  end
  return true
end

---@nodiscard
---@param sym table
---@return string
local function symbol_display_name(sym)
  local name = sym.name or ""
  if sym.detail and #sym.detail > 0 then
    local short = sym.detail:match("([%w_%.:]+)%s*%(") or sym.detail:match("([%w_%.:]+)$")
    if short and #short > 0 and #short < (#name + 3) then
      name = short
    end
  end
  return name
end

---@nodiscard
---@param kind integer
---@param name string
---@return string
local function maybe_callish(kind, name)
  if (kind == LspKind.Function) or (kind == LspKind.Method) or (kind == LspKind.Constructor) then
    if not name:find("%)$") then
      return name .. "()"
    end
  end
  return name
end

---@param bufnr integer
local function request_doc_symbols_async(bufnr)
  -- Validate buffer first
  local ok_valid, is_valid = pcall(api.nvim_buf_is_loaded, bufnr)
  if not ok_valid or not is_valid then
    return
  end

  local cache = M.__lsp_doc_cache[bufnr]
    or {
      version = -1,
      items = nil,
      hierarchical = false,
      client_id = nil,
      last_req = 0,
      pending = false,
    }

  -- Skip if already pending
  if cache.pending then
    return
  end

  cache.pending = true
  M.__lsp_doc_cache[bufnr] = cache

  -- Create params safely
  local ok_params, params = pcall(vim.lsp.util.make_text_document_params, bufnr)
  if not ok_params then
    cache.pending = false
    return
  end

  -- Snapshot the tick the request was made for — the buffer may advance
  -- past it (another edit) while the request is in flight, and stamping
  -- the cache with the tick *at response time* would mark a stale result
  -- as fresh, suppressing the refresh that should follow the next edit.
  local req_tick = current_tick(bufnr)

  local function on_result(err, result, ctx)
    cache.pending = false
    cache.last_req = vim.uv.now()

    if err or not result then
      return
    end

    local hierarchical = (result[1] and result[1].range ~= nil)
    cache.items = result
    cache.hierarchical = hierarchical
    cache.client_id = ctx and ctx.client_id or nil
    cache.version = req_tick

    -- Schedule redraw safely
    local function redraw()
      local ok = pcall(function()
        vim.cmd("redrawstatus")
      end)
      if not ok then
        -- Silently fail if redraw not possible
        require("lib").noop()
      end
    end

    if vim.in_fast_event() then
      vim.schedule(redraw)
    else
      redraw()
    end
  end

  -- Find client with documentSymbolProvider
  local requested = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local caps = client.server_capabilities or {}
    if caps.documentSymbolProvider then
      requested = true
      vim.lsp.buf_request(bufnr, "textDocument/documentSymbol", params, on_result)
      break
    end
  end

  if not requested then
    cache.items = nil
    cache.hierarchical = false
    cache.client_id = nil
    cache.pending = false
  end
end

---Per-buffer debounced trigger for `request_doc_symbols_async` — one
---independent timer per bufnr, auto-cancelled on BufDelete/BufWipeout by
---`lib.nvim.debounce.buffer` itself (see the module's own README), so the
---manual `BufDelete` timer cleanup below is no longer needed.
---@type Lib.Debounce.BufferHandle|nil
local doc_symbols_debounce
---@return Lib.Debounce.BufferHandle
local function get_doc_symbols_debounce()
  if not doc_symbols_debounce then
    doc_symbols_debounce = debounce_buffer.new(function(bufnr)
      local ok_valid, is_valid = pcall(api.nvim_buf_is_valid, bufnr)
      if ok_valid and is_valid then
        request_doc_symbols_async(bufnr)
      end
    end, { ms = get_options().debounce_ms or 250 })
  end
  return doc_symbols_debounce
end

---@param bufnr integer
local function ensure_doc_symbols_in_bg(bufnr)
  local opts = get_options()
  local now = vim.uv.now()
  local cache = M.__lsp_doc_cache[bufnr]
  local tick = current_tick(bufnr)

  -- Skip if cache is fresh
  if cache and cache.version == tick then
    return
  end

  -- Skip if pending
  if cache and cache.pending then
    return
  end

  -- Debounce: skip if request was too recent
  if cache and (now - (cache.last_req or 0) < (opts.debounce_ms or 250)) then
    return
  end

  get_doc_symbols_debounce().call(bufnr)
end

-- Auto-update setup
do
  if not rawget(M, "__au_lsp_breadcrumbs") then
    local opts = get_options()
    local aug = Autocmd.group("LspBreadcrumbsAsync", true)

    for _, ev in ipairs(opts.update_events) do
      Autocmd.create(ev, function(args)
        local bufnr = args.buf or 0
        if bufnr <= 0 then
          bufnr = api.nvim_get_current_buf()
        end
        ensure_doc_symbols_in_bg(bufnr)
      end, {
        group = aug,
        desc = "Warm LSP documentSymbol cache for breadcrumbs",
      })
    end

    M.__au_lsp_breadcrumbs = true
  end
end

---@nodiscard
---@param bufnr integer
---@return table[]|nil items, boolean hierarchical
local function get_cached_doc_symbols(bufnr)
  local cache = M.__lsp_doc_cache[bufnr]
  if cache and cache.items and cache.version == current_tick(bufnr) then
    return cache.items, cache.hierarchical
  end
  return nil, false
end

---Walk a hierarchical outline, collecting the chain of ancestor symbols that
---contain (l, c), then filtering it down to DEFAULT_KEEP_KINDS.
---@param list table[]
---@param l integer
---@param c integer
---@return table[]
local function locate_in_hierarchical(list, l, c)
  local best_path = {}
  local function walk(nodes, path)
    for _, sym in ipairs(nodes) do
      if sym.range and range_contains(sym.range, l, c) then
        -- Shallow copy: `path` holds references to already-matched symbol
        -- tables (each potentially carrying its own `children` subtree), so
        -- a deep copy here would clone subtrees no caller ever reads through
        -- `this` -- only an independent *array* of those references is
        -- needed so sibling branches don't clobber each other's path.
        local this = {}
        for i, v in ipairs(path) do
          this[i] = v
        end
        table.insert(this, sym)
        if sym.children and #sym.children > 0 then
          walk(sym.children, this)
        else
          best_path = this
        end
      end
    end
  end
  walk(list, {})

  if #best_path == 0 then
    return {}
  end

  local filtered = {}
  for _, s in ipairs(best_path) do
    for _, k in ipairs(DEFAULT_KEEP_KINDS) do
      if (s.kind or 0) == k then
        table.insert(filtered, s)
        break
      end
    end
  end
  return filtered
end

---Find the innermost flat symbol whose range contains (l, c).
---@param infos table[]
---@param l integer
---@param c integer
---@return table[]
local function locate_in_flat(infos, l, c)
  local best, best_span
  for _, si in ipairs(infos) do
    local loc = si.location
    local range = loc and loc.range
    if range and range_contains(range, l, c) then
      local sL, sC = range.start.line, range.start.character
      local eL, eC = range["end"].line, range["end"].character
      local span = (eL - sL) * 10000 + (eC - sC)
      if not best or span < best_span then
        best, best_span = si, span
      end
    end
  end

  if not best then
    return {}
  end

  local ok = false
  for _, k in ipairs(DEFAULT_KEEP_KINDS) do
    if (best.kind or 0) == k then
      ok = true
      break
    end
  end

  if not ok then
    return {}
  end

  return { best }
end

---@nodiscard
---@return string|nil
function M.symbol_context_lsp()
  local utils = require("ui.statusline.utils.primitives")
  local bufnr = utils.stbufnr()
  local items, hierarchical = get_cached_doc_symbols(bufnr)

  if not items then
    ensure_doc_symbols_in_bg(bufnr)
    return nil
  end

  -- Safe cursor retrieval with type guards
  local ok_cur, cur = pcall(api.nvim_win_get_cursor, 0)
  if not ok_cur or type(cur) ~= "table" or #cur < 2 then
    return nil
  end

  local l0, c0 = cur[1] - 1, cur[2]
  if type(l0) ~= "number" or type(c0) ~= "number" then
    return nil
  end

  local path_syms = hierarchical and locate_in_hierarchical(items, l0, c0)
    or locate_in_flat(items, l0, c0)

  if #path_syms == 0 then
    return nil
  end

  local names = {}
  for _, s in ipairs(path_syms) do
    local name = symbol_display_name(s)
    name = maybe_callish(s.kind or 0, name)
    table.insert(names, name)
  end

  return (#names > 0) and table.concat(names, " → ") or nil
end

---@nodiscard
---@return string|nil
function M.symbol_context_smart()
  local ok1, ctx1 = pcall(M.symbol_context_lsp)
  if ok1 and ctx1 and #ctx1 > 0 then
    return ctx1
  end

  local ts_ok, ts_module = pcall(require, "ui.statusline.modules.lsp.symbols.treesitter")
  if ts_ok then
    local ok2, ctx2 = pcall(ts_module.symbol_context_ts)
    if ok2 and ctx2 and #ctx2 > 0 then
      return ctx2
    end
  end

  return nil
end

-- Clean up on buffer delete. The debounce timer itself needs no cleanup
-- here — lib.nvim.debounce.buffer cancels it via its own BufDelete/
-- BufWipeout autocmd (see get_doc_symbols_debounce above).
Autocmd.create("BufDelete", function(args)
  M.__lsp_doc_cache[args.buf] = nil
end, {
  group = Autocmd.group("UiLspSymbolsCache", true),
  desc = "Clear LSP symbols cache on buffer delete",
})

return M
