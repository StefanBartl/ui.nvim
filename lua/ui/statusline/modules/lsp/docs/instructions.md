# Einbindung in chadrc.lua (durchgehende Färbung, LSP-first)

**Kurztests und Hinweise:**
* LSP-Verfügbarkeit prüfen: :LspInfo im betroffenen Buffer; documentSymbolProvider sollte „true“ sein.
* Performance: Der Sync-Request nutzt 120 ms Timeout. Bei langsamen Servern greift der Cache-Fallback. Für große Dateien ggf. Timeout senken oder ausschließlich Cache nutzen.
* Genauigkeit: Manche Server liefern nur flache SymbolInformation[]; der Code behandelt das (kleinstes einschließendes Range als „Pfad“).
* Anpassungen: In DEFAULT_KEEP_KINDS Symbolarten erweitern/einschränken; KIND_LABEL für Debug/Tooltips nutzbar.
* Fallback: Wenn LSP nichts Brauchbares liefert, aktiviert sich automatisch die bestehende Treesitter-Logik; damit funktionieren Tabellen-/Member-Kontexte auch ohne LSP-Server stabil.


Einbindung in chadrc.lua als Modul-Key in der Mitte

```lua
local M = {}

M.ui = {
  statusline = {
    theme = "default",
    separator_style = "default",

    -- Wenn diese "modules"-Form verfügbar ist, einfach den Custom-Key verwenden:
    modules = {
      left  = { "mode", "file" },
      mid   = { "lsp_breadcrumbs" },  -- unser neues Modul hier platzieren
      right = { "git", "diagnostics", "lsp", "cwd" },
    },

    ---@param mods table<string, fun():string>
    overriden_modules = function(mods)
      mods.lsp_breadcrumbs = function()
        local mod = require("ui.stl_modules.lsp_based")
        local band = mod.mode_band_group()
        -- Band öffnen, Inherit-Variante rendern, NICHT schließen:
        return mod.hl_open(band) .. mod.render_breadcrumbs_inherit_lspfirst(band)
      end
    end,
  },
}

return M

```

Alternative Einbindung, falls nur Array-Slots verfügbar sind

```lua
local M = {}

M.ui = {
  statusline = {
    theme = "default",
    separator_style = "default",

    ---@param mods table|any
    overriden_modules = function(mods)
      -- Bei vielen NvChad-Versionen ist mods[2] die zentrale Mitte
      mods[2] = function()
        local mod = require("ui.stl_modules.lsp_based")
        local band = mod.mode_band_group()
        -- Mitte einfärben bis zum rechten Block: Band offen lassen
        return mod.hl_open(band) .. mod.render_breadcrumbs_inherit_lspfirst(band)
      end
    end,
  },
}

return M
```
