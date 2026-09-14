---@module 'ui.bindings.usrcmds'
---Provides :UI usercommand for runtime UI configuration (theme, transparency).

local notify = require("lib.nvim.notify").create("[ui.bindings.usrcmds]")
local usercmd = require("lib.nvim.bindings.usercmd")

local M = {}

local theme = require("ui.bindings.usrcmds.themes")
local theme_picker = require("ui.bindings.usrcmds.themes.picker")
local screenkey = require("ui.screenkey")

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
      notify.info("✨ Transparenz aktiviert")
    end
    return
  end

  if action == "off" then
    local success = theme.set_transparency(false)
    if success then
      notify.info("🎨 Transparenz deaktiviert")
    end
    return
  end

  -- Toggle
  local new_state = theme.toggle_transparency()
  notify.info(string.format("✨ Transparenz %s", new_state and "aktiviert" or "deaktiviert"))
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
    notify.info("⌨️  Screenkey aktiviert")
    return
  end

  if action == "off" then
    screenkey.disable()
    notify.info("⌨️  Screenkey deaktiviert")
    return
  end

  local now_enabled = screenkey.toggle()
  notify.info(string.format("⌨️  Screenkey %s", now_enabled and "aktiviert" or "deaktiviert"))
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
      string.format(
        "Theme '%s' nicht gefunden.\n\nVerfügbare Themes:\n%s",
        theme_name,
        available_str
      )
    )
    return
  end

  -- Load theme
  local success = theme.load_theme(theme_name)

  if success then
    notify.info(string.format("🎨 Theme geändert zu: %s", theme_name))
  else
    notify.error(string.format("Fehler beim Laden von Theme '%s'", theme_name))
  end
end

---Handle themes list command
---@param _args string[] # Unused: these subcommands take no argument
local function ui_themes(_args)
  local themes = theme.list_themes()
  local current = theme.get_current_theme()

  if #themes == 0 then
    notify.error("Keine Themes gefunden!")
    return
  end

  -- Format themes list with current marker
  local lines = { string.format("Verfügbare Themes (%d):", #themes), "" }

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
    string.format("│ Transparenz:  %-15s │", info.transparency and "an" or "aus"),
    string.format("│ Variante:     %-15s │", variant or "(unbenannt)"),
    string.format("│ Tabline-Style:%-15s │", tabline_style),
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

  require("ui.statusline.render").enable(assembled.ui.statusline)
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
        "Aktuelle Variante: %s\nNutze :UI variant <name> zum Wechseln",
        current or "(unbenannt -- per Tabelle direkt übergeben)"
      )
    )
    return
  end

  if not variants.exists(name) then
    notify.error(
      string.format(
        "Variante '%s' nicht gefunden.\n\nVerfügbare Varianten:\n%s",
        name,
        table.concat(variants.list(), ", ")
      )
    )
    return
  end

  if switch_variant(name) then
    notify.info(string.format("🎨 Statusline-Variante geändert zu: %s", name))
  else
    notify.error(string.format("Fehler beim Wechseln zu Variante '%s'", name))
  end
end

---Handle variants list command
---@param _args string[] # Unused: this subcommand takes no argument
local function ui_variants(_args)
  local variants = require("ui.config.variants")
  local names = variants.list()
  local current = require("ui.config").get_variant()

  local lines = { string.format("Verfügbare Statusline-Varianten (%d):", #names), "" }

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
      string.format(
        "Aktueller Tabline-Style: %s\nNutze :UI tabline-style <name> zum Wechseln",
        current
      )
    )
    return
  end

  if not styles.exists(name) then
    notify.error(
      string.format(
        "Tabline-Style '%s' nicht gefunden.\n\nVerfügbare Styles:\n%s",
        name,
        table.concat(styles.list(), ", ")
      )
    )
    return
  end

  if switch_tabline_style(name) then
    notify.info(string.format("🎨 Tabline-Style geändert zu: %s", name))
  else
    notify.error(
      string.format(
        "Fehler beim Wechseln zu Tabline-Style '%s' (Tabline noch nicht aktiviert?)",
        name
      )
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
    notify.info(string.format("🎨 Theme geändert zu: %s", next_theme))
  else
    notify.warn(
      "Kein theme_toggle in chadrc konfiguriert.\n"
        .. "Füge mindestens 2 Themes zu theme_toggle hinzu."
    )
  end
end

---Show help information
---@param _args string[] # Unused: these subcommands take no argument
local function ui_help(_args)
  local help_text = [[
╭─ UI Command Hilfe ──────────────────────────────────╮
│                                                      │
│  :UI transparency           Transparenz umschalten   │
│  :UI transparency on        Transparenz aktivieren   │
│  :UI transparency off       Transparenz deaktivieren │
│                                                      │
│  :UI screenkey              Screenkey-HUD umschalten │
│  :UI screenkey on           Screenkey aktivieren     │
│  :UI screenkey off          Screenkey deaktivieren   │
│                                                      │
│  :UI theme                  Aktuelles Theme zeigen   │
│  :UI theme <name>           Theme setzen             │
│  :UI themes                 Alle Themes auflisten    │
│  :UI picker                 Visuellen Theme-Picker   │
│                             öffnen (Live-Vorschau)   │
│  :UI toggle                 Zwischen Themes wechseln │
│                                                      │
│  :UI variant                Aktuelle Variante zeigen │
│  :UI variant <name>         Variante wechseln        │
│  :UI variants               Alle Varianten auflisten │
│                                                      │
│  :UI tabline-style          Aktuellen Style zeigen   │
│  :UI tabline-style <name>   Tabline-Style wechseln   │
│  :UI tabline-styles         Alle Styles auflisten    │
│                                                      │
│  :UI modules                Verfügbare Segmente      │
│                             auflisten                │
│  :UI status                 Aktuelle Config zeigen   │
│  :UI help                   Diese Hilfe anzeigen     │
│                                                      │
╰──────────────────────────────────────────────────────╯

Siehe auch: ui/bindings/usrcmds/themes/README.md für technische Details
]]
  notify.info(help_text)
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

  local actions = {
    transparency = ui_transparency,
    screenkey = ui_screenkey,
    theme = ui_theme,
    themes = ui_themes,
    variant = ui_variant,
    variants = ui_variants,
    ["tabline-style"] = ui_tabline_style,
    ["tabline-styles"] = ui_tabline_styles,
    picker = ui_picker,
    modules = ui_modules,
    toggle = ui_toggle,
    status = ui_status,
    help = ui_help,
  }

  local action = actions[sub]

  if action then
    local ok, err = pcall(action, args)
    if not ok then
      notify.error(string.format("UI %s Fehler: %s", sub, tostring(err)))
    end
  else
    notify.error(string.format("Unbekannter Befehl: '%s'\nNutze :UI help für Hilfe", sub))
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
    local subcommands = {
      "transparency",
      "screenkey",
      "theme",
      "themes",
      "variant",
      "variants",
      "tabline-style",
      "tabline-styles",
      "picker",
      "modules",
      "toggle",
      "status",
      "help",
    }
    return filter(arglead, subcommands)
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
    ---@diagnostic disable-next-line: unused-local
    complete = function(arglead, _cmdline, _cursorpos)
      return filter(arglead, theme.list_themes())
    end,
    desc = "Theme ändern (Shortcut für :UI theme)",
  })
end

return M
