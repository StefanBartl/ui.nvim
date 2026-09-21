---@module 'ui.statusline.layout'
--- Where each rendered module sits on the statusline row, for the one thing
--- a click handler cannot answer: "which key is under this screen column?" --
--- needed for hover (there is no native hover region, only click regions)
--- and for a right/double click that lands on a module `ui.statusline.render`
--- never wrapped in its own click protocol. `ui.tabline.layout` solves the
--- same problem for buffer chips; this is its statusline sibling, bucketed
--- by window instead of a single tabline-wide record because a per-window
--- statusline (`laststatus` 0/1/2) renders once per window, not once total.
---
--- `nvim_eval_statusline` is the load-bearing call throughout: it is what
--- Neovim itself uses to turn `%=` into padding, so asking it to evaluate the
--- real rendered text (or a same-shaped probe built from it) reproduces
--- Neovim's own column math exactly -- including multiple `%=` sections
--- splitting the slack between them, which no hand-rolled formula here would
--- get pixel-right on the first try.

local api = vim.api

local M = {}

---@class Ui.Statusline.LayoutEntry
---@field order string[]     # keys in render order, "%=" entries kept as-is
---@field rendered table<string, string> # key -> the exact string M.generate() emitted for it

--- One recorded layout per statusline-owning window -- `vim.g.statusline_winid`
--- at record time, which is also what a global (`laststatus=3`) statusline's
--- own single evaluation sets to the currently focused window. Keyed rather
--- than a single slot (unlike `ui.tabline.layout`, which has only one
--- tabline) because `laststatus` 0/1/2 renders a distinct statusline per
--- window, each with its own column layout.
---@type table<integer, Ui.Statusline.LayoutEntry>
local last = {}

--- Remember what `ui.statusline.render.generate()` just emitted for `winid`.
---@param winid integer
---@param order string[]
---@param rendered table<string, string>
---@return nil
function M.record(winid, order, rendered)
  last[winid] = { order = order, rendered = rendered }
end

--- The layout `record()` last stored for `winid`, or nil.
---@param winid integer
---@return Ui.Statusline.LayoutEntry|nil
function M.current(winid)
  return last[winid]
end

-- Two throwaway highlight groups per key (its start and end marker), reused
-- across calls -- attributes are irrelevant (the probe string built in
-- `key_at` is never displayed, only evaluated), only the presence of a group
-- *switch* at each boundary matters. Grown lazily to the longest `order`
-- seen so far. Confirmed empirically (a real headless Neovim) that this
-- registration step is load-bearing, not defensive dead weight: an
-- undefined group's NAME does not survive into `nvim_eval_statusline`'s own
-- `highlights` output at all (it reports the resolved fallback group
-- instead), so `key_at` could not tell one marker from another without it.
---@type integer
local marker_groups_defined = 0

---@param n integer
---@return nil
local function ensure_marker_groups(n)
  for i = marker_groups_defined + 1, n do
    api.nvim_set_hl(0, "UiSlB" .. i .. "a", {})
    api.nvim_set_hl(0, "UiSlB" .. i .. "b", {})
  end
  if n > marker_groups_defined then
    marker_groups_defined = n
  end
end

--- The key at 1-based column `col` of `winid`'s last recorded layout, or nil
--- when nothing has been recorded yet, `col` falls in the empty space a `%=`
--- expanded into, or `col` is past the end of the row.
---
--- Builds a probe string -- every key's own recorded text, bracketed by a
--- start and an end marker unique to that key -- and evaluates it ONCE via
--- `nvim_eval_statusline` with `winid`'s real width (so `%=` expands exactly
--- as it did on screen). The returned `highlights` list carries a `start`
--- byte offset for every group switch, including zero-width ones
--- immediately overridden by a key's own `%#Group#` (confirmed empirically),
--- which is what lets a key with no highlight of its own still be located
--- precisely -- and, bracketed on both sides this way, lets ONE eval call
--- answer "which key, and does it actually reach this column" for the whole
--- row at once. An earlier version paired each key's start marker with the
--- NEXT key's start marker to find its end, which silently swallowed a `%=`
--- gap into the key on its near side (caught by this module's own tests);
--- a second version fixed that by re-evaluating each candidate key's own
--- text in a separate `nvim_eval_statusline` call, which is correct but
--- costs one extra call per key at or before the hovered column -- up to one
--- per module in `order` on every single `<MouseMove>` tick. Two markers per
--- key removes that cost entirely: the one probe eval already carries both
--- boundaries.
---@param winid integer
---@param col integer # 1-based, `wincol` for a per-window statusline or `screencol` for a global one
---@param maxwidth integer|nil # the row's real width; defaults to `winid`'s own width, but a global (`laststatus=3`) statusline spans the full editor and the caller must pass `vim.o.columns` explicitly -- `winid` there is only the window the layout happened to be recorded against, not the row's actual width
---@return string|nil key
function M.key_at(winid, col, maxwidth)
  local entry = last[winid]
  if not entry or #entry.order == 0 or col < 1 then
    return nil
  end

  local real_keys = {}
  for _, key in ipairs(entry.order) do
    if key ~= "%=" then
      real_keys[#real_keys + 1] = key
    end
  end
  if #real_keys == 0 then
    return nil
  end
  ensure_marker_groups(#real_keys)

  local probe = {}
  ---@type table<string, string>
  local start_marker_of, end_marker_of = {}, {}
  local n = 0
  for _, key in ipairs(entry.order) do
    if key == "%=" then
      probe[#probe + 1] = "%="
    else
      n = n + 1
      local a, b = "UiSlB" .. n .. "a", "UiSlB" .. n .. "b"
      start_marker_of[a] = key
      end_marker_of[b] = key
      probe[#probe + 1] = "%#" .. a .. "#" .. (entry.rendered[key] or "") .. "%#" .. b .. "#"
    end
  end

  if not maxwidth then
    local width_ok, width = pcall(api.nvim_win_get_width, winid)
    maxwidth = width_ok and width or vim.o.columns
  end

  local ok, res = pcall(
    api.nvim_eval_statusline,
    table.concat(probe),
    { winid = winid, maxwidth = maxwidth, highlights = true }
  )
  if not ok or type(res) ~= "table" then
    return nil
  end

  -- Column -> byte offset in `res.str`: `strdisplaywidth` on the prefix up to
  -- each marker's `start`, since `col` (wincol/screencol) is a screen-cell
  -- position but `highlights[].start` is a byte offset -- they only agree
  -- when everything on the row is single-byte/single-cell, never true once
  -- an icon is involved. `start_col[key]` is 1-based (matching `col`);
  -- `end_col[key]` is the last column the key's own text still occupies
  -- (the display width consumed up to and including it, which is already
  -- the right number with no further +1/-1 -- confirmed empirically).
  ---@type table<string, integer>
  local start_col, end_col = {}, {}
  for _, h in ipairs(res.highlights) do
    local prefix_width = vim.fn.strdisplaywidth(res.str:sub(1, h.start))
    local start_key = start_marker_of[h.group]
    if start_key and not start_col[start_key] then
      start_col[start_key] = prefix_width + 1
    end
    local end_key = end_marker_of[h.group]
    if end_key and not end_col[end_key] then
      end_col[end_key] = prefix_width
    end
  end

  for _, key in ipairs(real_keys) do
    local s, e = start_col[key], end_col[key]
    if s and e and col >= s and col <= e then
      return key
    end
  end

  return nil
end

return M
