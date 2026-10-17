---@module 'ui.bindings.usrcmds'
---Provides :UI usercommand for runtime UI configuration (theme, transparency).

local notify = require("lib.nvim.notify").create("[ui.bindings.usrcmds]")

local M = {}

local theme = require("ui.bindings.usrcmds.themes")
local theme_picker = require("ui.bindings.usrcmds.themes.picker")
local screenkey = require("ui.screenkey")
local context = require("ui.context")
local colorpicker = require("ui.colorpicker")
local zen = require("ui.zen")
local ui_notify = require("ui.notify")
local ui_keys = require("ui.keys")
local windowpicker = require("ui.windowpicker")
local nerd_font = require("lib.nvim.ui.nerd_font")

-- Icons for `:UI` output.
--
-- Resolved once through `lib.nvim.ui.nerd_font.glyph`, which gates on
-- `vim.g.have_nerd_font` and refuses any glyph wider than one cell. These
-- used to be raw emoji (U+2728, U+1F3A8, U+2328 U+FE0F) written straight
-- into the message: emoji are commonly East-Asian-Wide, so they rendered
-- two cells and shifted everything after them, and nothing checked whether
-- the user had a font for them at all.
--
-- `""` is the fallback, and `prefix()` is what makes that safe: it drops
-- the separating space along with the icon instead of leaving every
-- message with a leading blank.
---@type table<string, string>
local ICON = {
  theme = nerd_font.glyph("f1fc", ""), -- nf-fa-paint_brush
  magic = nerd_font.glyph("f0d0", ""), -- nf-fa-magic
  keyboard = nerd_font.glyph("f11c", ""), -- nf-fa-keyboard_o
  context = nerd_font.glyph("f121", ""), -- nf-fa-code
  color = nerd_font.glyph("f1fc", ""), -- nf-fa-paint_brush
  zen = nerd_font.glyph("f10c", ""), -- nf-fa-circle_o
  bell = nerd_font.glyph("f0f3", ""), -- nf-fa-bell
  window = nerd_font.glyph("f0db", ""), -- nf-fa-columns
}

---`icon .. " " .. text`, or bare `text` when no icon resolved.
---@param icon string
---@param text string
---@return string
local function prefix(icon, text)
  if icon == "" then
    return text
  end
  return icon .. " " .. text
end

-----------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------

---Filter list based on argument
---@param arg string
---@param list string[]
---@return string[]
local function filter(arg, list)
  if not arg or arg == "" then
    return list
  end

  local filtered = {}
  local lower_arg = arg:lower()

  for _, item in ipairs(list) do
    if item:lower():find(lower_arg, 1, true) == 1 then
      table.insert(filtered, item)
    end
  end

  return filtered
end

---Open a choice over a closed set of names, the current one marked and
---preselected; a pick hands the name to `on_pick`, a cancel does nothing.
---Uses `ui.kit.select` (which defers to a user-installed `vim.ui.select`
---override via `respect_override`) and falls back to `vim.ui.select` itself
---when the kit cannot be loaded.
---
---The pick arrives later, from the picker's own callback, outside the
---`pcall` that `run()` puts around the command itself -- so it gets its own
---here: an error while switching is reported like one from the named form
---(`UI <sub> error: ...`) instead of escaping raw out of the picker's keymap.
---@param sub string  # the subcommand, for the error message
---@param title string
---@param names string[]
---@param current string|nil
---@param on_pick fun(name: string)
local function choose(sub, title, names, current, on_pick)
  local initial
  for i, name in ipairs(names) do
    if name == current then
      initial = i
    end
  end

  local function format_item(name)
    return ((name == current) and "✓ " or "  ") .. name
  end

  local function pick(name)
    local ok, err = pcall(on_pick, name)
    if not ok then
      notify.error(("UI %s error: %s"):format(sub, tostring(err)))
    end
  end

  local ok, kit_select = pcall(require, "ui.kit.select")
  if ok and type(kit_select) == "table" and type(kit_select.open) == "function" then
    kit_select.open({
      title = title,
      items = names,
      format_item = format_item,
      initial_index = initial,
      respect_override = true,
      on_select = function(name)
        pick(name)
      end,
    })
    return
  end

  vim.ui.select(names, { prompt = title, format_item = format_item }, function(name)
    if name ~= nil then
      pick(name)
    end
  end)
end

-----------------------------------------------------------------------
-- Actions
-----------------------------------------------------------------------

---Handle transparency command
---@param args string[]
local function ui_transparency(args)
  local action = args[2]

  if action == "on" then
    local success = theme.set_transparency(true)
    if success then
      notify.info(prefix(ICON.magic, "Transparency enabled"))
    end
    return
  end

  if action == "off" then
    local success = theme.set_transparency(false)
    if success then
      notify.info(prefix(ICON.magic, "Transparency disabled"))
    end
    return
  end

  -- Toggle
  local new_state = theme.toggle_transparency()
  notify.info(prefix(ICON.magic, ("Transparency %s"):format(new_state and "enabled" or "disabled")))
