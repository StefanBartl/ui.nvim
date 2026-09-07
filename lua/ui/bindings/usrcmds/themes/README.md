# Base46 Theme System - Technische Dokumentation

## Table of content

- [Base46 Theme System - Technische Dokumentation](#base46-theme-system-technische-dokumentation)
  - [Warum ist Theme-Switching in NvChad anders?](#warum-ist-theme-switching-in-nvchad-anders)
  - [🎨 Normale Colorschemes vs. Base46 Themes](#normale-colorschemes-vs-base46-themes)
    - [Normale Neovim Colorschemes](#normale-neovim-colorschemes)
    - [Base46 Themes](#base46-themes)
  - [🔧 Wie Base46 funktioniert](#wie-base46-funktioniert)
    - [1. Theme-Daten laden](#1-theme-daten-laden)
    - [2. Highlights generieren](#2-highlights-generieren)
    - [3. Compilation durchführen](#3-compilation-durchfhren)
    - [4. Caching für Performance](#4-caching-fr-performance)
  - [⚙️ Theme-Wechsel: Der komplette Prozess](#theme-wechsel-der-komplette-prozess)
    - [Schritt-für-Schritt](#schritt-fr-schritt)
    - [Was `load_all_highlights()` macht](#was-load_all_highlights-macht)
  - [🔍 Warum andere Methoden nicht funktionieren](#warum-andere-methoden-nicht-funktionieren)
    - [❌ Versuch 1: load_theme()](#versuch-1-load_theme)
    - [❌ Versuch 2: Direkter Colorscheme](#versuch-2-direkter-colorscheme)
    - [❌ Versuch 3: Nur Config ändern](#versuch-3-nur-config-ndern)
  - [✅ Die richtige Implementierung](#die-richtige-implementierung)
    - [Unser Theme-Modul](#unser-theme-modul)
  - [📝 Transparenz-Handling](#transparenz-handling)
    - [Warum Transparenz speziell ist](#warum-transparenz-speziell-ist)
    - [Toggle-Logik](#toggle-logik)
    - [Warum "off" nicht funktionierte](#warum-off-nicht-funktionierte)
  - [🎯 File-Persistierung](#file-persistierung)
    - [Warum überhaupt persistieren?](#warum-berhaupt-persistieren)
    - [Wie NvChad es macht](#wie-nvchad-es-macht)
    - [Unsere Implementierung](#unsere-implementierung)
  - [🔄 NvChad's Theme Picker](#nvchads-theme-picker)
  - [💡 Best Practices](#best-practices)
    - [1. Immer validieren](#1-immer-validieren)
    - [2. Error Handling](#2-error-handling)
    - [3. Async Persistierung](#3-async-persistierung)
    - [4. Module Reload](#4-module-reload)
  - [🧪 Testing](#testing)
    - [Theme-Wechsel testen](#theme-wechsel-testen)
    - [Persistierung testen](#persistierung-testen)
    - [Transparenz testen](#transparenz-testen)
  - [📚 Referenzen](#referenzen)
  - [🎓 Zusammenfassung](#zusammenfassung)

---

## Warum ist Theme-Switching in NvChad anders?

Diese Dokumentation erklärt, warum du **nicht einfach** `vim.cmd.colorscheme()` verwenden kannst und wie das Base46-System funktioniert.

---

## 🎨 Normale Colorschemes vs. Base46 Themes

### Normale Neovim Colorschemes

```lua
-- So funktioniert es NICHT in NvChad:
vim.cmd.colorscheme("gruvbox")  -- ❌ Funktioniert nicht!

-- Warum? Weil Base46 keine Colorscheme-Files verwendet
```

**Normale Colorschemes:**
- Sind `.vim` oder `.lua` Dateien in `colors/`
- Werden mit `:colorscheme name` geladen
- Setzen Highlight-Groups direkt
- Sind eigenständige Dateien

### Base46 Themes

```lua
-- Base46 Themes sind DATA-TABLES, keine Colorschemes:
-- In base46/lua/base46/themes/tokyonight.lua:

return {
  base00 = "#1a1b26",  -- Background
  base01 = "#16161e",  -- Lighter background
  base02 = "#2f3549",  -- Selection
  -- ... weitere Farben
}
```

**Base46 Themes:**
- Sind **Datentabellen** mit Farbpaletten
- Werden **nicht** als Colorscheme geladen
- Werden zur **Compile-Zeit** in Highlights umgewandelt
- Erfordern **Recompilation** bei jedem Wechsel

---

## 🔧 Wie Base46 funktioniert

### 1. Theme-Daten laden

```lua
-- Base46 lädt das Theme als Lua-Table
local theme_data = require("base46.themes.tokyonight")

-- Das Theme enthält nur Farben, keine Highlight-Groups!
-- {
--   base00 = "#1a1b26",
--   base01 = "#16161e",
--   ...
-- }
```

### 2. Highlights generieren

Base46 hat **Highlight-Templates** die die Theme-Farben verwenden:

```lua
-- Beispiel aus base46/lua/base46/integrations/...
local highlights = {
  Normal = { fg = theme.base05, bg = theme.base00 },
  Comment = { fg = theme.base03, italic = true },
  -- Hunderte weitere Highlight-Groups...
}
```

### 3. Compilation durchführen

```lua
-- Base46 kompiliert ALLE Highlights für ALLE Plugins:
base46.load_all_highlights()

-- Dies generiert:
-- - Editor Highlights (Normal, CursorLine, etc.)
-- - Syntax Highlights (String, Function, etc.)
-- - Plugin Highlights (Telescope, NvimTree, etc.)
-- - Custom Highlights aus chadrc.hl_override
```

### 4. Caching für Performance

```lua
-- Base46 cached kompilierte Highlights hier:
vim.g.base46_cache = vim.fn.stdpath("data") .. "/base46/"

-- Cached Files:
-- ~/.local/share/nvim/base46/
-- ├── colors         -- Farbpalette
-- ├── syntax         -- Syntax Highlights
-- ├── telescope      -- Telescope Highlights
-- └── ...
```

---

## ⚙️ Theme-Wechsel: Der komplette Prozess

### Schritt-für-Schritt

```lua
-- 1. UPDATE IN-MEMORY CONFIG
local chadrc = require("chadrc")
chadrc.base46.theme = "new_theme"

-- 2. RELOAD CHADRC MODULE
-- Wichtig! Sonst lädt Base46 das alte Theme
package.loaded.chadrc = nil
require("chadrc")  -- Neu laden

-- 3. RECOMPILE ALLE HIGHLIGHTS
local base46 = require("base46")
base46.load_all_highlights()  -- ⚡ Das ist die Magie!

-- 4. PERSIST TO FILE (Optional aber empfohlen)
-- Schreibe Änderung zurück in chadrc.lua
-- Sonst ist Theme nur für diese Sitzung aktiv
```

### Was `load_all_highlights()` macht

```lua
function M.load_all_highlights()
  -- 1. Lade Theme-Daten
  local theme = require("base46.themes." .. opts.theme)

  -- 2. Generiere Highlights für:
  --    - Editor (statusline, tabline, etc.)
  --    - Syntax (LSP, Treesitter)
  --    - Alle Plugins (telescope, cmp, nvimtree...)

  -- 3. Wende Overrides aus chadrc an
  local overrides = require("chadrc").base46.hl_override or {}

  -- 4. Cache compiled highlights
  -- 5. Apply to Neovim
  for group, colors in pairs(all_highlights) do
    vim.api.nvim_set_hl(0, group, colors)
  end
end
```

---

## 🔍 Warum andere Methoden nicht funktionieren

### ❌ Versuch 1: load_theme()

```lua
-- Das existiert NICHT in Base46!
base46.load_theme("tokyonight")  -- ❌ nil value error

-- In der Base46 Source gibt es nur:
-- - load_all_highlights()
-- - toggle_theme()
-- - toggle_transparency()
```

### ❌ Versuch 2: Direkter Colorscheme

```lua
vim.cmd.colorscheme("tokyonight")  -- ❌ Not found

-- Base46 Themes sind keine Colorschemes!
-- Es gibt kein colors/tokyonight.vim File
```

### ❌ Versuch 3: Nur Config ändern

```lua
require("chadrc").base46.theme = "new_theme"  -- ❌ Unvollständig

-- Das ändert nur die Config in memory
-- Highlights werden NICHT neu generiert!
-- Du siehst weiterhin das alte Theme
```

---

## ✅ Die richtige Implementierung

### Unser Theme-Modul

```lua
-- ui/command/theme.lua

function M.load_theme(theme)
  -- 1. Validate
  if not M.theme_exists(theme) then
    return false
  end

  -- 2. Get Base46
  local base46 = require("base46")

  -- 3. Update in-memory config
  local chadrc = require("chadrc")
  chadrc.base46.theme = theme

  -- 4. Reload chadrc (wichtig!)
  package.loaded.chadrc = nil
  require("chadrc")

  -- 5. Recompile everything
  base46.load_all_highlights()  -- ⚡ Key function!

  -- 6. Persist to file
  persist_theme(theme)

  return true
end
```

---

## 📝 Transparenz-Handling

### Warum Transparenz speziell ist

```lua
-- Transparenz ist eine spezielle Highlight-Override
-- Sie setzt bestimmte Backgrounds auf NONE

-- In Base46:
if opts.transparency then
  highlights.Normal.bg = "NONE"
  highlights.NormalFloat.bg = "NONE"
  highlights.SignColumn.bg = "NONE"
  -- etc...
end
```

### Toggle-Logik

```lua
function M.set_transparency(enabled)
  local current = M.get_transparency()

  -- NUR togglen wenn State sich ändert
  if current ~= enabled then
    base46.toggle_transparency()
    -- Dies ruft intern load_all_highlights() auf
  end
end
```

### Warum "off" nicht funktionierte

```lua
-- ❌ Original Code (FALSCH):
if action == "off" then
  base46.toggle_transparency()  -- Togglet immer!
  -- Wenn schon off -> geht an
  -- Wenn schon an -> geht aus (korrekt)
end

-- ✅ Korrigierter Code:
if action == "off" then
  local current = M.get_transparency()
  if current then  -- Nur wenn aktuell AN
    base46.toggle_transparency()
  end
end
```

---

## 🎯 File-Persistierung

### Warum überhaupt persistieren?

```lua
-- Ohne Persistierung:
-- 1. Du wechselst Theme -> OK!
-- 2. Du schließt Neovim
-- 3. Du öffnest Neovim neu
-- 4. ALTES Theme ist wieder da ❌

-- Mit Persistierung:
-- Die chadrc.lua wird GEÄNDERT
-- Nächster Start lädt direkt das neue Theme ✅
```

### Wie NvChad es macht

```lua
-- nvchad.utils.replace_word() Funktion
function replace_word(old, new)
  local chadrc_path = find_chadrc()
  local lines = readfile(chadrc_path)

  for i, line in ipairs(lines) do
    if line:find(old) then
      lines[i] = line:gsub(old, new)
    end
  end

  writefile(lines, chadrc_path)
end

-- Verwendung:
replace_word('theme = "old_theme"', 'theme = "new_theme"')
```

### Unsere Implementierung

```lua
function persist_theme(theme)
  -- 1. Finde chadrc.lua
  local path = find_chadrc_path()

  -- 2. Lese File
  local content = vim.fn.readfile(path)

  -- 3. Ersetze theme = "..." Zeile
  for i, line in ipairs(content) do
    if line:match('theme%s*=%s*"[^"]*"') then
      content[i] = line:gsub(
        'theme%s*=%s*"[^"]*"',
        'theme = "' .. theme .. '"'
      )
      break
    end
  end

  -- 4. Schreibe zurück
  vim.fn.writefile(content, path)
end
```

---

## 🔄 NvChad's Theme Picker

Der offizielle Theme Picker macht im Grunde dasselbe:

```lua
-- nvchad/themes/utils.lua
function reload_theme(theme)
  -- Update config
  require("chadrc").base46.theme = theme

  -- Reload module
  package.loaded.chadrc = nil
  require("chadrc")

  -- Recompile
  require("base46").load_all_highlights()
end

-- Aber: Speichert auch in der UI
-- Und: Hat Preview-Funktionalität
```

---

## 💡 Best Practices

### 1. Immer validieren

```lua
-- ✅ GOOD
if M.theme_exists(theme) then
  M.load_theme(theme)
end

-- ❌ BAD
M.load_theme(theme)  -- Könnte crashen bei ungültigem Theme
```

### 2. Error Handling

```lua
local ok, err = pcall(M.load_theme, theme)
if not ok then
  vim.notify("Theme-Fehler: " .. tostring(err), vim.log.levels.ERROR)
end
```

### 3. Async Persistierung

```lua
-- Nicht auf File-Write warten
vim.schedule(function()
  persist_theme(theme)
end)
```

### 4. Module Reload

```lua
-- IMMER chadrc reloaden nach Config-Änderung
package.loaded.chadrc = nil
require("chadrc")
```

---

## 🧪 Testing

### Theme-Wechsel testen

```vim
:lua require("ui.command.theme").load_theme("tokyonight")
:lua require("ui.command.theme").load_theme("rosepine")

" Prüfe ob Highlights korrekt sind:
:Telescope highlights
```

### Persistierung testen

```vim
:UI theme tokyonight
:q
" Neovim neu öffnen
" Theme sollte tokyonight sein ✅
```

### Transparenz testen

```vim
:UI transparency on
" Hintergrund sollte durchsichtig sein

:UI transparency off
" Hintergrund sollte solid sein

:UI transparency
" Toggle
```

---

## 📚 Referenzen

- **Base46 Source**: `lazy/base46/lua/base46/init.lua`
- **NvChad Utils**: `lazy/ui/lua/nvchad/utils.lua`
- **Theme Picker**: `lazy/ui/lua/nvchad/themes/`
- **Themes Ordner**: `lazy/base46/lua/base46/themes/`

---

## 🎓 Zusammenfassung

**Was du gelernt hast:**

1. ❌ Base46 Themes sind **keine Colorschemes**
2. ✅ Themes sind **Datentabellen** mit Farbpaletten
3. ⚡ `load_all_highlights()` ist der **Schlüssel**
4. 🔄 **Reload chadrc** nach Config-Änderungen
5. 💾 **Persistierung** für dauerhafte Änderungen
6. 🎯 Transparenz ist eine **spezielle Override**

**Die drei wichtigen Schritte:**

```lua
-- 1. Config ändern
chadrc.base46.theme = "new_theme"

-- 2. Module reloaden
package.loaded.chadrc = nil
require("chadrc")

-- 3. Recompile
base46.load_all_highlights()
```

---
