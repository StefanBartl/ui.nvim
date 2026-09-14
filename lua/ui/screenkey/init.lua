---@module 'ui.screenkey'
--- In-editor keystroke HUD -- shows the keys currently being pressed in a
--- small corner float, for recording demos/GIFs of this plugin fleet (the
--- live/animated equivalent of the screenshots several sibling READMEs
--- already ship, e.g. `cmdlog.nvim/docs/assets/Cmdlog-Picker-UI.png`). Not a
--- daily-driver feature -- off by default, and stays off until `:UI
--- screenkey` (or `M.enable()`) turns it on for the session.
---
--- Built entirely on native Neovim primitives, no missing building block:
--- `vim.on_key()` intercepts every keypress, `vim.fn.keytrans()` formats the
--- raw byte sequence into human-readable form (`<C-w>`, `<Esc>`, ...). The
--- float itself is `ui.kit.surface` -- the same primitive `ui.kit.toast`
--- reflows into a corner, no new float-window mechanics invented here.
---
--- The `vim.on_key()` hook is registered only while enabled (mirrors
--- `ui.statusline.modules.macro_counter`'s own `RecordingEnter`/
--- `RecordingLeave`-bracketed hook) -- a disabled screenkey costs nothing on
--- every keystroke in the session, not just "renders nothing".

local surface = require("ui.kit.surface")
local debounce = require("lib.nvim.debounce")

local NS = vim.api.nvim_create_namespace("ui_screenkey")

local M = {}

--- `M.setup(opts)`'s own parameter shape -- every field optional, overriding
--- just the ones a host passes.
---@class Ui.Screenkey.Opts
---@field fade_ms? integer
---@field width? integer
---@field height? integer
---@field margin? integer
---@field max_entries? integer
---@field theme? string|table|nil

---@class Ui.Screenkey.Config
---@field fade_ms integer # how long the HUD stays up after the last keystroke
---@field width integer # float width in columns
---@field height integer # float height in rows -- one line, MVP
---@field margin integer # columns from the right edge / rows above the cmdline
---@field max_entries integer # rolling cap on tracked key entries, before display-width truncation
---@field theme string|table|nil # forwarded to ui.kit.surface's theme resolver
local cfg = {
  fade_ms = 2000,
  width = 40,
  height = 1,
  margin = 2,
  max_entries = 30,
  theme = nil,
}

---@type boolean
local enabled = false
---@type Ui.Kit.Surface|nil
local surf = nil
---@type { key: string, count: integer }[]
local entries = {}

---@internal
--- Close the float and drop every tracked entry -- the fade's own end state,
--- and what `M.disable()` resets to as well.
---@return nil
local function clear()
  if surf then
    surf:close()
    surf = nil
  end
  entries = {}
end

---@internal
--- One debounce handle per `cfg.fade_ms` -- rebuilt in `M.setup()` whenever
--- that value changes, since `lib.nvim.debounce.new()` bakes its `ms`
--- argument in at creation rather than reading it live per call.
local function build_fader()
  return debounce.new(clear, cfg.fade_ms)
end

local fader = build_fader()

---@internal
--- The formatted display key×count suffix as `\xC3\x97` (U+00D7 MULTIPLICATION
--- SIGN), written as explicit bytes rather than a literal glyph -- same
--- reason `ui.tabline.utils`'s rounded-cap codepoints and
--- `ui.statusline.modules.macro_counter`'s middle dot are: an editor/encoding
--- pass has silently dropped literal multi-byte glyphs from this codebase
--- before.
local TIMES = "\xC3\x97"