end

---Handle screenkey command -- the in-editor keystroke HUD, off by default
---(see `ui.screenkey`'s own doc comment for why). `on`/`off` set an explicit
---state, matching `ui_transparency` above; no argument toggles, matching
---`:UI toggle`'s own naming for "the state-flip subcommand".
---@param args string[]
local function ui_screenkey(args)
  local action = args[2]

  if action == "on" then
    screenkey.enable()
    notify.info(prefix(ICON.keyboard, "Screenkey enabled"))
    return
  end

  if action == "off" then
    screenkey.disable()
    notify.info(prefix(ICON.keyboard, "Screenkey disabled"))
    return
  end

  local now_enabled = screenkey.toggle()
  notify.info(
    prefix(ICON.keyboard, ("Screenkey %s"):format(now_enabled and "enabled" or "disabled"))
  )
end

---Handle color command -- the interactive colour picker (`ui.colorpicker`).
---An optional `#hex` argument is the start colour; without one the picker
---opens on the `#hex` under the cursor, or on its default.
---@param args string[]
local function ui_color(args)
  local hex = args[2]
  if hex and not require("ui.colorpicker.color").valid(hex) then
    notify.warn(prefix(ICON.color, ("not a colour: %s (expected #rrggbb)"):format(hex)))
    return
  end
  if not colorpicker.open({ hex = hex }) then
    notify.warn(prefix(ICON.color, "could not open the colour picker"))
  end
end

---Handle zen command -- the distraction-free box (`ui.zen`). `on`/`off`
---set an explicit state, no argument toggles.
---@param args string[]
local function ui_zen(args)
  local action = args[2]
  if action == "on" then
    zen.open()
    return
  end
  if action == "off" then
    zen.close()
    return
  end
  local now_open = zen.toggle()
  if not now_open then
    notify.info(prefix(ICON.zen, "Zen off"))
  end
end

---Handle winpick command -- pick a window by letter (`ui.windowpicker`) and
---jump to it. A no-op (nothing happens, no error) when nothing qualifies or
---the pick is cancelled.
---@param _ string[]
local function ui_winpick(_)
  local win = windowpicker.pick()
  if win then
    vim.api.nvim_set_current_win(win)
  end
end

---Handle notify command -- `vim.notify` as toasts with a history
---(`ui.notify`). `on`/`off` set an explicit state, `history` opens the
---viewer, `clear` forgets the recorded entries, no argument toggles.
---@param args string[]
local function ui_notify_cmd(args)
  local action = args[2]
  if action == "on" then
    ui_notify.enable()
    notify.info(prefix(ICON.bell, "Notify toasts enabled"))
    return
  end
  if action == "off" then
    ui_notify.disable()
    notify.info(prefix(ICON.bell, "Notify toasts disabled"))
    return
  end
  if action == "history" then
    ui_notify.show_history()
    return
  end
  if action == "clear" then
    ui_notify.clear_history()
    notify.info(prefix(ICON.bell, "Notification history cleared"))
    return
  end
  local now = ui_notify.toggle()
  notify.info(prefix(ICON.bell, ("Notify toasts %s"):format(now and "enabled" or "disabled")))
end

---Handle keys command -- the mappings under a prefix as a menu
---(`ui.keys`). The prefix is everything after `keys`, joined back with
---spaces, so `:UI keys <leader>s` and `:UI keys <C-w>` both work; no
---argument uses the configured default prefix.
---@param args string[]
local function ui_keys_cmd(args)
  local arg = table.concat(vim.list_slice(args, 2), " ")
  if not ui_keys.open(arg ~= "" and arg or nil) then
    notify.info(
      prefix(ICON.keyboard, "no mappings under " .. (arg ~= "" and arg or "the default prefix"))
    )
  end
end

---Handle slots command -- numbered action slots (`ui.slots`). Loaded on the
---first use, so a session that never types it never loads the module.
---@param args string[]
local function ui_slots_cmd(args)
  require("ui.slots").command(args)
end

---@param s string|nil
---@return integer|nil # `s` as a whole number, nil for anything else
local function whole_number(s)
  local n = tonumber(s)
  if n and n == math.floor(n) then
    return n
  end
  return nil
end

---Handle sticky command (also spelled `context`) -- the sticky code-context
---overlay, off by default (see `ui.context`'s own doc comment).
---
---  `on`/`off`        set an explicit state; no argument (or `toggle`) toggles
---  `status`          state, heading depth and row cap
---  `depth [1-6]`     the deepest Markdown heading level that gets pinned
---  `lines [ft] [n]`  how many rows the context may take, for one filetype or
---                    for the default; 0 = unlimited
---  `up [n]`          jump the cursor to the n-th enclosing scope above the top
---                    of the window (1 = innermost) -- works with the overlay
---                    off as well, it only needs the parser
---
---  `reset`           drop what `depth`/`lines` changed, back to the configured values
---
---`depth`/`lines` change the running session; with `persist = true` in the
---`ui.setup({ context = { ... } })` table they are also saved and come back at
---the next start (`reset` deletes them). The configured form of the same values
---is `ui.setup({ context = { headings = { max_level = N }, max_lines = ... } })`.
---@param args string[]
local function ui_sticky(args)
  local action = args[2]
  local cfg = context.config()

  ---How a `depth`/`lines` change is kept, for the message that reports it. `saved`
  ---is what actually happened: with `persist` on and a write that failed, the
  ---value is still session-only.
  ---@return string
  local function kept()
    if context.is_saved() then
      return "saved"
    end
    return context.is_persisting() and "this session only, saving failed" or "this session only"
  end

  ---@return string
  local function keep_note()
    if context.is_saved() then
      return " -- saved for the next start"
    end
    return context.is_persisting() and " -- this session only: saving failed (see the warning)"
      or " -- this session only (`persist = true` keeps it)"
  end

  if action == "on" then
    context.enable()
    notify.info(prefix(ICON.context, "Sticky context enabled"))
    return
  end

  if action == "off" then
    context.disable()
    notify.info(prefix(ICON.context, "Sticky context disabled"))
    return
  end

  if action == "status" then
    local changed = context.describe_overrides()
    notify.info(
      prefix(
        ICON.context,
        ("Sticky context %s -- depth %d (deepest Markdown heading), lines %s%s"):format(
          context.is_enabled() and "on" or "off",
          cfg.headings.max_level,
          context.describe_max_lines(),
          changed and (" -- set by command: %s, %s"):format(changed, kept()) or ""
        )
      )
    )
    return
  end

  if action == "reset" then
    local had = context.reset()
    notify.info(
      prefix(
        ICON.context,
        had
            and ("Depth and lines back to the configured values (%d, %s)"):format(
              cfg.headings.max_level,
              context.describe_max_lines()
            )
          or "Nothing to reset -- depth and lines are still as configured"
      )
    )
    return
  end

  if action == "depth" then
    if args[3] == nil then
      notify.info(
        prefix(
          ICON.context,
          ("Depth: Markdown headings down to level %d"):format(cfg.headings.max_level)
        )
      )
      return
    end
    local level = args[3] == "all" and 6 or whole_number(args[3])
    if not level or level < 1 or level > 6 then
      notify.warn(prefix(ICON.context, "Usage: :UI sticky depth <1-6|all>"))
      return
    end
    notify.info(
      prefix(
        ICON.context,
        ("Depth: Markdown headings down to level %d%s"):format(
          context.set_max_level(level),
          keep_note()
        )
      )
    )
    return
  end

  if action == "lines" then
    -- `lines <n>` or `lines <filetype> <n>`; bare `lines` shows the current cap
    if args[3] == nil then
      notify.info(prefix(ICON.context, ("Lines: %s"):format(context.describe_max_lines())))
      return
    end
    local ft = args[4] ~= nil and args[3] or nil
    local n = whole_number(args[4] ~= nil and args[4] or args[3])
    if not n or not context.set_max_lines(n, ft) then
      notify.warn(prefix(ICON.context, "Usage: :UI sticky lines [filetype] <n>  (0 = unlimited)"))
      return
    end
    notify.info(
      prefix(ICON.context, ("Lines: %s%s"):format(context.describe_max_lines(), keep_note()))
    )
    return
  end

  if action == "up" then
    local n = tonumber(args[3]) or 1
    if not context.go_to_context(n) then
      notify.warn(prefix(ICON.context, "No enclosing context above the top of this window"))
    end
    return
  end

  if action ~= nil and action ~= "toggle" then
    notify.warn(prefix(ICON.context, ("Unknown sticky action '%s' -- see :UI help"):format(action)))
    return
  end

  local now_enabled = context.toggle()
  notify.info(
    prefix(ICON.context, ("Sticky context %s"):format(now_enabled and "enabled" or "disabled"))
  )
end

---Handle theme command
---@param args string[]
local function ui_theme(args)
  local theme_name = args[2]

  if not theme_name or theme_name == "" then
    -- Show current theme if no argument
    local current = theme.get_current_theme()
    if current then
      notify.info(string.format("Aktuelles Theme: %s\nNutze :UI theme <name> zum Ändern", current))
    else
      notify.warn("Kein Theme konfiguriert")
    end
    return
  end

  -- Validate theme exists
  if not theme.theme_exists(theme_name) then
    local available = theme.list_themes()
    local available_str = table.concat(available, ", ")
    notify.error(
      string.format("Theme '%s' not found.\n\nAvailable themes:\n%s", theme_name, available_str)
    )
    return
  end

  -- Load theme
  local success = theme.load_theme(theme_name)

  if success then
    notify.info(prefix(ICON.theme, ("Theme changed to: %s"):format(theme_name)))
  else
    notify.error(("Failed to load theme '%s'"):format(theme_name))
  end
end

---Handle themes list command
---@param _args string[] # Unused: these subcommands take no argument
local function ui_themes(_args)
  local themes = theme.list_themes()
  local current = theme.get_current_theme()

  if #themes == 0 then
    notify.error("No themes found!")
    return
  end

  -- Format themes list with current marker
  local lines = { ("Available themes (%d):"):format(#themes), "" }

  for _, theme_name in ipairs(themes) do
    local marker = (theme_name == current) and "✓ " or "  "
    table.insert(lines, marker .. theme_name)
  end

  notify.info(table.concat(lines, "\n"))
end

---Handle status command
---@param _args string[] # Unused: these subcommands take no argument
local function ui_status(_args)
  local info = theme.get_info()
  local variant = require("ui.config").get_variant()
  local tabline_cfg = require("ui.tabline.render").current()
  local tabline_style = (tabline_cfg and tabline_cfg.style) or "rounded"

  local lines = {
    "╭─ UI Status ─────────────────╮",
    string.format("│ Theme:        %-15s │", info.theme or "none"),
    string.format("│ Transparency: %-15s │", info.transparency and "on" or "off"),
    string.format("│ Variant:      %-15s │", variant or "(unnamed)"),
    string.format("│ Tabline style:%-15s │", tabline_style),
  }

  if info.toggle_themes and #info.toggle_themes > 0 then
    local toggle_str = table.concat(info.toggle_themes, ", ")
    if #toggle_str > 15 then
      toggle_str = toggle_str:sub(1, 12) .. "..."
    end
    lines[#lines + 1] = string.format("│ Toggle:       %-15s │", toggle_str)
  end

  lines[#lines + 1] =
    "╰─────────────────────────────╯"

  notify.info(table.concat(lines, "\n"))
end

---Switch the active statusline variant and make it render immediately.
---`ui.config.setup()` only assembles a config; `ui.statusline.render.enable()`
---is the separate step that actually points `vim.o.statusline` at it -- both
---are needed for a runtime switch to be visible, not just recorded.
---@param name string
---@return boolean success
local function switch_variant(name)
  local variants = require("ui.config.variants")
  if not variants.exists(name) then
    return false
  end

  local ok, assembled = pcall(require("ui.config").setup, { variant = name })
  if not ok then
    return false
  end

  -- `render.enable()`'s `cfg` is non-optional (Ui.Statusline.Config), but a
  -- host-registered variant shaped `{ statusline = {...} }` instead of
  -- `{ ui = { statusline = {...} } }` makes `assembled.ui.statusline` nil --
  -- enable(nil) would blank the statusline with no error anywhere. Fail the
  -- switch instead of reporting success for it (PRIN-20).
  local stl_cfg = assembled.ui and assembled.ui.statusline
  if not stl_cfg then
    return false
  end

  require("ui.statusline.render").enable(stl_cfg)
  return true
end

---Handle variant command
---@param args string[]
local function ui_variant(args)
  local name = args[2]
  local variants = require("ui.config.variants")

  if not name or name == "" then
    local current = require("ui.config").get_variant()
    choose("variant", "Statusline variant", variants.list(), current, function(pick)
      ui_variant({ args[1], pick })
    end)
    return
  end

  if not variants.exists(name) then
    notify.error(
      string.format(
        "Variant '%s' not found.\n\nAvailable variants:\n%s",
        name,
        table.concat(variants.list(), ", ")
      )
    )
    return
  end

  if switch_variant(name) then
    notify.info(prefix(ICON.theme, ("Statusline variant changed to: %s"):format(name)))
  else
    notify.error(("Failed to switch to variant '%s'"):format(name))
  end
end

---Handle variants list command
---@param _args string[] # Unused: this subcommand takes no argument
local function ui_variants(_args)
  local variants = require("ui.config.variants")
  local names = variants.list()
  local current = require("ui.config").get_variant()

  local lines = { ("Available statusline variants (%d):"):format(#names), "" }

  for _, name in ipairs(names) do
    local marker = (name == current) and "✓ " or "  "
    table.insert(lines, marker .. name)
  end

  notify.info(table.concat(lines, "\n"))
end

---Switch the active tabline style and force an immediate redraw. Unlike
---`switch_variant` above, there is no separate `setup()` step: `cfg.style`
---is one field of the single already-`enable()`d tabline config, mutated
---in place on the same table `ui.tabline.render.current()` returns --
---`render()` reads that table fresh on every redraw, so `redrawtabline`
---alone is enough to make the change visible.
---@param name string
---@return boolean success
local function switch_tabline_style(name)
  local styles = require("ui.tabline.styles")
  if not styles.exists(name) then
    return false
  end

  local cfg = require("ui.tabline.render").current()
  if not cfg then
    return false
  end

  cfg.style = name
  vim.cmd("redrawtabline")
  return true
end

---Handle tabline-style command
---@param args string[]
local function ui_tabline_style(args)
  local name = args[2]
  local styles = require("ui.tabline.styles")

  if not name or name == "" then
    local cfg = require("ui.tabline.render").current()
    -- Without an enabled tabline every pick would fail (see
    -- `switch_tabline_style`), so say that now instead of offering a choice
    -- that cannot switch anything.
    if not cfg then
      notify.error("The tabline is not enabled, so there is no style to switch")
      return
    end
    local current = cfg.style or "rounded"
    choose("tabline-style", "Tabline style", styles.list(), current, function(pick)
      ui_tabline_style({ args[1], pick })
    end)
    return
  end

  if not styles.exists(name) then
    notify.error(
      string.format(
        "Tabline style '%s' not found.\n\nAvailable styles:\n%s",
        name,
        table.concat(styles.list(), ", ")
      )
    )
    return
  end

  if switch_tabline_style(name) then
    notify.info(prefix(ICON.theme, ("Tabline style changed to: %s"):format(name)))
  else
    notify.error(
      string.format("Failed to switch to tabline style '%s' (tabline not enabled yet?)", name)
    )
  end
end

---Handle tabline-styles list command
---@param _args string[] # Unused: this subcommand takes no argument
local function ui_tabline_styles(_args)
  local styles = require("ui.tabline.styles")
  local names = styles.list()
  local cfg = require("ui.tabline.render").current()
  local current = (cfg and cfg.style) or "rounded"

  local lines = { string.format("Verfügbare Tabline-Styles (%d):", #names), "" }

  for _, name in ipairs(names) do
    local marker = (name == current) and "✓ " or "  "
    table.insert(lines, marker .. name)
  end

  notify.info(table.concat(lines, "\n"))
end

---Handle kit-preset command: switches `ui.kit.theme`'s active default --
---the border/color preset (`rounded`/`solid`/`double`/`ascii`/`minimal`/
---`menu`/...) that every `ui.kit` surface (popup, toast, menu, viewer,
---confirm, chooser, chip, the statusline hover tooltip, ...) resolves
---through. Unlike `:UI theme` (the colorscheme) or `:UI tabline-style`
---(chip boundary shape), nothing surfaced this one interactively before --
---`ui.kit.theme.setup({ default = ... })` from Lua was the only way in.
---
---Best-effort "combined look" switch: when a `ui.tabline.styles` entry of
---the SAME name is also registered (e.g. a future "ascii"/"hacker" preset
---that ships a matching tabline style), that switches too, in one command --
---see `switch_tabline_style`. Silently skipped when no such style exists
---(true for every kit preset today), so this never errors over a kit-only
---preset.
---@param args string[]
local function ui_kit_preset(args)
  local kit_theme = require("ui.kit.theme")
  local name = args[2]

  if not name or name == "" then
    choose("kit-preset", "Kit preset", kit_theme.presets(), kit_theme.default(), function(pick)
      ui_kit_preset({ args[1], pick })
    end)
    return
  end

  if not vim.tbl_contains(kit_theme.presets(), name) then
    notify.error(
      string.format(
        "Kit preset '%s' not found.\n\nAvailable presets:\n%s",
        name,
        table.concat(kit_theme.presets(), ", ")
      )
    )
    return
  end

  kit_theme.setup({ default = name })
  local also_tabline = switch_tabline_style(name)
  notify.info(
    prefix(
      ICON.theme,
      ("Kit preset changed to: %s%s"):format(
        name,
        also_tabline and " (tabline style matched too)" or ""
      )
    )
  )
end

---List every registered kit preset -- see `ui_kit_preset`'s own doc comment
---for what it controls.
---@param _args string[] # Unused: this subcommand takes no argument
local function ui_kit_presets(_args)
  local kit_theme = require("ui.kit.theme")
  local names = kit_theme.presets()
  local current = kit_theme.default()

  local lines = { string.format("Available kit presets (%d):", #names), "" }
  for _, name in ipairs(names) do
    local marker = (name == current) and "* " or "  "
    lines[#lines + 1] = marker .. name
  end

  notify.info(table.concat(lines, "\n"))
end

---Open the visual theme picker
---@param _args string[] # Unused: this subcommand takes no argument
local function ui_picker(_args)
  theme_picker.open()
end

---List every catalogued statusline segment -- see ui.statusline.catalog's
---own doc comment for what "catalogued" excludes and why.
---@param _args string[] # Unused: this subcommand takes no argument
local function ui_modules(_args)
  local catalog = require("ui.statusline.catalog")

  local builtin, standalone = {}, {}
  for _, entry in ipairs(catalog) do
    table.insert(entry.builtin and builtin or standalone, entry)
  end

  ---@param entry Ui.Statusline.CatalogEntry
  ---@return string
  local function format_entry(entry)
    local wiring = (#entry.used_by > 0) and ("in " .. table.concat(entry.used_by, ", "))
      or "opt-in only"
    local dep = entry.requires and (" [needs " .. entry.requires .. "]") or ""
    return ("  %-20s %s%s (%s)"):format(entry.key, entry.summary, dep, wiring)
  end

  local lines = {
    ('Built into the "default" theme -- add the key to any preset\'s `order` (%d):'):format(
      #builtin
    ),
    "",
  }
  for _, entry in ipairs(builtin) do
    lines[#lines + 1] = format_entry(entry)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = ("Standalone modules -- add the key to `order` plus a `modules` entry (%d):"):format(
    #standalone
  )
  lines[#lines + 1] = ""
  for _, entry in ipairs(standalone) do
    lines[#lines + 1] = format_entry(entry)
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Full wiring snippets: docs/modules.md in the ui.nvim repo."

  notify.info(table.concat(lines, "\n"))
end

---Popup view of whatever `lib.nvim.progress`'s "statusline" style is
---currently tracking -- the same registry `ui.statusline.modules
---.plugin_progress` renders inline and hovering that module already surfaces
---(see `ui.statusline.hover`'s `live` support), but reachable on demand
---without a mouse or a narrow statusline segment doing the truncating.
---@param _args string[]
local function ui_progress(_args)
  local ok, sl = pcall(require, "lib.nvim.progress.styles.statusline")
  if not ok then
    notify.warn("lib.nvim.progress not available")
    return
  end

  local active = sl.active() -- string[], oldest first
  if #active == 0 then
    notify.info("No plugin operation is currently running.")
    return
  end

  local lines = { ("%d operation(s) in progress:"):format(#active), "" }
  for _, text in ipairs(active) do
    lines[#lines + 1] = "  " .. text
  end

  notify.info(table.concat(lines, "\n"))
end

---Toggle between configured themes
---@param _args string[] # Unused: these subcommands take no argument
local function ui_toggle(_args)
  local next_theme = theme.toggle_theme()

  if next_theme then
    notify.info(prefix(ICON.theme, ("Theme changed to: %s"):format(next_theme)))
  else
    notify.warn("No theme_toggle configured.\n" .. "Add at least two themes to theme_toggle.")
  end
end

-- The route table is built below the handlers (it points at them), and `help_text`
-- reads it: the long help is generated from the routes, so it cannot drift from
-- what `:UI` offers (it used to be a second, hand-kept list next to the route texts).
---@type Lib.UserCmd.Composer.Route[]
local ROUTES

---`:UI sub [optional] <required> variadic...` for one route.
---@param route Lib.UserCmd.Composer.Route
---@return string
local function usage(route)
  local parts = { ":UI " .. table.concat(route.path, " ") }
  for _, arg in ipairs(route.args or {}) do
    local name = arg.variadic and (arg.name .. "...") or arg.name
    parts[#parts + 1] = arg.optional and ("[" .. name .. "]") or ("<" .. name .. ">")
  end
  return table.concat(parts, " ")
end

---The long help text of `:UI help`, generated from `ROUTES`: one row per route, one
---more per documented value of an argument (`enum_desc`), and the argument text where
---there is no per-value text (the slots subcommands).
---@return string
local function help_text()
  local rows = {} ---@type string[][]
  local width = 0
  local function add(left, right)
    rows[#rows + 1] = { left, right }
    width = math.max(width, vim.fn.strdisplaywidth(left))
  end

  for _, route in ipairs(ROUTES) do
    local base = ":UI " .. table.concat(route.path, " ")
    add(usage(route), route.desc or "")
    for _, arg in ipairs(route.args or {}) do
      if arg.enum_desc then
        -- The order of `values` when the arg has them; the words of a custom type
        -- (the slots subcommands) are listed alphabetically.
        local order = arg.values
        if not order then
          order = vim.tbl_keys(arg.enum_desc)
          table.sort(order)
        end
        for _, value in ipairs(order) do
          if arg.enum_desc[value] then
            add(("  %s %s"):format(base, value), arg.enum_desc[value])
          end
        end
      elseif arg.desc then
        add(("    %s"):format(arg.name), arg.desc)
      end
    end
  end
  add(":Theme [name]", "Shortcut for :UI theme")

  local lines = { "UI Command Help (a bare :UI opens the option float)", "" }
  for _, row in ipairs(rows) do
    local pad = (" "):rep(width - vim.fn.strdisplaywidth(row[1]) + 2)
    lines[#lines + 1] = "  " .. row[1] .. pad .. row[2]
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "See also: ui/bindings/usrcmds/themes/README.md for technical details"
  return table.concat(lines, "\n")
end

---Show help information
---@param _args string[] # Unused: these subcommands take no argument
local function ui_help(_args)
  notify.info(help_text())
end

---The text `:UI help` prints (generated from the routes).
---@return string
function M.help_text()
  return help_text()
end

-----------------------------------------------------------------------
-- The verbs (lib.nvim composer)
-----------------------------------------------------------------------

-- `:UI` and `:Theme` are composer verbs: the route tree is the one source for the
-- dispatch, `<Tab>` completion, the usage text and the help float (the cheatsheet
-- key, or a bare `:UI`). The handlers above are unchanged and still read the words the
-- user typed (`fargs`, `args[1]` is the subcommand), so every subcommand keeps
-- its own validation and messages. The `values` of an argument are completion
-- hints only (never enforced), for the same reason.

local composer = require("lib.nvim.bindings.usercmd.composer")

---Words of the command line as the old completion read them.
---@param cmdline string
---@param arglead string
---@return string[] parts
---@return integer num_args  # words after `:UI`, counting the one being completed
---@return string arglead
local function words(cmdline, arglead)
  local parts = {}
  for part in cmdline:gmatch("%S+") do
    parts[#parts + 1] = part
  end
  local num_args = #parts - 1
  if cmdline:match("%s$") then
    num_args = num_args + 1
    arglead = ""
  end
  return parts, num_args, arglead
end

---@param name string
---@param desc string
---@param list fun(): string[]
local function list_type(name, desc, list)
  composer.register_type(name, {
    desc = desc,
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(lead)
      return filter(lead, list())
    end,
  })
end

-- The argument types go into lib.nvim's process-wide type registry, so they are
-- written by `setup()` (once `:UI` is wanted), not as a side effect of `require`.
---@return nil
local function register_types()
  list_type("UI_THEME", "Name of an installed colorscheme", function()
    return theme.list_themes()
  end)
  -- The registries, not static lists: a host's own `register(name, ...)` shows up
  -- the moment it runs, same as the shipped entries.
  list_type("UI_VARIANT", "Name of a statusline variant", function()
    return require("ui.config.variants").list()
  end)
  list_type("UI_TABLINE_STYLE", "Name of a tabline style", function()
    return require("ui.tabline.styles").list()
  end)
  list_type("UI_KIT_PRESET", "Name of a popup/toast preset", function()
    return require("ui.kit.theme").presets()
  end)

  -- `:UI slots` takes a subcommand or a slot number, then slot numbers.
  composer.register_type("UI_SLOT_WORD", {
    desc = "A slots subcommand or the number of a slot",
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(lead, _, cmdline)
      local parts, num_args, arglead = words(cmdline or "", lead)
      if num_args <= 2 then
        return require("ui.slots").complete(arglead, nil, 1)
      end
      return require("ui.slots").complete(arglead, parts[3], num_args - 1)
    end,
  })

  -- The word after `sticky depth` / `sticky lines`.
  composer.register_type("UI_STICKY_WORD", {
    desc = "A depth level (sticky depth) or a filetype (sticky lines)",
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(lead, _, cmdline)
      local parts, num_args, arglead = words(cmdline or "", lead)
      if num_args == 3 and parts[3] == "depth" then
        return filter(arglead, { "1", "2", "3", "4", "5", "6", "all" })
      end
      if num_args == 3 and parts[3] == "lines" then
        return filter(arglead, vim.fn.getcompletion("", "filetype"))
      end
      return {}
    end,
  })
end

---A route's handler: the legacy `ui_*` function with the words as typed, the way
---the old dispatcher ran it (errors are told, not thrown).
---@param fn fun(args: string[])
---@return fun(ctx: Lib.UserCmd.Composer.Ctx)
local function run(fn)
  return function(ctx)
    local fargs = ctx.raw and ctx.raw.fargs or {}
    local ok, err = pcall(fn, fargs)
    if not ok then
      notify.error(("UI %s error: %s"):format(tostring(fargs[1]), tostring(err)))
    end
  end
end

---@param extra table|nil  # `args` (and any other route field)
---@param name string
---@param fn fun(args: string[])
---@param desc string
local function route(name, fn, desc, extra)
  return vim.tbl_extend("force", { path = { name }, desc = desc, run = run(fn) }, extra or {})
end

---@param desc string
---@return Lib.UserCmd.Composer.ArgSpec
local function on_off(desc)
  return {
    name = "state",
    type = "STRING",
    optional = true,
    values = { "on", "off" },
    desc = desc,
    enum_desc = { on = "Enable", off = "Disable" },
  }
end

-- Built per route (not one table both sticky routes point at): a change to the
-- args of one route must not show up in the other.
---@return Lib.UserCmd.Composer.ArgSpec[]
local function sticky_args()
  return {
    {
      name = "action",
      type = "STRING",
      optional = true,
      desc = "What to do; without it the sticky context is toggled",
      values = { "on", "off", "toggle", "status", "depth", "lines", "reset", "up" },
      enum_desc = {
        on = "Enable",
        off = "Disable",
        toggle = "Switch",
        status = "Show state, depth and lines",
        depth = "Deepest heading pinned (1-6 or all)",
        lines = "Row cap per filetype (0 = unlimited)",
        reset = "Back to the configured values",
        up = "Jump to the n-th scope",
      },
    },
    {
      name = "a",
      type = "UI_STICKY_WORD",
      optional = true,
      desc = "depth: the level; lines: a filetype or the row cap; up: the n-th scope",
    },
    { name = "b", type = "STRING", optional = true, desc = "lines: the row cap after a filetype" },
  }
end

ROUTES = {
  route("transparency", ui_transparency, "Toggle transparency (on/off to set it)", {
    args = { on_off("Set transparency instead of toggling") },
  }),
  route("screenkey", ui_screenkey, "Toggle the screenkey HUD", {
    args = { on_off("Set the HUD instead of toggling") },
  }),
  route("sticky", ui_sticky, "The sticky context: toggle, depth, line cap, jump", {
    args = sticky_args(),
  }),
  route("context", ui_sticky, "Same command as sticky, older name", { args = sticky_args() }),
  route("color", ui_color, "Open the colour picker, optionally on a colour", {
    args = { { name = "hex", type = "STRING", optional = true, desc = "Start colour, #rrggbb" } },
  }),
  route("zen", ui_zen, "Toggle the zen box", { args = { on_off("Enter or leave zen") } }),
  route("winpick", ui_winpick, "Pick a window by letter and jump to it"),
  route("notify", ui_notify_cmd, "Toggle notify toasts, open or clear the history", {
    args = {
      {
        name = "action",
        type = "STRING",
        optional = true,
        desc = "What to do; without it the toasts are toggled",
        values = { "on", "off", "history", "clear" },
        enum_desc = {
          on = "Enable toasts",
          off = "Disable toasts",
          history = "Open the history",
          clear = "Forget the history",
        },
      },
    },
  }),
  route("keys", ui_keys_cmd, "List the mappings under a prefix", {
    args = {
      {
        name = "prefix",
        type = "STRING",
        optional = true,
        variadic = true,
        desc = "Key prefix such as <leader>; the default prefix when left out",
      },
    },
  }),
  route("slots", ui_slots_cmd, "Numbered slots: list, run, add, edit, move, clear, panel, bar", {
    args = {
      {
        name = "word",
        type = "UI_SLOT_WORD",
        optional = true,
        variadic = true,
        desc = "A subcommand or a slot number to run",
        enum_desc = {
          list = "List the slots",
          add = "Current file -> slot",
          yank = "Copy what a slot is",
          clear = "Empty a slot (or all)",
          move = "Move or swap two slots",
          kinds = "List the slot kinds",
          toggle = "Show/hide the slot bar",
          open = "Show the slot bar",
          close = "Hide the slot bar",
          panel = "Slot panel (work in it)",
          edit = "Add or change a slot",
        },
      },
    },
  }),
  route("theme", ui_theme, "Show the current colorscheme, or switch to one", {
    args = { { name = "name", type = "UI_THEME", optional = true } },
  }),
  route("themes", ui_themes, "List every colorscheme, the active one marked"),
  route("variant", ui_variant, "Pick a statusline variant from a list, or switch to one", {
    args = { { name = "name", type = "UI_VARIANT", optional = true } },
  }),
  route("variants", ui_variants, "List all statusline variants"),
  route("tabline-style", ui_tabline_style, "Pick a tabline style from a list, or switch to one", {
    args = { { name = "name", type = "UI_TABLINE_STYLE", optional = true } },
  }),
  route("tabline-styles", ui_tabline_styles, "List all tabline styles"),
  route("kit-preset", ui_kit_preset, "Pick or switch the popup/toast border and colors", {
    args = { { name = "name", type = "UI_KIT_PRESET", optional = true } },
  }),
  route("kit-presets", ui_kit_presets, "List all popup/toast presets"),
  route("picker", ui_picker, "Open the visual theme picker with live preview"),
  route("modules", ui_modules, "List the available statusline segments"),
  route("progress", ui_progress, "Show what is running now"),
  route("toggle", ui_toggle, "Switch between the two configured themes"),
  route("status", ui_status, "Show the current UI configuration"),
  route("help", ui_help, "Print the long help text"),
}

-----------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------

---@return nil
function M.setup()
  -- `ui.kit` registers nothing when required (LUA-92), so its playground
  -- command comes in with the rest of the commands. The `require` is inside
  -- the protected call too: `pcall(require(...).f)` evaluates the `require`
  -- before `pcall` runs, so a module that fails to load would abort the
  -- setup and take `:UI` and `:Theme` with it.
  pcall(function()
    require("ui.kit.preview").ensure_command()
  end)

  register_types()

  composer.verb("UI", {
    desc = "UI Kontrolle (Theme, Transparenz, Varianten, Tabline-Stil, ... -- siehe :UI help)",
    help = true,
    routes = ROUTES,
  })

  composer.verb("Theme", {
    desc = "Theme ändern (Shortcut für :UI theme)",
    help = true,
    routes = {
      {
        path = {},
        desc = "Show the current colorscheme, or switch to one",
        args = { { name = "name", type = "UI_THEME", optional = true } },
        run = run(function(fargs)
          ui_theme({ "theme", fargs[1] })
        end),
      },
    },
  })
end

return M
