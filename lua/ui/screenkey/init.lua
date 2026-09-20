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
local normalize = require("lib.nvim.normalize")
local autocmd = require("lib.nvim.bindings.autocmd")

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
---@field labels? table<string, string>
---@field join_chars? boolean

---@class Ui.Screenkey.Config
---@field fade_ms integer # how long the HUD stays up after the last keystroke
---@field width integer # float width in columns
---@field height integer # float height in rows -- one line, MVP
---@field margin integer # columns from the right edge / rows above the cmdline
---@field max_entries integer # rolling cap on tracked key entries, before display-width truncation
---@field theme string|table|nil # forwarded to ui.kit.surface's theme resolver
---@field labels table<string, string> # keytrans() name -> what to show instead, e.g. { ["<Space>"] = "\xE2\x90\xA3" (U+2423), ["<CR>"] = "\xE2\x8F\x8E" (U+23CE) }
---@field join_chars boolean # run plain characters together ("todo.md") instead of one chip per key ("t o d o . m d")
local cfg = {
  fade_ms = 2000,
  width = 40,
  height = 1,
  margin = 2,
  max_entries = 30,
  theme = nil,
  labels = {},
  join_chars = false,
}

---@type boolean
local enabled = false
---@type Ui.Kit.Surface|nil
local surf = nil
---@type { key: string, count: integer }[]
local entries = {}
---@type string[]
--- Rejected values from the last `M.setup()` call -- an invalid single value
--- keeps `cfg`'s current one instead of corrupting it, surfaced through
--- `:checkhealth ui` rather than raised (ERR-22).
local setup_issues = {}

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
---@internal
--- What one entry shows: its `cfg.labels` replacement when there is one,
--- the keytrans() name otherwise.
---@param key string
---@return string
local function label_of(key)
  local l = cfg.labels[key]
  if type(l) == "string" and l ~= "" then
    return l
  end
  return key
end

---@internal
--- With `cfg.join_chars`, a run of single presses whose display is not a
--- `<...>` keycode is one chip ("todo.md" rather than "t o d o . m d"), so
--- typed text reads as text while `<Esc>`, `<C-w>` and repeat counts still
--- stand apart. A label counts as text too: `<Space>` shown as U+2423
--- joins its neighbours, an unlabelled `<Space>` does not.
--- A short repeat ("pp" in "app", "ee" in "see") is spelled out inside the
--- run; from JOIN_REPEAT_MAX + 1 on it is a held key and stays a `key×N`
--- chip of its own, so "jjjjjjjj" does not paint a wall of j.
---@param display string
---@param count integer
---@return boolean
local JOIN_REPEAT_MAX = 3
local function joinable(display, count)
  return cfg.join_chars and count <= JOIN_REPEAT_MAX and display:match("^<.+>$") == nil
end

