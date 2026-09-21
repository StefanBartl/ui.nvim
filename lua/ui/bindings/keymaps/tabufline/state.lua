---@module 'ui.bindings.keymaps.tabufline.state'
--- Maintains `vim.t.bufs` -- the per-tab listed-buffer list `init.lua`'s
--- `next()`/`prev()` already read -- and provides `close_buffer()`/
--- `move_buf()`, the two operations this module used to reach into
--- `nvchad.tabufline` for.
---
--- Ported from NvChad's own `nvchad/tabufline/lazyload.lua` and
--- `nvchad/tabufline/init.lua`. The bookkeeping matters more than the two
--- functions: `vim.t.bufs` was never populated by any of the three
--- `require("nvchad.tabufline")` call sites this repo's own code has --
--- it was NvChad's own `nvchad/init.lua` calling `require
--- "nvchad.tabufline.lazyload"` (never required by name from here) that set
--- up the `BufAdd`/`BufEnter`/`tabnew`/`BufDelete` autocmds building it. The
--- roadmap's "5 symbols, 32 call sites" measurement, being a `require()`
--- count over this repo's own code, could not see that -- the same shape as
--- the statusline render-entrypoint gap step 4 found: the real dependency
--- was not a symbol this repo's own code required, it was setup that ran
--- from NvChad's own init before this repo's code ever got a chance to see
--- `vim.t.bufs` empty. Without `M.setup()` below, `next()`/`prev()` were
--- already NvChad-independent code that silently did nothing (`vim.t.bufs`
--- is `nil`, so both return `false` on their first line) whenever NvChad's
--- own autocmds were not the ones populating it.
---
--- What is intentionally NOT here: `vim.o.tabline` / a rendered tabline.
--- That is `nvchad.tabufline.modules` in the original, and it is separate,
--- larger scope -- see "Planned scope, by area > Tabline" in the project roadmap.
--- This module only keeps the LIST correct; nothing here draws one.

local api = vim.api

local M = {}

---@internal
---1-based index of `bufnr` within `bufs` (default `vim.t.bufs`), or nil.
---@param bufnr integer
---@param bufs? integer[]
---@return integer|nil
local function buf_index(bufnr, bufs)
  bufs = bufs or vim.t.bufs
  if not bufs then
    return nil
  end
  for i, b in ipairs(bufs) do
    if b == bufnr then
      return i
    end
  end
  return nil
end

--- Count of pinned buffers among `bufs` (default the current tab's
--- `vim.t.bufs`) -- the size of the "pins first" block `move_buf_to`/
--- `move_buf` clamp their target into, and the boundary slot `set_pinned`
--- re-places a buffer to.
---@param bufs? integer[]
---@return integer
local function pinned_count(bufs)
  bufs = bufs or vim.t.bufs or {}
  local pinned = vim.t.ui_pinned or {}
  local n = 0
  for _, b in ipairs(bufs) do
    if vim.tbl_contains(pinned, b) then
      n = n + 1
    end
  end
  return n
end

--- Whether `bufnr` is pinned in the current tab. Pin state is tab-local
--- (`vim.t.ui_pinned`, a plain LIST of bufnrs -- not a `{[bufnr]=true}` set:
--- `vim.t`/`vim.g`/`vim.b` round-trip a Lua table through a VimL value, and
--- a table keyed by arbitrary integers like a bufnr comes back as a List
--- padded with `vim.NIL` up to the highest key, not a sparse Dict -- found
--- live, `vim.NIL` is truthy in Lua, so a plain `pinned[bufnr]` truthy check
--- read every LOWER bufnr as pinned too. A list plus `vim.tbl_contains` has
--- no such hazard) and not persisted across a restart -- `ui.tabline.menu`'s
--- "Pin"/"Unpin" entry and a pinned chip's own pin-glyph click are the only
--- ways to change it.
---@param bufnr integer
---@return boolean
function M.is_pinned(bufnr)
  return vim.tbl_contains(vim.t.ui_pinned or {}, bufnr)
end

--- The current tab's pinned bufnrs, one `vim.t.ui_pinned` read. For a caller
--- that needs to check MANY buffers against the pin set in one pass (the
--- tabline's own per-chip render loop, the tab menu's close-set filters) --
--- `vim.t`/`vim.g`/`vim.b` round-trip through a VimL value on every access,
--- so calling `is_pinned()` once per buffer in a loop re-reads and
--- re-converts the whole tab-local table each time. Read this ONCE outside
--- the loop instead and check membership locally (`vim.tbl_contains(list,
--- b)`, or build a lookup table for a larger n).
---@return integer[]
function M.pinned_bufs()
  return vim.t.ui_pinned or {}
end

--- Pin or unpin `bufnr` in the current tab, then re-place it to keep the
--- invariant `move_buf_to`/`move_buf` (below) both uphold: pinned buffers
--- always sit before unpinned ones in `vim.t.bufs`. Pinning moves `bufnr` to
--- the last pinned slot (the right edge of the pin block); unpinning moves
--- it to the first unpinned slot (the left edge of the rest) -- either way
--- it lands on the boundary between the two regions, not at an arbitrary
--- spot inside one of them.
---@param bufnr integer
---@param pinned boolean
---@return boolean changed # false when bufnr is unlisted or already in that state
function M.set_pinned(bufnr, pinned)
  local bufs = vim.t.bufs
  if not bufs or not buf_index(bufnr, bufs) then
    return false
  end
  if M.is_pinned(bufnr) == pinned then
    return false
  end

  local set = vim.t.ui_pinned or {}
  if pinned then
    set[#set + 1] = bufnr
  else
    for i, b in ipairs(set) do
      if b == bufnr then
        table.remove(set, i)
        break
      end
    end
  end
  vim.t.ui_pinned = set

  M.move_buf_to(bufnr, pinned and pinned_count(bufs) or (pinned_count(bufs) + 1))
  return true
end

--- Flip `bufnr`'s pin state. See `set_pinned`.
---@param bufnr integer
---@return boolean changed
function M.toggle_pinned(bufnr)
  return M.set_pinned(bufnr, not M.is_pinned(bufnr))
end

-- Guards `M.setup()` against registering its autocmds twice -- called from
-- both `attach_buffers()` and `attach_tabs()` in `keymaps/init.lua`, and
-- either could run first.
local registered = false

--- Start (idempotently) maintaining `vim.t.bufs`: seed it from the buffers
--- already listed when this runs, then keep it current as buffers are
--- added, entered, or deleted, and each new tab gets its own list. Safe to
--- call more than once.
---@return nil
function M.setup()
  if registered then
    return
  end
  registered = true

  vim.t.bufs = vim.t.bufs
    or vim.tbl_filter(function(buf)
      return vim.fn.buflisted(buf) == 1
    end, api.nvim_list_bufs())

  local autocmd = require("lib.nvim.bindings.autocmd")
  local group = autocmd.group("ui_tabufline_state", true)

  autocmd.create({ "BufAdd", "BufEnter", "tabnew" }, function(args)
    local bufs = vim.t.bufs
    local is_curbuf = api.nvim_get_current_buf() == args.buf

    if bufs == nil then
      bufs = is_curbuf and {} or { args.buf }
    elseif
      not vim.tbl_contains(bufs, args.buf)
      and (args.event == "BufEnter" or not is_curbuf or vim.bo[args.buf].buflisted)
      and api.nvim_buf_is_valid(args.buf)
      and vim.bo[args.buf].buflisted
    then
      table.insert(bufs, args.buf)
    end

    -- An unnamed, unmodified buffer at the front is the placeholder Neovim
    -- opens with -- drop it once a real one has been added, same as the
    -- original.
    if args.event == "BufAdd" and bufs[1] then
      if api.nvim_buf_get_name(bufs[1]) == "" and not vim.bo[bufs[1]].modified then
        table.remove(bufs, 1)
      end
    end

    vim.t.bufs = bufs
  end, {
    group = group,
    desc = "ui.tabufline: keep vim.t.bufs current",
  })

  autocmd.create("BufDelete", function(args)
    -- Before the buffer is dropped from any tab's list below: the ring
    -- needs its name and last cursor mark, which only exist while the
    -- buffer itself still does (see ui.tabline.reopen's own doc comment).
    -- Required lazily -- ui.tabline.reopen requires this module back (to
    -- reopen at a remembered slot), so a top-level require here would be a
    -- load-order cycle.
    pcall(require("ui.tabline.reopen").record, args.buf)

    for _, tab in ipairs(api.nvim_list_tabpages()) do
      local bufs = vim.t[tab].bufs
      if bufs then
        local idx = buf_index(args.buf, bufs)
        if idx then
          table.remove(bufs, idx)
          vim.t[tab].bufs = bufs
        end
      end

      local pinned = vim.t[tab].ui_pinned
      if pinned then
        for i, b in ipairs(pinned) do
          if b == args.buf then
            table.remove(pinned, i)
            vim.t[tab].ui_pinned = pinned
            break
          end
        end
      end
    end
  end, {
    group = group,
    desc = "ui.tabufline: drop a deleted buffer from every tab's vim.t.bufs/pins, record it for reopen",
  })

  -- Quickfix buffers are never file buffers a tabline should list or
  -- next()/prev() should land on. The `BufAdd`/`BufEnter` handler above
  -- would otherwise pick one up the moment it becomes `buflisted`.
  autocmd.create("FileType", function()
    vim.opt_local.buflisted = false
  end, {
    group = group,
    pattern = "qf",
    desc = "ui.tabufline: keep quickfix out of vim.t.bufs",
  })
end

--- If `win` is `winfixbuf`-locked, the nearest window that both lists
--- buffers and is not itself locked -- `win` itself otherwise (including
--- when no such window exists). Shared by `goto_buf` and `close_buffer`:
--- both run a command that changes what the current window shows (`:b`,
--- `:enew`, `nvim_set_current_buf`), and `winfixbuf` would otherwise
--- silently fight (E1513) over what a locked window is allowed to display.
---
--- `close_buffer` needed this too once a fix confirmed the bug was real:
--- clicking a tabline "x" while a `winfixbuf`-locked window (a file tree
--- sidebar, typically) happens to be the current one raised exactly this
--- error and left the buffer open -- `goto_buf` already guarded against the
--- same class of problem, `close_buffer` just never got the same check.
---@param win integer
---@return integer
local function switchable_win(win)
  if not api.nvim_get_option_value("winfixbuf", { win = win }) then
    return win
  end

  for _, w in ipairs(api.nvim_list_wins()) do
    local buflisted = api.nvim_get_option_value("buflisted", { buf = api.nvim_win_get_buf(w) })
    local win_fixedbuf = api.nvim_get_option_value("winfixbuf", { win = w })
    if buflisted and not win_fixedbuf then
      return w
    end
  end

  return win
end

--- Hop the current window to `switchable_win`'s result, if that differs
--- from where it already is.
---@return nil
local function hop_off_fixedbuf()
  local cur = api.nvim_get_current_win()
  local target = switchable_win(cur)
  if target ~= cur then
    api.nvim_set_current_win(target)
  end
end

--- Whether closing `bufnr` would hit the `confirm bd` prompt below --
--- i.e. it reaches that branch at all (not a terminal, not a floating
--- window's buffer) and actually has unsaved changes. Used by
--- `close_all_bufs`/`close_n_buffers` to ask ONCE for the whole batch
--- (UI-01: "confirm once, not once per item") instead of once per buffer.
---@param bufnr integer
---@return boolean
local function needs_close_confirm(bufnr)
  if not api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype == "terminal" then
    return false
  end
  local bufwin = vim.fn.bufwinid(bufnr)
  if bufwin ~= -1 and api.nvim_win_get_config(bufwin).zindex then
    return false
  end
  return vim.bo[bufnr].bufhidden ~= "delete" and vim.bo[bufnr].modified
end
M.__needs_close_confirm = needs_close_confirm

--- Close `bufnr` (default: the current buffer), landing on a sensible
--- neighbour rather than whatever Neovim's own `:bdelete` would fall back
--- to. Ported from `nvchad.tabufline.close_buffer`.
---
---@param bufnr? integer
---@param skip_confirm? boolean Force-close without `confirm bd`'s
---  save-changes prompt -- for a caller that already asked once for the
---  whole batch it is part of (`close_all_bufs`/`close_n_buffers`).
---@return nil
function M.close_buffer(bufnr, skip_confirm)
  bufnr = bufnr or api.nvim_get_current_buf()

  -- Whether `bufnr` is what the current window shows. Only then does closing
  -- it have to pick a new buffer for that window; closing a background
  -- buffer (a tabline "x" or context-menu "Close" on a chip that is not the
  -- current one) must leave the window, and so the user's place, alone --
  -- this used to hop to `bufnr`'s neighbour first regardless, which yanked
  -- the current window off what the user was editing.
  local is_current = api.nvim_get_current_buf() == bufnr

  if vim.bo[bufnr].buftype == "terminal" then
    if is_current then
      hop_off_fixedbuf()
      vim.cmd(vim.bo[bufnr].buflisted and "set nobl | enew" or "hide")
      vim.cmd("redrawtabline")
    else
      -- `set nobl | enew` would replace what the current window shows, and
      -- that is not this terminal. Unlist it and drop its chip instead --
      -- the job keeps running, same as the current-buffer branch above.
      vim.bo[bufnr].buflisted = false
      M.forget_buffer(bufnr, api.nvim_get_current_tabpage())
    end
    return
  end

  local idx = buf_index(bufnr)
  local bufhidden = vim.bo[bufnr].bufhidden

  -- The window actually showing `bufnr`, not window 0 -- an explicit-bufnr
  -- caller (close_all_bufs, close_n_buffers) can run with the current
  -- window pointed at something else entirely (an LSP hover float, the
  -- theme picker, ...), and checking window 0's zindex there would wipe
  -- whatever float happens to be focused instead of `bufnr` itself.
  local bufwin = vim.fn.bufwinid(bufnr)
  if bufwin ~= -1 and api.nvim_win_get_config(bufwin).zindex then
    -- A floating window's buffer: force-close the window itself. Not a
    -- winfixbuf case -- destroying the window outright, not switching what
    -- buffer it shows.
    pcall(api.nvim_win_close, bufwin, true)
    return
  end

  if is_current then
    -- Every branch below runs a command that changes what the current window
    -- shows (`:b`, `nvim_set_current_buf`, `:enew`) -- hop off a
    -- winfixbuf-locked window first, or the whole close aborts on E1513
    -- before `bufnr` itself ever gets touched.
    hop_off_fixedbuf()

    if idx and vim.t.bufs and #vim.t.bufs > 1 then
      local step = (idx == #vim.t.bufs) and -1 or 1
      vim.cmd("b" .. vim.t.bufs[idx + step])
    elseif not vim.bo[bufnr].buflisted then
      local fallback = vim.t.bufs and vim.t.bufs[1]
      if fallback then
        local winid = vim.fn.bufwinid(fallback)
        winid = winid ~= -1 and winid or 0
        api.nvim_set_current_win(winid)
        api.nvim_set_current_buf(fallback)
      end
      vim.cmd("bw" .. bufnr)
      return
    else
      vim.cmd("enew")
    end
  elseif not vim.bo[bufnr].buflisted then
    vim.cmd("bw" .. bufnr)
    return
  end

  if bufhidden ~= "delete" then
    vim.cmd((skip_confirm and "bd! " or "confirm bd") .. bufnr)
  end

  vim.cmd("redrawtabline")
end

--- Switch to `bufnr` directly (as opposed to `next()`/`prev()`'s relative
--- move). Hops off a `winfixbuf`-locked current window first (see
--- `switchable_win`'s own doc comment). Ported from
--- `nvchad.tabufline.goto_buf`.
---@param bufnr integer
---@return nil
function M.goto_buf(bufnr)
  hop_off_fixedbuf()
  api.nvim_set_current_buf(bufnr)
end

--- Close every listed buffer in the current tab via `close_buffer()`
--- (respecting its terminal/floating/fallback handling per buffer), current
--- buffer included unless `include_cur_buf` is explicitly `false`. Ported
--- from `nvchad.tabufline.closeAllBufs`.
---
--- Pinned buffers are excluded unconditionally, `include_cur_buf` or not --
--- the roadmap's own recommendation: "Alle schließen" should not be a
--- backdoor around a pin.
---@param include_cur_buf? boolean # default true
---@return nil
function M.close_all_bufs(include_cur_buf)
  local bufs = vim.tbl_filter(function(b)
    return not M.is_pinned(b)
  end, vim.t.bufs or {})

  if include_cur_buf == false then
    local idx = buf_index(api.nvim_get_current_buf(), bufs)
    if idx then
      table.remove(bufs, idx)
    end
  end

  M.close_bufs(bufs)
end

--- Close every buffer in `bufnrs` (a subset of the tab's list, as the
--- tabline context menu's "close others"/"close to the right" build) through
--- `close_buffer()`, asking ONCE up front when any of them has unsaved
--- changes. `close_all_bufs` above is this over the whole list.
---@param bufnrs integer[]
---@return boolean closed # false when the user declined the discard prompt
function M.close_bufs(bufnrs)
  -- UI-01: confirm once for the whole batch, not once per modified buffer
  -- below -- without this, "close all" with N unsaved buffers popped N
  -- sequential `confirm bd` dialogs for a single `<leader>bq`.
  local modified = 0
  for _, bufnr in ipairs(bufnrs) do
    if needs_close_confirm(bufnr) then
      modified = modified + 1
    end
  end

  if modified > 0 then
    local choice = vim.fn.confirm(
      string.format("Discard changes in %d modified buffer(s)?", modified),
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return false
    end
  end

  -- pcall'd per buffer, no notify here -- this module stays low-level (see
  -- its own doc comment); the deferred caller (ui.tabline.utils) already
  -- notifies on the whole batch failing. Without this, one already-invalid
  -- or otherwise failing bufnr would abort the rest of a "close all" batch,
  -- leaving everything after it in vim.t.bufs open.
  for _, bufnr in ipairs(bufnrs) do
    pcall(M.close_buffer, bufnr, true)
  end
  return true
end

--- Drop `bufnr` from one tab's `vim.t.bufs`, leaving every other tab alone.
---
--- The gap this closes: `lib.nvim.buf_win_tab.move_buffer_to_tab` (bound to
--- the "move current buffer into a new tab" keymap) moves a buffer across
--- tabs without deleting it. `BufEnter` in the destination tab adds it
--- there, but nothing takes it out of the tab it came from -- only
--- `BufDelete` does that, and the buffer is very much still alive. The
--- result was a chip in the source tab's tabline for a buffer no longer in
--- that tab, for the rest of the session.
---
--- `lib.nvim` cannot fix this itself: `vim.t.bufs` is this plugin's
--- bookkeeping and the dependency only points one way, so the repair lives
--- on this side of the boundary, next to the state it repairs.
---
--- A no-op when the tab is gone, when `M.setup()` never ran (no
--- `vim.t.bufs` to speak of), or when the buffer was not listed there.
---@param bufnr integer
---@param tabpage integer # tabpage handle, as `nvim_get_current_tabpage()` returns
---@return nil
function M.forget_buffer(bufnr, tabpage)
  if not api.nvim_tabpage_is_valid(tabpage) then
    return
  end

  local bufs = vim.t[tabpage].bufs
  if not bufs then
    return
  end

  local idx = buf_index(bufnr, bufs)
  if not idx then
    return
  end

  table.remove(bufs, idx)
  vim.t[tabpage].bufs = bufs

  local pinned = vim.t[tabpage].ui_pinned
  if pinned then
    for i, b in ipairs(pinned) do
      if b == bufnr then
        table.remove(pinned, i)
        vim.t[tabpage].ui_pinned = pinned
        break
      end
    end
  end

  vim.cmd("redrawtabline")
end

--- Place `bufnr` at slot `pos` in `vim.t.bufs`, shifting the buffers in
--- between by one -- the absolute counterpart of `move_buf` below, which
--- swaps the CURRENT buffer with a neighbour. This is what a drag on the
--- tabline and the context menu's "move to position" both need: any buffer,
--- any target slot.
---
--- `pos` is clamped into `1..#bufs` rather than rejected: "move to 99" in a
--- five-tab bar reasonably means "to the end".
---@param bufnr integer
---@param pos integer
---@return boolean moved # false when nothing changed (unknown buffer, bad `pos`, already there)
function M.move_buf_to(bufnr, pos)
  local bufs = vim.t.bufs
  if not bufs or type(pos) ~= "number" or pos ~= pos then
    return false
  end

  local idx = buf_index(bufnr, bufs)
  if not idx then
    return false
  end

  pos = math.min(math.max(math.floor(pos), 1), #bufs)

  -- "Pins first" invariant (see M.set_pinned's own doc comment): a pinned
  -- buffer never moves past the last pinned slot, an unpinned one never
  -- moves into the pinned block. Both the tab menu's "Move to position…"
  -- and a tabline drag (ui.tabline.drag, via layout.slot_at) go through
  -- here, so clamping once, in this one place, covers every mover.
  local n = pinned_count(bufs)
  if M.is_pinned(bufnr) then
    pos = math.min(pos, n)
  else
    pos = math.max(pos, n + 1)
  end

  if pos == idx then
    return false
  end

  table.remove(bufs, idx)
  table.insert(bufs, pos, bufnr)
  vim.t.bufs = bufs
  vim.cmd("redrawtabline")
  return true
end

--- 1-based slot of `bufnr` in the current tab's `vim.t.bufs`, or nil.
---@param bufnr integer
---@return integer|nil
function M.index_of(bufnr)
  return buf_index(bufnr)
end

--- Swap the current buffer with the neighbour `n` slots over in
--- `vim.t.bufs` (wrapping at either end), and persist the reordered list.
--- Ported from `nvchad.tabufline.move_buf`.
---@param n integer # positive moves right, negative moves left
---@return nil
function M.move_buf(n)
  local bufs = vim.t.bufs
  if not bufs then
    return
  end
  if type(n) ~= "number" or n == 0 then
    return
  end
  n = math.floor(n)

  local cur = api.nvim_get_current_buf()
  local n_pinned = pinned_count(bufs)
  for i, bufnr in ipairs(bufs) do
    if bufnr == cur then
      -- "Pins first" invariant, same as move_buf_to: a swap partner is
      -- clamped into `bufnr`'s own region ([1, n_pinned] when pinned,
      -- [n_pinned + 1, #bufs] otherwise) instead of the whole list.
      local lo, hi
      if M.is_pinned(cur) then
        lo, hi = 1, n_pinned
      else
        lo, hi = n_pinned + 1, #bufs
      end

      if hi > lo then
        if (n < 0 and i == lo) or (n > 0 and i == hi) then
          bufs[lo], bufs[hi] = bufs[hi], bufs[lo]
        else
          -- Clamp the destination into bounds (PRIN-25): `n` is documented
          -- as "positive moves right, negative moves left" with no range
          -- limit, but an unclamped `i + n` past either end reads bufs[i +
          -- n] as nil and writes one, corrupting the sequence vim.t.bufs
          -- persists.
          local dest = math.min(math.max(i + n, lo), hi)
          bufs[i], bufs[dest] = bufs[dest], bufs[i]
        end
      end
      break
    end
  end

  vim.t.bufs = bufs
  vim.cmd("redrawtabline")
end

return M
