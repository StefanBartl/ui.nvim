---@module 'ui.slots.view.preview'
--- The preview pane of the slot panel: a float beside the panel that shows what
--- the slot under the cursor stands for. It does not know what a slot is; the
--- slot's kind answers (`kind.preview(slot, ctx)`) with one of three shapes:
---
---   * `{ lines, ft?, pos? }` -- text, a filetype for highlighting, a cursor `{ line, col }`;
---   * `{ buf, pos? }`        -- a buffer that is ready;
---   * `{ draw = fun(surface) }` -- the kind draws itself (an image, a diff).
---
--- A kind without a preview gets a one-line note. A kind whose `preview` raises,
--- or answers with something else, gets a note too: the pane is never left with
--- the text of the slot before, which `<CR>` could then be mistaken to act on
--- (nothing acts on the pane, it is not focusable -- but it must not lie).
---
--- The pane is not focusable, read-only, and closes with the panel.

require("ui.slots.@types")

local registry = require("ui.slots.kinds.registry")

local api = vim.api

local M = {}

local NS = api.nvim_create_namespace("ui_slots_preview")

---@class Ui.Slots.Preview.State
---@field surf Ui.Kit.Surface|nil
---@field n integer|nil      # the slot shown
local S = { surf = nil, n = nil }

---@return boolean
function M.is_open()
  return S.surf ~= nil and S.surf:is_valid()
end

--- The shape a slot's kind answers with, or a note.
---@param slot table
---@return table
function M.render(slot)
  local kind = registry.get(slot.kind)
  if not kind then
    return { lines = { ("unknown kind '%s'"):format(tostring(slot.kind)) } }
  end
  if not kind.preview then
    return { lines = { ("(no preview for a '%s' slot)"):format(slot.kind) } }
  end
  local ok, res = pcall(registry.preview, slot, {})
  if not ok or type(res) ~= "table" then
    return { lines = { "(the preview could not be made)" } }
  end
  if type(res.lines) ~= "table" and type(res.buf) ~= "number" and type(res.draw) ~= "function" then
    return { lines = { "(the preview could not be made)" } }
  end
  return res
end

--- Lines the buffer accepts: strings, no newline inside.
---@param lines any
---@return string[]
local function clean(lines)
  local out = {}
  for i, l in ipairs(lines) do
    out[i] = (
      tostring(l):gsub("[\r\n%z]", function(c)
        return c == "\0" and "^@" or " "
      end)
    )
  end
  return out
end

--- Put a rendered preview into the pane.
---@param res table
local function fill(res)
  local surf = S.surf
  if not surf then
    return
  end
  api.nvim_buf_clear_namespace(surf.bufnr, NS, 0, -1)
  if res.draw then
    local ok = pcall(res.draw, surf)
    if not ok then
      surf:set_lines({ "(the preview could not be drawn)" })
    end
    return
  end
  local lines
  if res.buf then
    lines = api.nvim_buf_is_valid(res.buf) and api.nvim_buf_get_lines(res.buf, 0, -1, false)
      or { "(the buffer is gone)" }
    res = { lines = lines, ft = res.buf and vim.bo[res.buf].filetype or nil, pos = res.pos }
  end
  local ok = pcall(function()
    surf:set_lines(clean(res.lines))
  end)
  if not ok then
    pcall(function()
      surf:set_lines({ "(the preview could not be shown)" })
    end)
    return
  end
  vim.bo[surf.bufnr].filetype = type(res.ft) == "string" and res.ft or ""
  if res.pos and res.pos[1] then
    local line = math.max(1, math.min(res.pos[1], api.nvim_buf_line_count(surf.bufnr)))
    pcall(api.nvim_win_set_cursor, surf.winid, { line, math.max(0, (res.pos[2] or 1) - 1) })
    pcall(api.nvim_win_call, surf.winid, function()
      vim.cmd("normal! zz")
    end)
  else
    pcall(api.nvim_win_set_cursor, surf.winid, { 1, 0 })
  end
end

--- Close the pane.
function M.close()
  local surf = S.surf
  S.surf, S.n = nil, nil
  if surf then
    surf:close()
  end
end

--- Show the preview of slot `n` beside the panel. `geom` is the panel's
--- rectangle (`row`, `col`, `width`, `height`, `side`); the pane takes the room
--- next to it, and does not open where there is none.
---@param n integer
---@param geom { row: integer, col: integer, width: integer, height: integer, side: string }
---@return boolean shown
function M.show(n, geom)
  local slot = require("ui.slots.store").get(n)
  if not slot then
    M.close()
    return false
  end
  local res = M.render(slot)

  if not M.is_open() then
    local room = geom.side == "left" and (vim.o.columns - geom.col - geom.width - 3)
      or (geom.col - 1)
    local width = math.min(80, room - 1)
    if width < 20 then
      return false
    end
    local col = geom.side == "left" and (geom.col + geom.width + 2) or (geom.col - width - 2)
    local surf = require("ui.kit.surface").open({
      lines = { "" },
      title = " preview ",
      relative = "editor",
      row = geom.row,
      col = math.max(0, col),
      width = width,
      height = geom.height,
      enter = false,
      focusable = false,
      modifiable = false,
      wo = { wrap = false, cursorline = false, number = true },
    })
    if not surf then
      return false
    end
    S.surf = surf
    surf:on_close(function()
      if S.surf == surf then
        S.surf, S.n = nil, nil
      end
    end)
  end
  S.n = n
  fill(res)
  return true
end

---@return integer|nil
function M.shown()
  return M.is_open() and S.n or nil
end

--- The lines in the pane, for specs.
---@return string[]
function M.lines()
  if not M.is_open() then
    return {}
  end
  return api.nvim_buf_get_lines(S.surf.bufnr, 0, -1, false)
end

---@return integer|nil
function M.cursor_line()
  if not M.is_open() then
    return nil
  end
  return api.nvim_win_get_cursor(S.surf.winid)[1]
end

---@return integer|nil
function M.winid()
  return M.is_open() and S.surf.winid or nil
end

function M.reset()
  M.close()
end

return M