local function build_text()
  local parts = {}
  local open = false -- whether parts[#parts] is a run that may still grow
  for _, e in ipairs(entries) do
    local display = label_of(e.key)
    if joinable(display, e.count) then
      local run = display:rep(e.count)
      if open then
        parts[#parts] = parts[#parts] .. run
      else
        parts[#parts + 1] = run
        open = true
      end
    else
      parts[#parts + 1] = (e.count > 1) and (display .. TIMES .. e.count) or display
      open = false
    end
  end

  local max_w = math.max(1, cfg.width - 2) -- inside the border/padding
  local text = table.concat(parts, " ")
  while #parts > 1 and vim.fn.strdisplaywidth(text) > max_w do
    table.remove(parts, 1)
    text = table.concat(parts, " ")
  end
  -- A single part alone overflows: a long <Cmd>...<CR> sequence, or with
  -- `join_chars` any typed command line. Drop leading *characters* until it
  -- fits -- a byte-based clip could cut a multi-byte glyph (a label such as
  -- U+2423) in half and put invalid UTF-8 into the buffer.
  while vim.fn.strdisplaywidth(text) > max_w and vim.fn.strchars(text) > 1 do
    text = vim.fn.strcharpart(text, 1)
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
--- Reposition the live HUD at its current corner -- the editor may have been
--- resized since it was opened (PERF-92: geometry must never stay pinned to
--- the size it happened to open at). No-op while closed.
---@return nil
local function reposition()
  if not (surf and surf:is_valid()) then
    return
  end
  local row, col = corner_geometry()
  pcall(vim.api.nvim_win_set_config, surf.winid, {
    relative = "editor",
    row = row,
    col = col,
    width = cfg.width,
    height = cfg.height,
  })
end

---@internal
--- Open the float on first render, `set_lines` on every one after -- mirrors
--- `ui.kit.toast`'s own open-once-then-update shape, minus the stacking (one
--- screenkey HUD, not several). Repositions the existing float every time
--- too, so a `VimResized` while the HUD is up (it can stay up for as long as
--- keys keep coming) is reflected on the very next keystroke rather than
--- leaving it pinned to stale coordinates (PERF-92).
---@return nil
local function render()
  local text = build_text()

  if surf and surf:is_valid() then
    reposition()
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
    -- A raw terminal code (`<t_..>`: a key the terminal sent in a form
    -- Neovim has no name for) means nothing to a viewer; leave it out.
    if trans:sub(1, 3) == "<t_" then
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

---@internal
--- Validate one integer field of `opts` and apply it to `cfg`, or reject it
--- and record why -- an invalid value keeps `cfg`'s current one rather than
--- being accepted as-is (ERR-22).
---@param opts Ui.Screenkey.Opts
---@param field "width"|"height"|"margin"|"max_entries"|"fade_ms"
---@param min integer
---@return boolean applied
local function apply_int(opts, field, min)
  local v = opts[field]
  if v == nil then
    return false
  end
  local ok, n, err = normalize.as_int(field, v, min, false)
  if ok then
    cfg[field] = n
    return true
  end
  setup_issues[#setup_issues + 1] = ("%s (kept %s)"):format(
    err or (field .. " is invalid"),
    tostring(cfg[field])
  )
  return false
end

---Override the shipped tunables. Safe to call before or after `M.enable()`;
---a `fade_ms` change takes effect on the next keystroke's fade, not
---retroactively on one already pending. An invalid value (wrong type, or
---below its minimum) is rejected and `cfg` keeps its current value; see
---`M.health_issues()`.
---@param opts? Ui.Screenkey.Opts
---@return nil
function M.setup(opts)
  opts = opts or {}
  setup_issues = {}

  apply_int(opts, "width", 1)
  apply_int(opts, "height", 1)
  apply_int(opts, "margin", 0)
  apply_int(opts, "max_entries", 1)
  if opts.theme ~= nil then
    cfg.theme = opts.theme
  end
  if opts.labels ~= nil then
    if type(opts.labels) == "table" then
      local clean = {}
      for k, v in pairs(opts.labels) do
        if type(k) ~= "string" or type(v) ~= "string" then
          setup_issues[#setup_issues + 1] = ("labels[%s] must map a keytrans() name to a string (dropped)"):format(
            tostring(k)
          )
        -- nvim_buf_set_lines rejects any line containing "\n" -- a label with
        -- one would crash render() on the very first keystroke that uses it
        -- (surface.open()'s own initial set_lines), not just render wrong.
        elseif v:find("\n", 1, true) then
          setup_issues[#setup_issues + 1] = ("labels[%s] must not contain a newline (dropped)"):format(
            tostring(k)
          )
        else
          clean[k] = v
        end
      end
      cfg.labels = clean
    else
      setup_issues[#setup_issues + 1] = ("labels must be a table (kept %d entries)"):format(
        vim.tbl_count(cfg.labels)
      )
    end
  end
  if opts.join_chars ~= nil then
    if type(opts.join_chars) == "boolean" then
      cfg.join_chars = opts.join_chars
    else
      setup_issues[#setup_issues + 1] = ("join_chars must be a boolean (kept %s)"):format(
        tostring(cfg.join_chars)
      )
    end
  end
  if apply_int(opts, "fade_ms", 1) then
    fader.cancel()
    fader = build_fader()
  end
end

---Rejected `M.setup()` values from the last call, one message per rejected
---field -- empty when every field validated. For `:checkhealth ui`.
---@return string[]
function M.health_issues()
  return vim.deepcopy(setup_issues)
end

---Turn the HUD on: registers the `vim.on_key()` hook and a `VimResized`
---repositioner (the HUD can sit open, updated in place, for as long as keys
---keep coming -- a resize during that window must not leave it pinned to
---stale coordinates; PERF-92). Idempotent.
---@return nil
function M.enable()
  if enabled then
    return
  end
  enabled = true
  entries = {}
  vim.on_key(on_key, NS)
  local group = autocmd.group("ui_screenkey_resize", true)
  autocmd.create("VimResized", reposition, {
    group = group,
    desc = "ui.screenkey: keep the HUD pinned to its corner",
  })
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
  pcall(vim.api.nvim_del_augroup_by_name, "ui_screenkey_resize")
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
