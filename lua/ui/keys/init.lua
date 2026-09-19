---@module 'ui.keys'
--- The keymaps under a prefix, as a menu: `:UI keys <leader>s` lists every
--- normal-mode mapping that starts with `<leader>s`, one row per next key
--- with the mapping's `desc`, and picking a row runs it. A prefix that has
--- more mappings below it than a single one becomes a drill-down group
--- (`ui.kit.menu`'s nesting), labelled from `groups` when the host named
--- it, so `<leader>s` shows "spotlight ▸" rather than a wall of two-key
--- rows.
---
--- The idea is which-key's pending-keymap popup; the difference is
--- deliberate: this is asked for, never triggered by a timeout. A popup that
--- opens on its own after `<leader>` has to intercept the pending-key state
--- of the whole editor -- the part of which-key that is genuinely hard and
--- the part nobody misses when the prompt is one key away. `ui.kit.menu`
--- already draws an anchored list with a right-aligned hint column and
--- nested levels, so the rest is reading `nvim_get_keymap`.
---
--- What is listed: buffer-local mappings of the current buffer over global
--- ones (the same precedence Neovim applies), skipping the ones whose
--- `desc` is which-key's own `which_key_ignore` marker.

local api = vim.api

local M = {}

---@class Ui.Keys.Mapping
---@field lhs string        # keytrans'd full lhs, e.g. "<Space>sK"
---@field raw string        # the raw bytes, for feedkeys
---@field rest string       # keytrans'd part after the prefix
---@field tokens string[]   # `rest` split into key tokens
---@field desc string|nil
---@field rhs string|nil
---@field buffer boolean

---@class Ui.Keys.Node
---@field token string
---@field mapping Ui.Keys.Mapping|nil    # a leaf
---@field children Ui.Keys.Node[]|nil    # a group
---@field label string

---@class Ui.Keys.Opts
---@field mode? string                     # default "n"
---@field groups? table<string, string>    # prefix (as typed, e.g. "<leader>s") -> label
---@field title? string
---@field default_prefix? string           # for `:UI keys` with no argument

---@class Ui.Keys.Config
---@field mode string
---@field groups table<string, string>
---@field default_prefix string
local cfg = {
  mode = "n",
  groups = {},
  default_prefix = "<leader>",
}

---@internal
---@param lhs string
---@return string raw
local function raw_of(lhs)
  return api.nvim_replace_termcodes(lhs, true, true, true)
end

---@internal
---Split a keytrans'd string into tokens: `<C-x>` stays one, plain chars
---are one each.
---@param s string
---@return string[]
local function tokens_of(s)
  local out = {}
  local i = 1
  while i <= #s do
    if s:sub(i, i) == "<" then
      local close = s:find(">", i, true)
      if close then
        out[#out + 1] = s:sub(i, close)
        i = close + 1
      else
        out[#out + 1] = "<"
        i = i + 1
      end
    else
      -- One UTF-8 character.
      local c = s:sub(i, i)
      local len = 1
      local b = c:byte()
      if b >= 0xF0 then
        len = 4
      elseif b >= 0xE0 then
        len = 3
      elseif b >= 0xC0 then
        len = 2
      end
      out[#out + 1] = s:sub(i, i + len - 1)
      i = i + len
    end
  end
  return out
end

---@internal
---@param map table  one nvim_get_keymap entry
---@return string raw
local function raw_lhs(map)
  if type(map.lhsraw) == "string" then
    return map.lhsraw
  end
  return raw_of(map.lhs)
end

---Every mapping of `mode` (default `cfg.mode`) whose lhs starts with
---`prefix`, buffer-local ones first and shadowing global ones.
---@param prefix string
---@param opts Ui.Keys.Opts|nil
---@return Ui.Keys.Mapping[]
function M.mappings(prefix, opts)
  opts = opts or {}
  local mode = opts.mode or cfg.mode
  local praw = raw_of(prefix)
  local seen = {}
  local out = {}

  local function take(maps, is_buffer)
    for _, map in ipairs(maps) do
      local raw = raw_lhs(map)
      if raw:sub(1, #praw) == praw and #raw > #praw and not seen[raw] then
        local desc = map.desc
        if desc ~= "which_key_ignore" then
          seen[raw] = true
          local rest = vim.fn.keytrans(raw:sub(#praw + 1))
          out[#out + 1] = {
            lhs = vim.fn.keytrans(raw),
            raw = raw,
            rest = rest,
            tokens = tokens_of(rest),
            desc = (desc ~= nil and desc ~= "") and desc or nil,
            rhs = type(map.rhs) == "string" and map.rhs or nil,
            buffer = is_buffer,
          }
        end
      end
    end
  end
  take(api.nvim_buf_get_keymap(0, mode), true)
  take(api.nvim_get_keymap(mode), false)
  table.sort(out, function(a, b)
    return a.rest < b.rest
  end)
  return out
end

---@internal
---The label of a group node under `prefix`.
---@param prefix string
---@param token string
---@param count integer
---@return string
local function group_label(prefix, token, count)
  local key = prefix .. token
  local named = cfg.groups[key]
  if named then
    return named
  end
  return ("%d mappings"):format(count)
end

---The mappings under `prefix` as one level of nodes: a leaf per single
---mapping, a group per next key that has more below it.
---@param prefix string
---@param opts Ui.Keys.Opts|nil
---@return Ui.Keys.Node[]
function M.tree(prefix, opts)
  local maps = M.mappings(prefix, opts)
  local by_token, order = {}, {}
  for _, m in ipairs(maps) do
    local t = m.tokens[1]
    if t then
      if not by_token[t] then
        by_token[t] = {}
        order[#order + 1] = t
      end
      table.insert(by_token[t], m)
    end
  end
  local nodes = {}
  for _, t in ipairs(order) do
    local group = by_token[t]
    local leaf = nil
    for _, m in ipairs(group) do
      if #m.tokens == 1 then
        leaf = m
      end
    end
    if #group == 1 and leaf then
      nodes[#nodes + 1] = { token = t, mapping = leaf, label = leaf.desc or leaf.rhs or leaf.lhs }
    else
      local children = M.tree(prefix .. t, opts)
      if leaf then
        table.insert(
          children,
          1,
          { token = "", mapping = leaf, label = leaf.desc or leaf.rhs or leaf.lhs }
        )
      end
      nodes[#nodes + 1] = { token = t, children = children, label = group_label(prefix, t, #group) }
    end
  end
  return nodes
end

---@internal
---@param m Ui.Keys.Mapping
---@return fun()
local function runner(m)
  return function()
    -- "m": remap, so a mapping that expands to another mapping still works;
    -- "t": as if typed, so counts and modes behave.
    api.nvim_feedkeys(m.raw, "mt", false)
  end
end

---@internal
---@param nodes Ui.Keys.Node[]
---@return Ui.Kit.MenuItem[]
local function items_of(nodes)
  local items = {}
  for _, n in ipairs(nodes) do
    if n.children then
      items[#items + 1] =
        { label = n.label, rtxt = n.token .. " ▸", items = items_of(n.children) }
    elseif n.mapping then
      items[#items + 1] =
        { label = n.label, rtxt = n.token ~= "" and n.token or "↵", action = runner(n.mapping) }
    end
  end
  return items
end

---Open the menu for `prefix` (default `cfg.default_prefix`). Returns the
---menu surface, or nil when nothing is mapped under the prefix.
---@param prefix string|nil
---@param opts Ui.Keys.Opts|nil
---@return Ui.Kit.Surface|nil
function M.open(prefix, opts)
  prefix = (prefix and prefix ~= "") and prefix or cfg.default_prefix
  opts = opts or {}
  local nodes = M.tree(prefix, opts)
  if #nodes == 0 then
    return nil
  end
  local ok, menu = pcall(require, "ui.kit.menu")
  if not ok then
    return nil
  end
  local shown = vim.fn.keytrans(raw_of(prefix))
  return menu.open({
    items = items_of(nodes),
    title = opts.title or (" " .. (cfg.groups[prefix] or shown) .. " "),
    relative = "cursor",
  })
end

---Override the shipped tunables. `groups` is merged.
---@param opts Ui.Keys.Opts|nil
function M.setup(opts)
  opts = opts or {}
  if type(opts.mode) == "string" then
    cfg.mode = opts.mode
  end
  if type(opts.groups) == "table" then
    for k, v in pairs(opts.groups) do
      cfg.groups[k] = v
    end
  end
  if type(opts.default_prefix) == "string" then
    cfg.default_prefix = opts.default_prefix
  end
end

---@return Ui.Keys.Config
function M.config()
  return cfg
end

return M
