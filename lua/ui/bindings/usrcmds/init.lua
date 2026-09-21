---@module 'ui.bindings.usrcmds'
---Provides :UI usercommand for runtime UI configuration (theme, transparency).

local notify = require("lib.nvim.notify").create("[ui.bindings.usrcmds]")
local usercmd = require("lib.nvim.bindings.usercmd")

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
    notify.info(
      string.format(
        "Current variant: %s\nUse :UI variant <name> to switch",
        current or "(unnamed -- passed directly as a table)"
      )
    )
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
    local current = (cfg and cfg.style) or "rounded"
    notify.info(
      string.format("Current tabline style: %s\nUse :UI tabline-style <name> to switch", current)
    )
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

---Show help information
---@param _args string[] # Unused: these subcommands take no argument
local function ui_help(_args)
  local help_text = [[
╭─ UI Command Help ────────────────────────────────────╮
│                                                      │
│  :UI transparency           Toggle transparency      │
│  :UI transparency on        Enable transparency      │
│  :UI transparency off       Disable transparency     │
│                                                      │
│  :UI screenkey              Toggle the screenkey HUD │
│  :UI screenkey on           Enable screenkey         │
│  :UI screenkey off          Disable screenkey        │
│                                                      │
│  :UI sticky                 Toggle the sticky context│
│  :UI sticky on|off          Explicit state           │
│  :UI sticky status          Show state, depth, lines │
│  :UI sticky depth [1-6]     Deepest heading pinned   │
│  :UI sticky lines [ft] [n]  Row cap (0 = unlimited)  │
│  :UI sticky reset           Back to configured values│
│  :UI sticky up [n]          Jump to the n-th scope   │
│  :UI context ...            Same command, older name │
│                                                      │
│  :UI color [#hex]           Open the colour picker   │
│                                                      │
│  :UI zen                    Toggle the zen box       │
│  :UI zen on                 Enter zen                │
│  :UI zen off                Leave zen                │
│                                                      │
│  :UI winpick                Pick a window by letter, │
│                             jump to it               │
│                                                      │
│  :UI notify                 Toggle notify toasts     │
│  :UI notify on|off          Explicit state           │
│  :UI notify history         Open the history         │
│  :UI notify clear           Forget the history       │
│                                                      │
│  :UI keys [prefix]          Mappings under a prefix  │
│                                                      │
│  :UI theme                  Show the current theme   │
│  :UI theme <name>           Set a theme              │
│  :UI themes                 List all themes          │
│  :UI picker                 Open the visual theme    │
│                             picker (live preview)    │
│  :UI toggle                 Switch between themes    │
│                                                      │
│  :UI variant                Show the current variant │
│  :UI variant <name>         Switch variant           │
│  :UI variants               List all variants        │
│                                                      │
│  :UI tabline-style          Show the current style   │
│  :UI tabline-style <name>   Switch tabline style     │
│  :UI tabline-styles         List all styles          │
│                                                      │
│  :UI modules                List available segments  │
│  :UI status                 Show the current config  │
│  :UI help                   Show this help           │
│                                                      │
╰──────────────────────────────────────────────────────╯

See also: ui/bindings/usrcmds/themes/README.md for technical details
]]
  notify.info(help_text)
end

-----------------------------------------------------------------------
-- Subcommand registry
-----------------------------------------------------------------------

-- Single source of truth for both the dispatcher and completion() below,
-- so a new subcommand can't be wired into one without the other.
local SUBCOMMANDS = {
  { name = "transparency", fn = ui_transparency },
  { name = "screenkey", fn = ui_screenkey },
  { name = "sticky", fn = ui_sticky },
  { name = "context", fn = ui_sticky }, -- the older name; same command
  { name = "color", fn = ui_color },
  { name = "zen", fn = ui_zen },
  { name = "winpick", fn = ui_winpick },
  { name = "notify", fn = ui_notify_cmd },
  { name = "keys", fn = ui_keys_cmd },
  { name = "theme", fn = ui_theme },
  { name = "themes", fn = ui_themes },
  { name = "variant", fn = ui_variant },
  { name = "variants", fn = ui_variants },
  { name = "tabline-style", fn = ui_tabline_style },
  { name = "tabline-styles", fn = ui_tabline_styles },
  { name = "picker", fn = ui_picker },
  { name = "modules", fn = ui_modules },
  { name = "toggle", fn = ui_toggle },
  { name = "status", fn = ui_status },
  { name = "help", fn = ui_help },
}

local actions = {}
local subcommand_names = {}
for _, entry in ipairs(SUBCOMMANDS) do
  actions[entry.name] = entry.fn
  table.insert(subcommand_names, entry.name)
end

-----------------------------------------------------------------------
-- Dispatcher
-----------------------------------------------------------------------

---@param opts table
local function dispatcher(opts)
  local args = vim.split(vim.trim(opts.args or ""), "%s+")

  -- Handle empty command
  if #args == 0 or args[1] == "" then
    ui_help({})
    return
  end

  local sub = args[1]
  local action = actions[sub]

  if action then
    local ok, err = pcall(action, args)
    if not ok then
      notify.error(("UI %s error: %s"):format(sub, tostring(err)))
    end
  else
    notify.error(("Unknown command: '%s'\nUse :UI help for help"):format(sub))
  end
end

-----------------------------------------------------------------------
-- Completion
-----------------------------------------------------------------------

---@param arglead string
---@param cmdline string
---@param _cursorpos number # Unused: the split below reads the whole cmdline
---@return string[]
local function complete(arglead, cmdline, _cursorpos)
  -- Split the command line into parts
  local parts = {}
  for part in cmdline:gmatch("%S+") do
    table.insert(parts, part)
  end

  -- Count how many arguments we have (excluding the command itself)
  local num_args = #parts - 1

  -- If the line ends with a space, we're completing the next argument
  if cmdline:match("%s$") then
    num_args = num_args + 1
    arglead = ""
  end

  -- Complete first argument (subcommands)
  if num_args == 1 then
    return filter(arglead, subcommand_names)
  end

  -- Complete second argument based on subcommand
  if num_args == 2 then
    local subcmd = parts[2]

    if subcmd == "transparency" then
      return filter(arglead, { "on", "off" })
    end

    if subcmd == "screenkey" then
      return filter(arglead, { "on", "off" })
    end

    if subcmd == "sticky" or subcmd == "context" then
      return filter(arglead, { "on", "off", "toggle", "status", "depth", "lines", "reset", "up" })
    end

    if subcmd == "zen" then
      return filter(arglead, { "on", "off" })
    end

    if subcmd == "notify" then
      return filter(arglead, { "on", "off", "history", "clear" })
    end

    if subcmd == "theme" then
      return filter(arglead, theme.list_themes())
    end

    if subcmd == "variant" then
      -- The registry, not a static list: a host's own require("ui.config
      -- .variants").register(name, ...) shows up here the moment it runs,
      -- same as the four shipped presets.
      return filter(arglead, require("ui.config.variants").list())
    end

    if subcmd == "tabline-style" then
      -- Same registry-not-static-list reasoning as "variant" above, one
      -- module over: require("ui.tabline.styles").register(name, fn).
      return filter(arglead, require("ui.tabline.styles").list())
    end
  end

  -- Complete third argument: only `sticky` has one, its `depth` level and the
  -- filetype of its `lines`.
  if num_args == 3 and (parts[2] == "sticky" or parts[2] == "context") then
    if parts[3] == "depth" then
      return filter(arglead, { "1", "2", "3", "4", "5", "6", "all" })
    end
    if parts[3] == "lines" then
      return filter(arglead, vim.fn.getcompletion("", "filetype"))
    end
  end

  return {}
end

-----------------------------------------------------------------------
-- Public API
-----------------------------------------------------------------------

---@return nil
function M.setup()
  usercmd.create("UI", dispatcher, {
    nargs = "*",
    complete = complete,
    desc = "UI Kontrolle (Theme, Transparenz, Varianten, Tabline-Stil, ... -- siehe :UI help)",
  })

  -- Optional: Create shorter aliases
  usercmd.create("Theme", function(opts)
    dispatcher({ args = "theme " .. opts.args })
  end, {
    nargs = "?",
    -- The `unused-local` suppression that used to sit here covered exactly
    -- one of the eleven `_`-prefixed unused parameters in this file and
    -- carried no reason for being on that one (LLS-40). The `_` prefix is
    -- this repo's marker for a parameter kept only for signature parity;
    -- LuaLS still hints on it, uniformly, and that uniform hint is easier to
    -- read than one arbitrarily silenced case.
    complete = function(arglead, _cmdline, _cursorpos)
      return filter(arglead, theme.list_themes())
    end,
    desc = "Theme ändern (Shortcut für :UI theme)",
  })
end

return M
