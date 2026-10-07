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
---@field gen integer         # moves with every fill: an answer of an older one is dropped
---@field later { cancel: fun() }|nil  # the request behind the text shown now
---@field sig string|nil       # what the pane shows, to skip a show of the same thing
local S = { surf = nil, n = nil, gen = 0, later = nil, sig = nil }

---@return boolean
function M.is_open()
  return S.surf ~= nil and S.surf:is_valid()
end

--- The shape a slot's kind answers with, or a note.
---@param slot table
---@param ctx { resolve?: Ui.Slots.Ctx }|nil  # where the placeholders are read (the editor, not the panel)
---@return table
function M.render(slot, ctx)
  local kind = registry.get(slot.kind)
  if not kind then
    return { lines = { ("unknown kind '%s'"):format(tostring(slot.kind)) } }
  end
  if not kind.preview then
    return { lines = { ("(no preview for a '%s' slot)"):format(slot.kind) } }
  end
  local ok, res = pcall(registry.preview, slot, ctx)
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

--- Stop waiting for the answer of the slot shown before.
local function forget_later()
  S.gen = S.gen + 1
  local later = S.later
  S.later = nil
  if later and type(later.cancel) == "function" then
    pcall(later.cancel)
  end
end

local fill

--- Start the request behind a preview that answers later. What it delivers
--- replaces the text only if the pane still shows the same slot at the same
--- fill: moving on, closing, or a newer fill make it a no-op.
---@param later fun(deliver: fun(res: table)): { cancel: fun() }|nil
local function wait_for(later)
  local gen = S.gen
  local surf = S.surf
  local ok, handle = pcall(later, function(res)
    vim.schedule(function()
      if gen ~= S.gen or S.surf ~= surf or not M.is_open() then
        return
      end
      if type(res) ~= "table" then
        res = { lines = { "(the preview could not be made)" } }
      end
      fill(vim.tbl_extend("force", res, { later = false }))
    end)
  end)
  if not ok then
    fill({ lines = { "(the preview could not be made)" }, later = false })
    return
  end
  if gen == S.gen then
    S.later = handle
  elseif handle and type(handle.cancel) == "function" then
    pcall(handle.cancel)
  end
end

--- Put a rendered preview into the pane.
---@param res table
function fill(res)
  local surf = S.surf
  if not surf then
    return
  end
  forget_later()
  api.nvim_buf_clear_namespace(surf.bufnr, NS, 0, -1)
  if res.draw then
    -- A clean pane first: a draw that does not touch every line must not show
    -- the lines (and the filetype) of the slot before.
    pcall(function()
      surf:set_lines({ "" })
    end)
    if vim.bo[surf.bufnr].filetype ~= "" then
      vim.bo[surf.bufnr].filetype = ""
    end
    pcall(api.nvim_win_set_cursor, surf.winid, { 1, 0 })
    local ok = pcall(res.draw, surf)
    if not ok then
      surf:set_lines({ "(the preview could not be drawn)" })
    end
    return
  end
  local lines
  if res.buf then
    local valid = api.nvim_buf_is_valid(res.buf)
    lines = valid and api.nvim_buf_get_lines(res.buf, 0, -1, false) or { "(the buffer is gone)" }
    res = { lines = lines, ft = valid and vim.bo[res.buf].filetype or nil, pos = res.pos }
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
  -- Only when it changes: setting a filetype fires FileType (ftplugins, treesitter,
  -- the user's own handlers) every time, equal or not.
  local ft = type(res.ft) == "string" and res.ft or ""
  if vim.bo[surf.bufnr].filetype ~= ft then
    vim.bo[surf.bufnr].filetype = ft
  end
  if type(res.pos) == "table" and type(res.pos[1]) == "number" then
    local line = math.max(1, math.min(res.pos[1], api.nvim_buf_line_count(surf.bufnr)))
    local col = type(res.pos[2]) == "number" and res.pos[2] or 1
    pcall(api.nvim_win_set_cursor, surf.winid, { line, math.max(0, col - 1) })
    pcall(api.nvim_win_call, surf.winid, function()
      vim.cmd("normal! zz")
    end)
  else
    pcall(api.nvim_win_set_cursor, surf.winid, { 1, 0 })
  end
  if type(res.later) == "function" then
    wait_for(res.later)
  end
end

--- Close the pane.
function M.close()
  local surf = S.surf
  forget_later()
  S.surf, S.n, S.sig = nil, nil, nil
  if surf then
    surf:close()
  end
end

--- Show the preview of slot `n` beside the panel. `geom` is the panel's
--- rectangle (`row`, `col`, `width`, `height`, `side`); the pane takes the room
--- next to it, and does not open where there is none.
---@param n integer
---@param geom { row: integer, col: integer, width: integer, height: integer, side: string }
---@param ctx { resolve?: Ui.Slots.Ctx }|nil  # the placeholders as the editor window sees them
---@return boolean shown
function M.show(n, geom, ctx)
  local slot = require("ui.slots.store").get(n)
  if not slot then
    M.close()
    return false
  end
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
      -- Every move replaces the whole text; with undo on, the old texts pile up
      -- (up to `max_kb` each) for as long as the pane stays open.
      bo = { undolevels = -1 },
      wo = { wrap = false, cursorline = false, number = true },
    })
    if not surf then
      return false
    end
    S.surf = surf
    surf:on_close(function()
      if S.surf == surf then
        forget_later()
        S.surf, S.n, S.sig = nil, nil, nil
      end
    end)
  end
  -- The same slot, unchanged, is already shown (or its page is on its way): a
  -- redraw of the panel must not cancel that request and start it again.
  local sig = vim.inspect(slot)
  if S.n == n and S.sig == sig then
    return true
  end
  S.n, S.sig = n, sig
  local ok = pcall(function()
    fill(M.render(slot, ctx))
  end)
  if not ok then
    -- Never leave the text of the slot before under the cursor of this one.
    forget_later()
    pcall(function()
      S.surf:set_lines({ "(the preview could not be shown)" })
    end)
  end
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
