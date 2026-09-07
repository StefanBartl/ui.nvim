# ui.nvim Configuration System

Zentrales Konfigurationssystem für NvChad mit flexibler Statusline-Auswahl.

## Table of content

- [ui.nvim Configuration System](#uinvim-configuration-system)
  - [Struktur](#struktur)
  - [Verwendung](#verwendung)
    - [1. Statusline-Variante auswählen](#1-statusline-variante-auswhlen)
    - [2. Base46-Settings anpassen](#2-base46-settings-anpassen)
    - [3. chadrc.lua bleibt minimal](#3-chadrclua-bleibt-minimal)
  - [Statusline-Varianten](#statusline-varianten)
    - [normal](#normal)
    - [base](#base)
    - [lspbased](#lspbased)
    - [custom](#custom)
  - [Eigene Variante erstellen](#eigene-variante-erstellen)
  - [API](#api)
    - [ui.config.setup(user_opts?)](#uiconfigsetupuser_opts)
    - [ui.config.get_variant()](#uiconfigget_variant)
  - [Ablauf](#ablauf)
  - [Migration](#migration)
    - [Von alter chadrc.lua](#von-alter-chadrclua)
  - [Troubleshooting](#troubleshooting)
    - [Statusline lädt nicht](#statusline-ldt-nicht)
    - [Base46-Config wird ignoriert](#base46-config-wird-ignoriert)
    - [Module fehlen](#module-fehlen)
  - [Best Practices](#best-practices)
    - [✅ DO](#do)
    - [❌ DON'T](#dont)
  - [Beispiele](#beispiele)
    - [Minimale Config](#minimale-config)
    - [Mit User-Overrides](#mit-user-overrides)
    - [Custom Statusline](#custom-statusline)
  - [Changelog](#changelog)
    - [v1.0.0](#v100)

---

## Struktur

```
lua/ui/config/
├── init.lua              # Zentraler Config-Loader
├── base46.lua            # Base46-Theme-Config (zentral)
├── chadrc.lua            # Legacy chadrc-Kompatibilität (optional)
└── statusline/
    ├── normal.lua        # Default NvChad
    ├── base.lua          # Minimal custom
    ├── lspbased.lua      # LSP-aware breadcrumbs
    └── custom.lua        # Legacy custom breadcrumbs
```

## Verwendung

### 1. Statusline-Variante auswählen

In `lua/ui/config/init.lua`:

```lua
---@type "normal"|"base"|"lspbased"|"custom"
M.STATUSLINE_VARIANT = "lspbased"  -- Hier ändern!
```

### 2. Base46-Settings anpassen

In `lua/ui/config/base46.lua`:

```lua
return {
  transparency = false,
  theme_toggle = { "vim_default", "rosepine" },
  theme = "tokyonight",
}
```

**Nirgendwo anders!** Diese Datei ist die einzige Quelle für Base46-Config.

### 3. chadrc.lua bleibt minimal

```lua
return require("ui.config").setup()
```

Keine manuelle Base46-Konfiguration mehr in chadrc.lua!

## Statusline-Varianten

### normal

Default NvChad Statusline ohne Anpassungen.

```lua
M.STATUSLINE_VARIANT = "normal"
```

**Features:**
- Standard NvChad Order
- Standard NvChad Modules
- Keine Custom-Logik

---

### base

Minimale Custom-Statusline mit grundlegenden Features.

```lua
M.STATUSLINE_VARIANT = "base"
```

**Features:**
- Custom Cursor mit Row-Progress
- CWD-Anzeige
- Standard Diagnostics/LSP

**Order:**
```lua
{ "mode", "git", "%=", "cwd", "%=", "diagnostics", "lsp", "cursor", "progress" }
```

---

### lspbased

LSP-aware Statusline mit intelligenten Breadcrumbs.

```lua
M.STATUSLINE_VARIANT = "lspbased"
```

**Features:**
- LSP DocumentSymbols-basierte Breadcrumbs
- Treesitter Fallback
- Path-Kompression mit Component-Awareness
- Devicon-Integration mit Mode-Band-Coloring
- Cursor Progress (konfigurierbarer Mode)

**Order:**
```lua
{ "mode", "git", "%=", "breadcrumbs", "%=", "diagnostics", "lsp", "cursor", "progress", "cwd" }
```

**Module:**
- `breadcrumbs`: LSP-first → Treesitter fallback
- `diagnostics`: Re-wrapped mit Mode-Band
- `lsp`: Re-wrapped mit Mode-Band
- `cursor`: Mit Progress-Support
- `progress`: Leer (in cursor integriert)

---

### custom

Deine Legacy Custom-Breadcrumbs-Implementation.

```lua
M.STATUSLINE_VARIANT = "custom"
```

**Features:**
- Custom Breadcrumbs-Rendering
- Legacy-Kompatibilität

**Order:**
```lua
{ "mode", "git", "%=", "custom_breadcrumbs", "%=", "diagnostics", "lsp", "cursor" }
```

---

## Eigene Variante erstellen

1. Neue Datei erstellen:

```lua
-- lua/ui/config/statusline/myvariante.lua
local M = {}

M.ui = {
  statusline = {
    order = { "mode", "file", "%=", "lsp", "cursor" },
    modules = {
      cursor = function()
        return " Ln %l "
      end,
    },
  },
}

-- Optional: Setup-Funktion
function M.setup(config)
  -- Initialisierung
end

return M
```

2. In `init.lua` registrieren:

```lua
M.STATUSLINE_VARIANT = "myvariante"
```

---

## API

### ui.config.setup(user_opts?)

Lädt und assembliert die komplette Config.

```lua
local config = require("ui.config").setup({
  base46 = {
    theme = "onedark",  -- Optional: Override
  }
})
```

**Returns:** `table` – Komplette Config mit `base46` und `ui`

---

### ui.config.get_variant()

Gibt die aktuelle Statusline-Variante zurück.

```lua
local variant = require("ui.config").get_variant()
-- "lspbased"
```

**Returns:** `string`

---

## Ablauf

1. **ui.nvim Setup**
   ```lua
   require("ui").setup({ all = true })
   ```

2. **Config Load**
   ```lua
   require("ui.config").setup()
   ```

3. **Base46 Load**
   - Lädt `ui.config.base46`
   - Merged mit optionalen User-Overrides

4. **Statusline Load**
   - Lädt gewählte Variante (z.B. `statusline.lspbased`)
   - Ruft `setup()` auf wenn vorhanden

5. **Assembly**
   - Kombiniert Base46 + UI-Config
   - Returned finale Config

---

## Migration

### Von alter chadrc.lua

**Alt:**
```lua
local M = {}

M.base46 = {
  theme = "tokyonight",
  transparency = false,
}

M.ui = {
  statusline = {
    -- custom order/modules
  }
}

return M
```

**Neu:**

1. `base46.lua` erstellen:
```lua
return {
  theme = "tokyonight",
  transparency = false,
}
```

2. Custom Statusline nach `statusline/custom.lua` verschieben

3. `chadrc.lua` vereinfachen:
```lua
return require("ui.config").setup()
```

4. Variante wählen in `config/init.lua`:
```lua
M.STATUSLINE_VARIANT = "custom"
```

---

## Troubleshooting

### Statusline lädt nicht

**Fehler:**
```
[ui.config] Failed to load statusline variant 'xyz'
```

**Lösung:**
1. Prüfe ob `lua/ui/config/statusline/xyz.lua` existiert
2. Prüfe Lua-Syntax in der Datei
3. Schau in `:messages` für Details

---

### Base46-Config wird ignoriert

**Problem:**
Theme-Änderungen in `base46.lua` haben keine Wirkung.

**Lösung:**
1. Prüfe ob `chadrc.lua` noch alte `M.base46 = {}` hat
2. Lösche Cache: `:lua vim.fn.delete(vim.fn.stdpath('data')..'/base46', 'rf')`
3. Neovim neustarten

---

### Module fehlen

**Fehler:**
```
attempt to call field 'breadcrumbs' (a nil value)
```

**Lösung:**
1. Prüfe ob `modules = {}` Table existiert
2. Prüfe ob `setup()` Funktion Module registriert
3. Bei `lspbased`: Prüfe ob `chadrc.register_statusline_modules()` läuft

---

## Best Practices

### ✅ DO

- Base46-Config nur in `base46.lua` ändern
- Statusline-Variante in `init.lua` wählen
- Custom-Logik in eigene Statusline-Variante auslagern
- `setup()` Funktion für komplexe Initialisierung

### ❌ DON'T

- Base46-Config in `chadrc.lua` duplizieren
- Statusline-Module direkt in `chadrc.lua` definieren
- Hardcoded Varianten-Checks in `chadrc.lua`
- Globale States ohne Modul-Encapsulation

---

## Beispiele

### Minimale Config

```lua
-- config/init.lua
M.STATUSLINE_VARIANT = "normal"

-- config/base46.lua
return {
  theme = "onedark",
  transparency = true,
}

-- chadrc.lua
return require("ui.config").setup()
```

---

### Mit User-Overrides

```lua
-- chadrc.lua
return require("ui.config").setup({
  base46 = {
    theme = "gruvbox",  -- Override default
  }
})
```

---

### Custom Statusline

```lua
-- config/statusline/minimal.lua
local M = {}

M.ui = {
  statusline = {
    order = { "mode", "%=", "cursor" },
    modules = {
      cursor = function()
        return " %l:%c "
      end,
    },
  },
}

return M

-- config/init.lua
M.STATUSLINE_VARIANT = "minimal"
```

---

