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
--- larger scope -- see docs/ROADMAP.md, "Planned scope, by area > Tabline".
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
    for _, tab in ipairs(api.nvim_list_tabpages()) do
      local bufs = vim.t[tab].bufs
      if bufs then
        local idx = buf_index(args.buf, bufs)
        if idx then
          table.remove(bufs, idx)
          vim.t[tab].bufs = bufs
        end
      end
    end
  end, {
    group = group,
    desc = "ui.tabufline: drop a deleted buffer from every tab's vim.t.bufs",
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

--- Close `bufnr` (default: the current buffer), landing on a sensible
--- neighbour rather than whatever Neovim's own `:bdelete` would fall back
--- to. Ported from `nvchad.tabufline.close_buffer`.
---@param bufnr? integer
---@return nil
function M.close_buffer(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if vim.bo[bufnr].buftype == "terminal" then
    vim.cmd(vim.bo.buflisted and "set nobl | enew" or "hide")
    vim.cmd("redrawtabline")
    return
  end

  local idx = buf_index(bufnr)
  local bufhidden = vim.bo[bufnr].bufhidden

  if api.nvim_win_get_config(0).zindex then
    -- A floating window's buffer: force-close the window itself.
    vim.cmd("bw")
    return
  elseif idx and vim.t.bufs and #vim.t.bufs > 1 then
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

  if bufhidden ~= "delete" then
    vim.cmd("confirm bd" .. bufnr)
  end

  vim.cmd("redrawtabline")
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

  local cur = api.nvim_get_current_buf()
  for i, bufnr in ipairs(bufs) do
    if bufnr == cur then
      if (n < 0 and i == 1) or (n > 0 and i == #bufs) then
        bufs[1], bufs[#bufs] = bufs[#bufs], bufs[1]
      else
        bufs[i], bufs[i + n] = bufs[i + n], bufs[i]
      end
      break
    end
  end

  vim.t.bufs = bufs
  vim.cmd("redrawtabline")
end

return M