---@internal
--- Build the one-line display string from `entries`, dropping the oldest
--- entries (never the newest) until it fits `cfg.width` -- the most recent
--- keystroke is always the one worth seeing.
---@return string
local function build_text()
  local parts = {}
  for _, e in ipairs(entries) do
    parts[#parts + 1] = (e.count > 1) and (e.key .. TIMES .. e.count) or e.key
  end

  local max_w = math.max(1, cfg.width - 2) -- inside the border/padding
  local text = table.concat(parts, " ")
  while #parts > 1 and vim.fn.strdisplaywidth(text) > max_w do
    table.remove(parts, 1)
    text = table.concat(parts, " ")
  end
  if vim.fn.strdisplaywidth(text) > max_w then
    -- A single entry alone overflows (a long <Cmd>...<CR> sequence) -- crude
    -- byte-based clip rather than nothing at all; this is a rare edge case,
    -- not the common path the loop above already handles.
    text = text:sub(-max_w)
  end
  return text
end

---@internal
--- Bottom-right corner, same margin-from-edges arithmetic
--- `ui.kit.compare`/`ui.kit.layout` already use for "usable rows above the
--- cmdline" (`vim.o.lines - (vim.o.cmdheight or 1)`).
---@return integer row, integer col
local function corner_geometry()
  local usable_lines = vim.o.lines - (vim.o.cmdheight or 1)
  local row = math.max(0, usable_lines - cfg.height - cfg.margin)
  local col = math.max(0, vim.o.columns - cfg.width - cfg.margin)
  return row, col
end

---@internal
--- Open the float on first render, `set_lines` on every one after -- mirrors
--- `ui.kit.toast`'s own open-once-then-update shape, minus the stacking (one
--- screenkey HUD, not several).
---@return nil
local function render()
  local text = build_text()

  if surf and surf:is_valid() then
    surf:set_lines({ text })
    return
  end

  local row, col = corner_geometry()
  surf = surface.open({
    lines = { text },
    width = cfg.width,
    height = cfg.height,
    relative = "editor",
    row = row,
    col = col,
    title = "Screenkey",
    theme = cfg.theme,
    enter = false, -- never steal focus
    focusable = false,
  })
end

---@internal
--- The `vim.on_key()` callback. Deliberately minimal outside `vim.schedule`
--- -- the raw callback runs in Neovim's own input-processing path, not a
--- normal call stack, so the actual state mutation and every API call
--- (`nvim_open_win` et al., via `render()`) are deferred onto the main loop
--- the same way `lib.nvim.debounce`'s own fired callback already is.
---@param key string # post-mapping raw keycode, per vim.on_key()'s own contract
---@return nil
local function on_key(key)
  if key == "" then
    return
  end
  vim.schedule(function()
    if not enabled then
      return
    end
    local ok, trans = pcall(vim.fn.keytrans, key)
    if not ok or trans == nil or trans == "" then
      return
    end

    local last = entries[#entries]
    if last and last.key == trans then
      last.count = last.count + 1
    else
      entries[#entries + 1] = { key = trans, count = 1 }
      if #entries > cfg.max_entries then
        table.remove(entries, 1)
      end
    end

    render()
    fader.call()
  end)
end

---Override the shipped tunables. Safe to call before or after `M.enable()`;
---a `fade_ms` change takes effect on the next keystroke's fade, not
---retroactively on one already pending.
---@param opts? Ui.Screenkey.Opts
---@return nil
function M.setup(opts)
  opts = opts or {}
  if opts.width then
    cfg.width = opts.width
  end
  if opts.height then
    cfg.height = opts.height
  end
  if opts.margin then
    cfg.margin = opts.margin
  end
  if opts.max_entries then
    cfg.max_entries = opts.max_entries
  end
  if opts.theme ~= nil then
    cfg.theme = opts.theme
  end
  if opts.fade_ms then
    cfg.fade_ms = opts.fade_ms
    fader.cancel()
    fader = build_fader()
  end
end

---Turn the HUD on: registers the `vim.on_key()` hook. Idempotent.
---@return nil
function M.enable()
  if enabled then
    return
  end
  enabled = true
  entries = {}
  vim.on_key(on_key, NS)
end

---Turn the HUD off: detaches the hook and closes/clears the float.
---Idempotent.
---@return nil
function M.disable()
  if not enabled then
    return
  end
  enabled = false
  vim.on_key(nil, NS)
  fader.cancel()
  clear()
end

---Flip the HUD on/off.
---@return boolean now_enabled
function M.toggle()
  if enabled then
    M.disable()
  else
    M.enable()
  end
  return enabled
end

---@return boolean
function M.is_enabled()
  return enabled
end

---The current HUD float, or `nil` while closed/disabled -- mainly for
---inspection: TESTS/screenkey_spec.lua reads its buffer directly rather than
---a bespoke peek accessor, and it's the natural hook for future
---debugging/health-check use too.
---@return Ui.Kit.Surface|nil
function M.surface()
  return surf
end

return M
