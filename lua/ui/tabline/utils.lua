---@module 'ui.tabline.utils'
--- `%#HL#` text wrapping, the `%@Func@...%X` click-handler wrapping Neovim's
--- `'tabline'` option protocol uses, and `style_buf()` -- one rendered
--- buffer chip (devicon, name, modified/close indicator).
---
--- Neovim's tabline click protocol calls a global Vimscript function by
--- name, not a Lua one directly, so `register_click_handlers()` defines a
--- handful of thin `UiTb*`-prefixed shims once, at first use, that bridge
--- straight back into this module and `ui.bindings.keymaps.tabufline.state`.
--- Distinct names from NvChad's own `TbGoToBuf`/`TbKillBuf`/... so both can
--- be on the runtimepath at once without one clobbering the other's global
--- function while NvChad is still installed.

local api = vim.api
local icon_cache = require("lib.lua.memo.lru").new(256)
local notify = require("lib.nvim.notify").create("[ui.tabline.utils]")

local M = {}

-- Rounded pill caps for `M.style_buf`'s chip -- same Powerline codepoints
-- (U+E0B6/U+E0B4) `ui.statusline.utils.primitives.separators.default` uses,
-- written the same way (explicit byte escapes, not literal glyphs) for the
-- same reason: an editor/encoding pass has silently dropped these before
-- (see that table's own doc comment). Public so `ui.tabline.modules.buffers`
-- can square off the outer edges of the visible chip run.
M.LEFT_CAP = "\xEE\x82\xB6" --
M.RIGHT_CAP = "\xEE\x82\xB4" --

-- The "divider" style's boundary glyph -- a plain vertical bar, no rounding.
-- U+2502 BOX DRAWINGS LIGHT VERTICAL, not a Nerd Font private-use codepoint:
-- unlike the caps above, this one only ever needs to exist in an ordinary
-- Unicode font, so it gets no byte-escape treatment.
M.DIVIDER = "│"

-- A pinned chip's close-button slot shows this instead of "x"/the modified
-- dot -- clicking it unpins rather than closes (see `M.on_pin_click`).
-- Resolved once, lazily (not at module load: `nerd_font.available()` reads
-- live config, and this module can load before that is settled), then
-- cached -- this is on the hot per-chip render path, same reasoning as
-- `ensure_icon_hl`'s own cache below.
---@type string|nil
local pin_glyph_cache = nil
local function pin_glyph()
  pin_glyph_cache = pin_glyph_cache or require("lib.nvim.ui.nerd_font").glyph("F0403", "P")
  return pin_glyph_cache
end

-- Buffers currently mid-"flash" (a brief highlight swap on click, before
-- `goto_buf` actually switches to it -- the same kind of momentary feedback
-- `lib.nvim.contextmenu` gives on a selection) and the duration of one.
---@type table<integer, true>
local flashing = {}
local FLASH_MS = 120

-- How long a close waits behind its flash. Deliberately much shorter than
-- `FLASH_MS`: the flash only has to reach the screen once before the chip
-- disappears, and waiting out its whole 120ms made every click on an "x" feel
-- laggy -- a click that lands should land now. The flash itself still runs its
-- full course (the timer in `M.flash`), it just no longer holds the close up.
local CLOSE_DELAY_MS = 25

--- Read one of the tabline's mouse-behaviour toggles off the live config.
--- `nil` in the config means "on": these are opt-outs.
---@param name "context_menu"|"drag"|"middle_click_close"
---@return boolean
local function mouse_feature_enabled(name)
  local cfg = require("ui.tabline.render").current()
  return not (cfg and cfg[name] == false)
end

--- Briefly render `bufnr`'s chip with `UiTbBufFlash` instead of its normal
--- On/Off group, then revert. Safe to call on any bufnr, current or not.
---
--- The devicon flashes too: `ensure_icon_hl` (cached by `(fg, is_current,
--- flashing)`) swaps the icon's own fg/bg pair for ~120ms instead of
--- reusing its normal On/Off-keyed group, so the icon reads as a
--- momentary color-inverted block in step with the text's own flash
--- rather than sitting inert on its usual background while the rest of
--- the chip flashes around it.
---@param bufnr integer
---@return nil
function M.flash(bufnr)
  flashing[bufnr] = true
  pcall(vim.cmd.redrawtabline)
  vim.defer_fn(function()
    flashing[bufnr] = nil
    pcall(vim.cmd.redrawtabline)
  end, FLASH_MS)
end

--- Keep `bufnr`'s chip in the flash look until the returned function is
--- called -- how the tab context menu marks which chip it is about, the same
--- way filetree's menu marks its node. Unlike `flash` there is no timeout; the
--- caller owns the release.
---@param bufnr integer
---@return fun() release
function M.hold(bufnr)
  flashing[bufnr] = true
  pcall(vim.cmd.redrawtabline)
  return function()
    flashing[bufnr] = nil
    pcall(vim.cmd.redrawtabline)
  end
end

--- Whether `bufnr` is currently mid-flash. Exposed for tests; `style_buf`
--- reads this directly.
---@param bufnr integer
---@return boolean
function M.is_flashing(bufnr)
  return flashing[bufnr] == true
end

--- `goto_buf`, wrapped with the click-flash above. The click handler calls
--- this instead of `ui.bindings.keymaps.tabufline.state.goto_buf` directly,
--- so every click-driven buffer switch flashes, while keymap-driven
--- switching (Tab/Shift-Tab, `:UI` commands) stays flash-free -- a flash
--- makes sense as click feedback, not as feedback for an action the user's
--- own keypress already told them happened.
---@param bufnr integer
---@return nil
function M.goto_buf(bufnr)
  M.flash(bufnr)
  -- pcall'd like `close_buffer` below: the tabline was rendered with this
  -- bufnr as a click target, but it can have gone invalid by the time the
  -- click actually lands (closed by a near-simultaneous click on a
  -- neighbour's "x", or a keymap) -- must not surface as an unhandled error
  -- out of the click handler.
  local ok, err = pcall(require("ui.bindings.keymaps.tabufline.state").goto_buf, bufnr)
  if not ok then
    notify.warn("goto_buf failed: " .. tostring(err))
  end
end

---@param str string|nil
---@param hl string|nil # suffix only -- "BufOn" becomes group "UiTbBufOn"
---@return string
function M.txt(str, hl)
  str = str or ""
  return hl and ("%#UiTb" .. hl .. "#" .. str) or str
end

---@param str string
---@param hl string|nil
---@param func string # suffix only -- "GoToBuf" becomes global function "UiTbGoToBuf"
---@param arg string|integer|nil # the click handler's `minwid` (e.g. a bufnr or tab number)
---@return string
function M.btn(str, hl, func, arg)
  str = hl and M.txt(str, hl) or str
  arg = arg or ""
  return "%" .. tostring(arg) .. "@UiTb" .. func .. "@" .. str .. "%X"
end

--- Close `bufnr` (default: the current buffer), flashed first. Unlike
--- `goto_buf` above, this flash is NOT click-only by design: a close is
--- destructive and immediate, so the chip closing right as you click on it
--- (or press the keymap) never actually renders the flash -- there is
--- nothing left to redraw once the buffer is gone. Deferring the real close
--- behind the flash fixes that for any single-buffer close, not just the
--- tabline's own "x" button -- `ui.bindings.keymaps.tabufline.close_n_buffers`
--- uses this too for a plain (uncounted) close.
---@param bufnr? integer
---@return nil
function M.close_buffer(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  M.flash(bufnr)
  vim.defer_fn(function()
    -- pcall'd like every other call site in this ecosystem (see
    -- docs/BINDINGS.md's "a failure notifies and returns rather than
    -- raising"): this runs 120ms after the synchronous half already
    -- returned, so a bufnr that went invalid in the meantime (closed
    -- elsewhere, double-clicked) must not surface as an unhandled error out
    -- of a timer callback.
    local ok, err = pcall(require("ui.bindings.keymaps.tabufline.state").close_buffer, bufnr)
    if not ok then
      notify.warn("close_buffer failed: " .. tostring(err))
    end
  end, CLOSE_DELAY_MS)
end

--- Close a chosen set of buffers -- the tab context menu's "close others",
--- "close to the right" and friends. Same shape as `close_all_bufs` below
--- (every listed buffer flashes together, one deferred close for the whole
--- batch, one discard prompt for all the modified ones) over `bufnrs` instead
--- of the whole tab.
---@param bufnrs integer[]
---@return nil
function M.close_bufs(bufnrs)
  for _, bufnr in ipairs(bufnrs) do
    M.flash(bufnr)
  end

  vim.defer_fn(function()
    -- Same pcall guard as `M.close_buffer` above, same reason.
    local ok, err = pcall(require("ui.bindings.keymaps.tabufline.state").close_bufs, bufnrs)
    if not ok then
      notify.warn("close_bufs failed: " .. tostring(err))
    end
  end, CLOSE_DELAY_MS)
end

--- Close every buffer in the current tab -- the click target for the "close
--- all buffers" button, and `ui.bindings.keymaps`'s `close_all` action. Every
--- listed buffer flashes together, once, before the whole batch closes --
--- not `close_buffer()` called once per bufnr, which would stagger `#bufs`
--- separate deferred closes instead of one.
---@param include_cur_buf? boolean # default true, forwarded to state.close_all_bufs
---@return nil
function M.close_all_bufs(include_cur_buf)
  -- Flashes every listed buffer, the current one included even when
  -- `include_cur_buf == false` will spare it from the actual close below --
  -- flashing a buffer that turns out to survive is harmless, and not
  -- special-casing it here avoids duplicating state.close_all_bufs()'s own
  -- exclusion logic just to decide what to flash.
  for _, bufnr in ipairs(vim.t.bufs or {}) do
    M.flash(bufnr)
  end

  vim.defer_fn(function()
    -- Same pcall guard as M.close_buffer above, same reason: this fires
    -- 120ms after the caller's own pcall (the close_all keymap's `rhs`) has
    -- already returned, so it is the only thing left standing between a
    -- failure here and an unhandled error out of a timer callback.
    local ok, err =
      pcall(require("ui.bindings.keymaps.tabufline.state").close_all_bufs, include_cur_buf)
    if not ok then
      notify.warn("close_all_bufs failed: " .. tostring(err))
    end
  end, CLOSE_DELAY_MS)
end

--- Whether `bufnr` is pinned -- and, if so, warn once for this call. Guards
--- middle-click and the "x" button below: a pinned chip refuses those two
--- accidental, one-click closes so a pin actually protects, per the
--- roadmap's own "Tabs anpinnen" spec. The tab menu's own "Close"/"Close
--- others"/etc. (`ui.tabline.menu`) do NOT go through this guard -- those
--- are a deliberate choice through a menu, not a stray click.
---@param bufnr integer
---@return boolean
local function guard_pinned_close(bufnr)
  local pinned = require("ui.bindings.keymaps.tabufline.state").is_pinned(bufnr)
  if pinned then
    notify.info("tab is pinned -- unpin it first to close")
  end
  return pinned
end

--- Click on a pinned chip's pin glyph (the close-button slot on a pinned
--- chip): unpin. There is no click target to PIN a chip from the bar itself
--- -- only the tab menu's "Pin" entry does that -- so this only ever runs on
--- an already-pinned chip.
---@param bufnr integer
---@return nil
function M.on_pin_click(bufnr)
  local ok, err = pcall(require("ui.bindings.keymaps.tabufline.state").set_pinned, bufnr, false)
  if not ok then
    notify.warn("unpin failed: " .. tostring(err))
  end
end

--- A left/right/middle click on a buffer chip's body, dispatched by the
--- tabline click protocol's `button` argument ("l", "r", "m").
---
--- * left   -- switch to the buffer, and arm a drag so the chip can be
---             carried along the bar (`ui.tabline.drag`)
--- * right  -- open the tab context menu for it (`ui.tabline.menu`)
--- * middle -- close it, the usual tab-bar convention
---
--- `cfg.context_menu`, `cfg.drag` and `cfg.middle_click_close` (each `false`
--- to opt out) fall back to plain "switch to it": what any click on a chip
--- did before these existed.
---@param bufnr integer
---@param button string
---@return nil
function M.on_chip_click(bufnr, button)
  if button == "r" and mouse_feature_enabled("context_menu") then
    -- Scheduled: opens a floating window and moves focus, which is not
    -- something to do from inside the click handler Neovim is still in.
    vim.schedule(function()
      require("ui.tabline.menu").open(bufnr)
    end)
    return
  end

  if button == "m" and mouse_feature_enabled("middle_click_close") then
    if guard_pinned_close(bufnr) then
      return
    end
    M.close_buffer(bufnr)
    return
  end

  M.goto_buf(bufnr)
  if button == "l" and mouse_feature_enabled("drag") then
    require("ui.tabline.drag").begin(bufnr)
  end
end

--- A click on a chip's close ("x") button. Left and middle close it; right
--- opens the same tab context menu the rest of the chip does, rather than
--- closing on a click that was reaching for a menu.
---@param bufnr integer
---@param button string
---@return nil
function M.on_close_click(bufnr, button)
  if button == "r" and mouse_feature_enabled("context_menu") then
    vim.schedule(function()
      require("ui.tabline.menu").open(bufnr)
    end)
    return
  end
  if guard_pinned_close(bufnr) then
    return
  end
  M.close_buffer(bufnr)
end

local registered = false

--- Define the `UiTb*` global Vimscript functions the click handlers above
--- reference, once. Idempotent, and cheap enough (`vim.cmd` on ~7 one-line
--- function bodies) to call unconditionally from `M.style_buf`/the tabs and
--- buttons modules rather than threading a "did this run yet" flag through
--- every call site.
---@return nil
function M.register_click_handlers()
  if registered then
    return
  end
  registered = true

  vim.cmd([[
    function! UiTbGoToBuf(bufnr, clicks, button, mod)
      call luaeval('require("ui.tabline.utils").on_chip_click(_A[1], _A[2])', [a:bufnr, a:button])
    endfunction
  ]])
  vim.cmd([[
    function! UiTbKillBuf(bufnr, clicks, button, mod)
      call luaeval('require("ui.tabline.utils").on_close_click(_A[1], _A[2])', [a:bufnr, a:button])
    endfunction
  ]])
  vim.cmd([[
    function! UiTbTogglePin(bufnr, clicks, button, mod)
      call luaeval('require("ui.tabline.utils").on_pin_click(_A[1])', [a:bufnr])
    endfunction
  ]])
  vim.cmd([[
    function! UiTbNewTab(arg, clicks, button, mod)
      tabnew
    endfunction
  ]])
  vim.cmd([[
    function! UiTbGotoTab(tabnr, clicks, button, mod)
      execute a:tabnr .. 'tabnext'
    endfunction
  ]])
  vim.cmd([[
    function! UiTbCloseAllBufs(arg, clicks, button, mod)
      call luaeval('require("ui.tabline.utils").close_all_bufs()')
    endfunction
  ]])
  vim.cmd([[
    function! UiTbToggleTheme(arg, clicks, button, mod)
      call luaeval('require("ui.bindings.usrcmds.themes").toggle_theme()')
    endfunction
  ]])
  vim.cmd([[
    function! UiTbToggleTabs(arg, clicks, button, mod)
      let g:ui_tb_tabs_toggled = !get(g:, 'ui_tb_tabs_toggled', 0)
      redrawtabline
    endfunction
  ]])
end

---@param path string
---@return string name
local function filename(path)
  return path:match("([^/\\]+)[/\\]*$") or path
end

--- Escape a literal `%` so embedding this string into `'tabline'` cannot be
--- misread as one of its own `%`-directives (`%#Group#`, `%=`, `%N@Func@`,
--- ...) -- a buffer's file/directory name is filesystem-controlled, not
--- something this module can assume is free of it (a file named e.g.
--- `50%done.lua`, or one deliberately crafted to break tabline rendering).
--- Same fix the statusline's own breadcrumb rendering already applies to
--- LSP/Treesitter symbol text for the identical reason.
---@param s string
---@return string
local function stl_escape(s)
  return (s:gsub("%%", "%%%%"))
end

---@param group string
---@return integer|nil
local function read_bg(group)
  local ok, hl = pcall(api.nvim_get_hl, 0, { name = group, link = false })
  if not ok or not hl then
    return nil
  end
  return hl.bg
end

-- One highlight group per (fg, is_current) combination actually seen, not a
-- freshly `nvim_set_hl`'d group on every single buffer render -- same fix as
-- `ui.statusline.modules.file_icons.devicons`'s `hl_built` cache, same
-- reason: an unconditional `nvim_set_hl` call per buffer per tabline redraw
-- is pure waste once a color has already been built once.
---@type table<string, true>
local hl_built = {}

---@param fg string|nil
---@param is_current boolean
---@param mid_flash boolean # mid-"flash" (see M.flash) -- swaps fg/bg instead of the normal pair
---@return string
local function ensure_icon_hl(fg, is_current, mid_flash)
  local bg_group = is_current and "UiTbBufOn" or "UiTbBufOff"
  local name = "UiTbIcon_"
    .. (fg and fg:gsub("#", "") or "none")
    .. "_"
    .. bg_group
    .. (mid_flash and "_Flash" or "")
  if hl_built[name] then
    return name
  end

  local bg = read_bg(bg_group)
  local hl
  if mid_flash then
    -- Inverted: the icon's normal background becomes its foreground, and
    -- its own devicon color (or, lacking one, the text flash's own
    -- background) becomes the fill -- the same two colors as the resting
    -- state, just swapped, so the icon visibly blinks without introducing
    -- a third color that would clash with an arbitrary devicon hue.
    hl = { fg = bg, bg = fg or read_bg("UiTbBufFlash") }
  else
    hl = { fg = fg, bg = bg }
  end
  local ok = pcall(api.nvim_set_hl, 0, name, hl)
  if ok then
    hl_built[name] = true
  end
  return name
end

---@param bufnr integer
---@return string icon, string|nil color
local function devicon_for_buf(bufnr)
  local ok_name, path = pcall(api.nvim_buf_get_name, bufnr)
  path = ok_name and path or ""
  local name = path == "" and "" or filename(path)

  local cache_key = name
  local cached = icon_cache:get(cache_key)
  if cached then
    return cached.icon, cached.color
  end

  local soft_require = require("ui.util.soft_require")
  local devicons = soft_require.try("nvim-web-devicons")
  if not devicons then
    local result = { icon = "󰈚", color = nil }
    -- Only cache when devicons is confirmed absent (PERF-42): while it is
    -- merely not lazy-loaded yet, caching here would keep serving the
    -- fallback with no trigger to ever invalidate once it does load.
    if not soft_require.available("nvim-web-devicons") then
      icon_cache:put(cache_key, result)
    end
    return result.icon, result.color
  end

  local icon, color = devicons.get_icon_color(name, name:match("^.+%.(.+)$"), { default = true })
  local result = { icon = icon or "󰈚", color = color }
  icon_cache:put(cache_key, result)
  return result.icon, result.color
end

--- `name` deduplicated against every other buffer's tail filename in
--- `vim.t.bufs` -- two open `init.lua`s become `plugins/init.lua` and
--- `lsp/init.lua` instead of two indistinguishable "init.lua" chips. Ported
--- from `nvchad.tabufline.utils.gen_unique_name`.
---@param name string
---@param index integer # this buffer's position in `vim.t.bufs`
---@return string|nil # nil when `name` is already unique
local function gen_unique_name(name, index)
  local bufs = vim.t.bufs or {}
  for i, nr in ipairs(bufs) do
    if i ~= index and api.nvim_buf_is_valid(nr) and filename(api.nvim_buf_get_name(nr)) == name then
      return vim.fn.fnamemodify(api.nvim_buf_get_name(bufs[index]), ":h:t") .. "/" .. name
    end
  end
  return nil
end

-- `close_or_dot`'s rendered width, keyed by its shape -- three ever exist
-- (the close button " 󰅖 ", the modified-buffer dot " ● ", the pin glyph on
-- a pinned chip), and none changes with the highlight group name or the
-- click-id embedded in it, so this is measured at most three times per
-- session, ever, not per chip per redraw. `nvim_eval_statusline` (not
-- `strdisplaywidth`) because the real string carries `%#Group#`/
-- `%N@Func@...%X` tabline directives, which `strdisplaywidth` would count
-- as literal text instead of the zero-width markup they are.
---@type table<"modified"|"unmodified"|"pinned", integer>
local close_width_cache = {}

---@param shape "modified"|"unmodified"|"pinned"
---@param rendered string
---@return integer
local function close_width(shape, rendered)
  local cached = close_width_cache[shape]
  if cached then
    return cached
  end
  local w = api.nvim_eval_statusline(rendered, { use_tabline = true }).width
  close_width_cache[shape] = w
  return w
end

--- Render one buffer chip: devicon, (deduplicated, truncated) name, and a
--- modified-dot or close button depending on focus/modified state. Ported
--- from `nvchad.tabufline.utils.style_buf`.
---
--- The chip's rendered width never exceeds `width`: every fixed-width
--- piece (icon, the space after it, the close/modified button) is measured
--- for real rather than assumed, and the name is truncated to whatever is
--- left over -- the caller (`ui.tabline.modules.buffers`) budgets how many
--- whole chips fit into the available columns from this same `width`, so a
--- chip that quietly rendered wider than promised (found live: exactly
--- this, at narrow widths, from a `math.max(2, ...)` padding floor that
--- could win over the width budget) overflows the whole tabline by that
--- much per chip -- invisible until Neovim's own last-resort truncation
--- (no `%<` marker anywhere in this tabline) chops it off the FRONT of the
--- first chip, mangling exactly the one buffer a reader looks for first.
---@param bufnr integer
---@param index integer # this buffer's 1-based position in `vim.t.bufs`
---@param width integer # target chip width in columns; `bufwidth` in the tabline config
---@param is_pinned? boolean # precomputed pin state; queried via `state.is_pinned(bufnr)` when omitted -- `ui.tabline.modules.buffers()` already knows this per chip (it just split pinned from unpinned) and passes it straight in, so this hot per-chip, per-redraw path does not pay for a second `vim.t.ui_pinned` read on top of that split's own one
---@return string
function M.style_buf(bufnr, index, width, is_pinned)
  M.register_click_handlers()

  local is_current = api.nvim_get_current_buf() == bufnr
  local mid_flash = M.is_flashing(bufnr)
  -- Mid-flash overrides On/Off for the chip's own text/background (see
  -- M.flash's own doc comment) -- and for the icon too, via `mid_flash`
  -- below, so the whole chip blinks together rather than just its text.
  local hl_suffix = mid_flash and "Flash" or (is_current and "On" or "Off")

  local icon, fg = devicon_for_buf(bufnr)
  local icon_hl = ensure_icon_hl(fg, is_current, mid_flash)

  local ok_name, raw_path = pcall(api.nvim_buf_get_name, bufnr)
  local name = (ok_name and raw_path ~= "") and filename(raw_path) or "[No Name]"
  if name ~= "[No Name]" then
    name = gen_unique_name(name, index) or name
  end

  -- Always a click target, modified or not: a plain "unsaved changes" dot
  -- with no click handler (found live: rendered as two blank spaces, no
  -- glyph at all) left a modified buffer's chip with no way to close it by
  -- mouse whatsoever -- indistinguishable from a rendering bug. `KillBuf`
  -- already routes through `confirm bd<bufnr>` (see
  -- `ui.bindings.keymaps.tabufline.state.close_buffer`), which prompts to
  -- save/discard/cancel for a modified buffer, so wiring the same handler
  -- here is safe -- only the icon/highlight differs from the plain close
  -- button, as a reminder that closing will prompt.
  --
  -- A pinned chip takes over this same slot with a pin glyph instead: it
  -- clicks through to `UiTbTogglePin` (unpin), not `KillBuf` -- middle-click
  -- and the plain "x" both refuse to close a pinned chip anyway (see
  -- `guard_pinned_close`), so offering "x" here would be a dead end.
  local modified = api.nvim_get_option_value("modified", { buf = bufnr })
  if is_pinned == nil then
    is_pinned = require("ui.bindings.keymaps.tabufline.state").is_pinned(bufnr)
  end
  local shape, close_or_dot
  if is_pinned then
    shape = "pinned"
    close_or_dot = M.txt(
      M.btn(" " .. pin_glyph() .. " ", nil, "TogglePin", bufnr),
      "Buf" .. hl_suffix .. "Pinned"
    )
  elseif modified then
    shape = "modified"
    close_or_dot = M.txt(M.btn(" ● ", nil, "KillBuf", bufnr), "Buf" .. hl_suffix .. "Modified")
  else
    shape = "unmodified"
    close_or_dot = M.txt(M.btn(" 󰅖 ", nil, "KillBuf", bufnr), "Buf" .. hl_suffix .. "Close")
  end

  -- icon + the single space that always follows it -- `strdisplaywidth`
  -- (not `#icon`) since devicon glyphs are multi-byte and occasionally
  -- multi-cell; no `%` directives in a bare glyph, so this is cheaper than
  -- `nvim_eval_statusline` and just as correct.
  local icon_part_width = vim.fn.strdisplaywidth(icon) + 1
  -- At least one space on each side of the icon+name block, always -- an
  -- icon flush against the chip's own rounded cap (visible once chips get
  -- this narrow) looks like a rendering glitch, not a deliberately tight
  -- chip.
  local min_side_pad = 1
  local fixed = icon_part_width + close_width(shape, close_or_dot) + min_side_pad * 2

  -- `math.max(0, ...)`, not `math.max(1, ...)`: below `fixed` (icon +
  -- padding + close/modified button, no name at all), there is no name
  -- length left to show and forcing one anyway would only add width a
  -- `width` this tight never asked for. `width < fixed` itself is a
  -- structurally impossible request (the icon and close button alone
  -- already cost `fixed`) that this function cannot honor either way --
  -- `M.buffers()` never sends one in practice, its own `bufwidth` floor
  -- (`MIN_BUFWIDTH` / `cfg.bufwidth_min`, 12 by default) sits well above
  -- `fixed`.
  local max_name_len = math.max(0, width - fixed)
  if #name > max_name_len then
    if max_name_len <= 2 then
      -- Not even room for one head character plus "..": the ellipsis
      -- itself would blow the budget this narrow, so it is dropped rather
      -- than added on top of a truncated name that no longer fits either.
      name = name:sub(1, max_name_len)
    else
      name = name:sub(1, max_name_len - 2) .. ".."
    end
  end

  -- Escaped after the width/truncation math above, which has to measure the
  -- name as it will actually display -- `%%` is two characters wide in the
  -- string but renders as one literal `%`.
  local extra = math.max(0, width - fixed - #name)
  local side_pad = min_side_pad + math.floor(extra / 2)

  local body = string.rep(" ", side_pad)
    .. ("%#" .. icon_hl .. "#" .. icon .. " " .. M.txt(stl_escape(name), "Buf" .. hl_suffix))
    .. string.rep(" ", side_pad)

  local chip = M.btn(body, nil, "GoToBuf", bufnr) .. close_or_dot
  return M.txt(chip, "Buf" .. hl_suffix)
end

-- Clear both caches on a colorscheme change: devicon colors are absolute
-- hex, and the UiTbBufOn/Off groups they were built against just changed.
require("lib.nvim.ui.hl").persist(function()
  icon_cache = require("lib.lua.memo.lru").new(256)
  hl_built = {}
end, { name = "ui_tabline_utils_cache", immediate = false })

return M
