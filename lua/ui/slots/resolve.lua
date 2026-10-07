---@module 'ui.slots.resolve'
--- Placeholder substitution for slot payloads (`{file}`, `{dir}`, `{root}`,
--- `{cwd}`, `{line}`, `{col}`, `{word}`, `{sel}`, `{clip}`, `{count}`).
---
--- `{{` and `}}` stand for a literal `{` and `}` (a file called `report {line}.md`
--- is written `report {{line}}.md`).
---
--- Plain text replacement and nothing else: a placeholder is a name between
--- braces, never code, so there is no `loadstring`/`vim.fn.eval` here. A name
--- this module does not know stays in the text unchanged and is reported in
--- the second return value, so a caller (or `:checkhealth`) can say so.
---
--- A substituted value is not escaped by default. A caller that hands the
--- result to something with its own syntax (an Ex command line) passes
--- `opts.escape`, which is applied to every substituted value.

require("ui.slots.@types")

local M = {}

--- The placeholder names, in the order the docs list them.
M.NAMES = { "file", "dir", "root", "cwd", "line", "col", "word", "sel", "clip", "count" }

local KNOWN = {}
for _, name in ipairs(M.NAMES) do
  KNOWN[name] = true
end

---@param v any
---@return any
local function eval(v)
  if type(v) == "function" then
    local ok, res = pcall(v)
    if ok then
      return res
    end
    return nil
  end
  return v
end

--- The text of the last visual selection, or "" when there is none.
---@return string
local function selection()
  local ok, lines = pcall(function()
    local s = vim.fn.getpos("'<")
    local e = vim.fn.getpos("'>")
    if s[2] == 0 or e[2] == 0 then
      return {}
    end
    return vim.fn.getregion(
      s,
      e,
      { type = vim.fn.visualmode() ~= "" and vim.fn.visualmode() or "v" }
    )
  end)
  if not ok or type(lines) ~= "table" then
    return ""
  end
  return table.concat(lines, "\n")
end

--- The context of the editor right now. Every value is a function, so nothing
--- is read (the clipboard in particular) unless the text uses it.
---@param count integer|nil
---@return Ui.Slots.Ctx
function M.context(count)
  local function bufname()
    local name = vim.api.nvim_buf_get_name(0)
    return name ~= "" and vim.fs.normalize(name) or ""
  end
  return {
    file = bufname,
    dir = function()
      local name = bufname()
      return name ~= "" and vim.fs.dirname(name) or ""
    end,
    root = function()
      return require("lib.nvim.fs.project_key")()
    end,
    cwd = function()
      return vim.fs.normalize((vim.uv or vim.loop).cwd() or vim.fn.getcwd())
    end,
    line = function()
      return vim.api.nvim_win_get_cursor(0)[1]
    end,
    col = function()
      return vim.api.nvim_win_get_cursor(0)[2] + 1
    end,
    word = function()
      return vim.fn.expand("<cword>")
    end,
    sel = selection,
    clip = function()
      return vim.fn.getreg("+")
    end,
    count = function()
      return count or vim.v.count
    end,
  }
end

--- Walk `text` once, left to right, and call `emit("text", chars)` for literal
--- text (a `{{` or `}}` is one literal brace) and `emit("name", word)` for
--- every `{word}`. One pass, so `{{{file}}}` is `{`, the file, `}` -- doing
--- the braces first and the names after would cut it in the wrong place.
---@param text string
---@param emit fun(kind: "text"|"name", value: string)
local function scan(text, emit)
  local i, n = 1, #text
  while i <= n do
    local two = text:sub(i, i + 1)
    if two == "{{" then
      emit("text", "{")
      i = i + 2
    elseif two == "}}" then
      emit("text", "}")
      i = i + 2
    else
      local name, after = text:match("^{(%w+)}()", i)
      if name then
        emit("name", name)
        i = after
      else
        emit("text", text:sub(i, i))
        i = i + 1
      end
    end
  end
end

--- Substitute the placeholders of `text`.
---@param text string|nil
---@param ctx Ui.Slots.Ctx|nil     # defaults to `M.context()`
---@param opts Ui.Slots.ResolveOpts|nil
---@return string resolved
---@return string[] unknown        # names that stayed in the text, each once
function M.resolve(text, ctx, opts)
  if type(text) ~= "string" then
    return "", {}
  end
  ctx = ctx or M.context()
  local escape = opts and opts.escape
  local unknown, seen = {}, {}
  local out = {}

  scan(text, function(kind, value)
    if kind == "text" then
      out[#out + 1] = value
    elseif not KNOWN[value] then
      -- Not ours: stays in the text exactly as written.
      out[#out + 1] = "{" .. value .. "}"
      if not seen[value] then
        seen[value] = true
        unknown[#unknown + 1] = value
      end
    else
      local v = eval(ctx[value])
      v = v == nil and "" or tostring(v)
      if escape then
        local ok, escaped = pcall(escape, v, value)
        if ok and type(escaped) == "string" then
          v = escaped
        end
      end
      out[#out + 1] = v
    end
  end)

  return table.concat(out), unknown
end

--- The unknown placeholder names of `text`, without resolving anything (for
--- validation and the health check).
---@param text string|nil
---@return string[]
function M.unknown(text)
  local names, seen = {}, {}
  if type(text) ~= "string" then
    return names
  end
  scan(text, function(kind, value)
    if kind == "name" and not KNOWN[value] and not seen[value] then
      seen[value] = true
      names[#names + 1] = value
    end
  end)
  return names
end

return M
