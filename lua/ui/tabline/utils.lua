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

-- Buffers currently mid-"flash" (a brief highlight swap on click, before
-- `goto_buf` actually switches to it -- the same kind of momentary feedback
-- `lib.nvim.contextmenu` gives on a selection) and the duration of one.
---@type table<integer, true>
local flashing = {}
local FLASH_MS = 120

--- Briefly render `bufnr`'s chip with `UiTbBufFlash` instead of its normal
--- On/Off group, then revert. Safe to call on any bufnr, current or not.
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
  require("ui.bindings.keymaps.tabufline.state").goto_buf(bufnr)
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

--- Close every buffer in the current tab -- the click target for the "close
--- all buffers" button. A thin wrapper so the Vimscript shim below has a
--- single, stable `luaeval()` target independent of where the state module
--- itself lives.
---@return nil
function M.close_all_bufs()
  require("ui.bindings.keymaps.tabufline.state").close_all_bufs()
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
      call luaeval('require("ui.tabline.utils").goto_buf(_A)', a:bufnr)
    endfunction
  ]])
  vim.cmd([[
    function! UiTbKillBuf(bufnr, clicks, button, mod)
      call luaeval('require("ui.bindings.keymaps.tabufline.state").close_buffer(_A)', a:bufnr)
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
---@return string
local function ensure_icon_hl(fg, is_current)
  local bg_group = is_current and "UiTbBufOn" or "UiTbBufOff"
  local name = "UiTbIcon_" .. (fg and fg:gsub("#", "") or "none") .. "_" .. bg_group
  if hl_built[name] then
    return name
  end

  local bg = read_bg(bg_group)
  local ok = pcall(api.nvim_set_hl, 0, name, { fg = fg, bg = bg })
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

  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then
    local result = { icon = "󰈚", color = nil }
    icon_cache:put(cache_key, result)
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

--- Render one buffer chip: devicon, (deduplicated, truncated) name, and a
--- modified-dot or close button depending on focus/modified state. Ported
--- from `nvchad.tabufline.utils.style_buf`.
---@param bufnr integer
---@param index integer # this buffer's 1-based position in `vim.t.bufs`
---@param width integer # target chip width in columns; `bufwidth` in the tabline config
---@return string
function M.style_buf(bufnr, index, width)
  M.register_click_handlers()

  local is_current = api.nvim_get_current_buf() == bufnr
  -- Mid-flash overrides On/Off for the chip's own text/background -- not for
  -- the icon (see M.flash's own doc comment on why only the text flashes).
  local hl_suffix = M.is_flashing(bufnr) and "Flash" or (is_current and "On" or "Off")

  local icon, fg = devicon_for_buf(bufnr)
  local icon_hl = ensure_icon_hl(fg, is_current)

  local ok_name, raw_path = pcall(api.nvim_buf_get_name, bufnr)
  local name = (ok_name and raw_path ~= "") and filename(raw_path) or "[No Name]"
  if name ~= "[No Name]" then
    name = gen_unique_name(name, index) or name
  end

  local max_name_len = math.max(1, width - 5)
  if #name > max_name_len then
    name = name:sub(1, math.max(1, max_name_len - 2)) .. ".."
  end

  -- Escaped after the width/truncation math above, which has to measure the
  -- name as it will actually display -- `%%` is two characters wide in the
  -- string but renders as one literal `%`.
  --
  -- `math.max(2, ...)` rather than `math.max(1, ...)`: at `pad == 1`,
  -- `pad - 1` below is 0 -- no leading space at all, so the icon sits flush
  -- against the chip's own left edge (visible once chips narrow, e.g. a
  -- markdown file's icon touching the rounded cap with no gap, unlike an
  -- icon glyph that happens to carry its own left-bearing). `pad >= 2`
  -- guarantees at least one space on each side regardless of how narrow the
  -- chip gets.
  local pad = math.max(2, math.floor((width - #name - 5) / 2))
  local body = string.rep(" ", pad - 1)
    .. ("%#" .. icon_hl .. "#" .. icon .. " " .. M.txt(stl_escape(name), "Buf" .. hl_suffix))
    .. string.rep(" ", pad - 1)

  local modified = api.nvim_get_option_value("modified", { buf = bufnr })
  local close_or_dot = modified and M.txt("  ", "Buf" .. hl_suffix .. "Modified")
    or M.txt(M.btn(" 󰅖 ", nil, "KillBuf", bufnr), "Buf" .. hl_suffix .. "Close")

  local chip = M.btn(body, nil, "GoToBuf", bufnr) .. close_or_dot
  return M.txt(chip, "Buf" .. hl_suffix)
end

-- Clear both caches on a colorscheme change: devicon colors are absolute
-- hex, and the UiTbBufOn/Off groups they were built against just changed.
require("lib.nvim.bindings.autocmd").create("ColorScheme", function()
  icon_cache = require("lib.lua.memo.lru").new(256)
  hl_built = {}
end, {
  group = require("lib.nvim.bindings.autocmd").group("ui_tabline_utils_cache", true),
  desc = "ui.tabline: clear the icon/highlight caches on colorscheme change",
})

return M
