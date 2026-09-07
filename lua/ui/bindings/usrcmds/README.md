# UI Command Modul für NvChad

Ein erweitertes Command-Modul für die Runtime-Konfiguration von NvChad's Base46 Themes und UI-Einstellungen.

## Table of content

- [UI Command Modul für NvChad](#ui-command-modul-fr-nvchad)
  - [🚀 Features](#features)
  - [📦 Installation](#installation)
    - [Mit lazy.nvim](#mit-lazynvim)
    - [Manuelle Installation](#manuelle-installation)
  - [📖 Verwendung](#verwendung)
    - [Theme wechseln](#theme-wechseln)
    - [Alle Themes auflisten](#alle-themes-auflisten)
    - [Transparenz umschalten](#transparenz-umschalten)
    - [Theme-Toggle verwenden](#theme-toggle-verwenden)
    - [Status anzeigen](#status-anzeigen)
    - [Hilfe anzeigen](#hilfe-anzeigen)
  - [⌨️ Empfohlene Keybindings](#empfohlene-keybindings)
  - [🎨 Verfügbare Base46 Themes](#verfgbare-base46-themes)
  - [🔧 Konfiguration](#konfiguration)
    - [chadrc.lua Beispiel](#chadrclua-beispiel)
  - [🐛 Troubleshooting](#troubleshooting)
    - [Theme wird nicht gefunden](#theme-wird-nicht-gefunden)
    - [Transparenz funktioniert nicht](#transparenz-funktioniert-nicht)
    - [Autocompletion funktioniert nicht](#autocompletion-funktioniert-nicht)
  - [📝 Changelog](#changelog)
    - [Version 1.0.0](#version-100)
  - [🤝 Contributing](#contributing)
  - [📄 Lizenz](#lizenz)
  - [💡 Tipps](#tipps)
    - [Schneller Theme-Wechsel während der Arbeit](#schneller-theme-wechsel-whrend-der-arbeit)
    - [Workflow-Empfehlung](#workflow-empfehlung)
    - [Performance](#performance)
  - [🎯 Zukünftige Features](#zuknftige-features)

---

## 🚀 Features

- **Theme-Switching**: Wechsle zwischen allen verfügbaren Base46 Themes
- **Autocompletion**: Intelligente Tab-Completion für alle Commands und Theme-Namen
- **Transparenz-Toggle**: Einfaches Ein-/Ausschalten der Terminal-Transparenz
- **Theme-Toggle**: Schnelles Wechseln zwischen konfigurierten Lieblings-Themes
- **Status-Übersicht**: Zeige aktuelle UI-Konfiguration an
- **Deutsche Lokalisierung**: Alle Meldungen auf Deutsch

## 📦 Installation

### Mit lazy.nvim

```lua
{
  "dein-nvchad-config",
  config = function()
    require("ui.command").setup()
  end,
}
```

### Manuelle Installation

1. Platziere das Modul unter `lua/ui/command/init.lua`
2. Füge in deiner `init.lua` hinzu:

```lua
require("ui.command").setup()
```

## 📖 Verwendung

### Theme wechseln

```vim
:UI theme tokyonight      " Wechsle zu tokyonight Theme
:UI theme rosepine        " Wechsle zu rosepine Theme
:UI theme <Tab>           " Zeige alle verfügbaren Themes (Autocompletion)

" Shortcut:
:Theme tokyonight         " Direkter Theme-Wechsel
```

### Alle Themes auflisten

```vim
:UI themes
```

Zeigt alle verfügbaren Base46 Themes mit Markierung (✓) für das aktuelle Theme.

### Transparenz umschalten

```vim
:UI transparency          " Toggle Transparenz an/aus
:UI transparency on       " Transparenz aktivieren
:UI transparency off      " Transparenz deaktivieren
```

### Theme-Toggle verwenden

Wenn du in deiner `chadrc.lua` einen `theme_toggle` konfiguriert hast:

```lua
M.base46 = {
  theme = "tokyonight",
  theme_toggle = { "tokyonight", "rosepine" },
  transparency = false,
}
```

Dann kannst du schnell zwischen den Themes wechseln:

```vim
:UI toggle                " Wechsle zum nächsten Theme in der Liste
```

### Status anzeigen

```vim
:UI status
```

Zeigt die aktuelle UI-Konfiguration:
```
╭─ UI Status ─────────────────╮
│ Theme:        tokyonight    │
│ Transparenz:  aus           │
│ Toggle:       tokyonight... │
╰─────────────────────────────╯
```

### Hilfe anzeigen

```vim
:UI help
:UI                       " Ohne Argument zeigt auch die Hilfe
```

## ⌨️ Empfohlene Keybindings

Füge diese zu deiner Konfiguration hinzu:

```lua
-- In deiner Keybindings-Datei
vim.keymap.set("n", "<leader>tt", ":UI toggle<CR>", { desc = "Toggle Theme" })
vim.keymap.set("n", "<leader>ts", ":UI transparency<CR>", { desc = "Toggle Transparency" })
vim.keymap.set("n", "<leader>th", ":UI themes<CR>", { desc = "List Themes" })
```

## 🎨 Verfügbare Base46 Themes

Das Modul unterstützt alle Base46 Themes, darunter:

- `tokyonight`
- `rosepine`
- `catppuccin`
- `everforest`
- `gruvbox`
- `nord`
- `onedark`
- `dracula`
- `nightfox`
- und viele mehr...

Nutze `:UI themes` für die vollständige Liste.

## 🔧 Konfiguration

### chadrc.lua Beispiel

```lua
local M = {}

M.base46 = {
  theme = "tokyonight",
  transparency = false,

  -- Optional: Definiere Themes zum schnellen Wechseln
  theme_toggle = { "tokyonight", "rosepine", "catppuccin" },

  -- Optional: Theme-spezifische Overrides
  hl_override = {
    Comment = { italic = true },
  },
}

return M
```

## 🐛 Troubleshooting

### Theme wird nicht gefunden

Stelle sicher, dass das Theme in Base46 existiert:

```vim
:UI themes              " Liste alle verfügbaren Themes
```

### Transparenz funktioniert nicht

1. Überprüfe, ob dein Terminal Transparenz unterstützt
2. Stelle sicher, dass Base46 korrekt geladen ist
3. Versuche manuell: `:lua require('base46').toggle_transparency()`

### Autocompletion funktioniert nicht

Stelle sicher, dass:
1. Das Modul mit `.setup()` initialisiert wurde
2. Du im Command-Modus `Tab` drückst
3. Neovim mindestens Version 0.8+ ist

## 📝 Changelog

### Version 1.0.0
- Initiales Release
- Theme-Switching mit Autocompletion
- Transparenz-Toggle über Base46
- Theme-Toggle zwischen konfigurierten Themes
- Deutsche Lokalisierung
- Status-Übersicht

## 🤝 Contributing

Verbesserungsvorschläge und Bug-Reports sind willkommen!

## 📄 Lizenz

MIT License - nutze es wie du möchtest!

## 💡 Tipps

### Schneller Theme-Wechsel während der Arbeit

Nutze die `:Theme` Shortcut-Command:

```vim
:Theme <Tab>            " Zeige alle Themes
:Theme tokyo<Tab>       " Autocomplete zu tokyonight
```

### Workflow-Empfehlung

1. Teste verschiedene Themes mit `:UI theme <name>`
2. Wähle deine 2-3 Favoriten aus
3. Konfiguriere sie in `theme_toggle`
4. Nutze `:UI toggle` für schnelles Wechseln

### Performance

- Theme-Wechsel sind instant (keine Neustart nötig)
- Transparenz-Toggle ist ebenfalls sofort aktiv
- Keine Performance-Einbußen durch das Modul

## 🎯 Zukünftige Features

- [ ] Theme-Previews in Floating Window
- [ ] Theme-Export/Import
- [ ] Custom Theme-Collections
- [ ] Theme-Scheduler (basierend auf Tageszeit)

---
