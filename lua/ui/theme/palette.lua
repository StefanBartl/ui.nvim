---@module 'ui.theme.palette'
--- Semantic accent colors derived from the active colorscheme's own
--- highlight groups (`nvim_get_hl`), so accents work with whatever
--- colorscheme is active instead of depending on a bundled theme engine.
---
--- This is ui.nvim ROADMAP.md's "Open decisions #1", decided: diagnostic
--- groups are the anchor, because they are close to universally defined by
--- modern colorschemes (built-in LSP diagnostics need them) -- the same
--- reasoning lualine's "auto" theme relies on. A small fixed hex per key is
--- the fallback layer for a colorscheme that leaves one of the anchors
--- undefined, not a first choice.
---
--- Replaces `base46.get_theme_tb("base_30")`, the only place in this plugin
--- that ever read a raw color value out of NvChad's own theme tables (step 6
--- of the roadmap; see health.lua and ROADMAP.md for the rest of the base46
--- removal).

local M = {}

---@alias Ui.Theme.SemanticKey "project"|"nearest"|"lock"|"manual"|"tree_leads"

--- Anchor group per semantic key, tried in order; the first one that
--- resolves the requested field wins.
---@type table<Ui.Theme.SemanticKey, {group: string, field: "fg"|"bg"}[]>
local ANCHORS = {
  project = { { group = "DiagnosticHint", field = "fg" }, { group = "Function", field = "fg" } },
  nearest = { { group = "DiagnosticInfo", field = "fg" }, { group = "Type", field = "fg" } },
  lock = { { group = "DiagnosticError", field = "fg" }, { group = "ErrorMsg", field = "fg" } },
  manual = { { group = "Comment", field = "fg" } },
  tree_leads = { { group = "DiagnosticOk", field = "fg" }, { group = "String", field = "fg" } },
}

--- Reached only when every anchor above is undefined by the active
--- colorscheme -- a fixed hex per key, not tied to any particular theme.
---@type table<Ui.Theme.SemanticKey, string>
local FALLBACK_HEX = {
  project = "#9d7cd8",
  nearest = "#e06c9f",
  lock = "#e06c75",
  manual = "#a0a8b7",
  tree_leads = "#7fd88f",
}

---@param n integer
---@return string
local function to_hex(n)
  return string.format("#%06x", n)
end

---@param group string
---@param field "fg"|"bg"
---@return string? hex
local function read_hl(group, field)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
  if not ok or not hl[field] then
    return nil
  end
  return to_hex(hl[field])
end

---The accent color for a semantic key, e.g. "lock" -> a red-ish hex.
---Always returns a usable hex -- falls back to a fixed color rather than nil,
---so call sites never need a "no theme available" branch.
---@param key Ui.Theme.SemanticKey
---@return string hex
function M.accent(key)
  for _, anchor in ipairs(ANCHORS[key] or {}) do
    local hex = read_hl(anchor.group, anchor.field)
    if hex then
      return hex
    end
  end
  return FALLBACK_HEX[key] or "#a0a8b7"
end

--- Relative luminance (simplified sRGB) of a "#rrggbb" hex, 0..1.
---@param hex string
---@return number
local function luminance(hex)
  local r = tonumber(hex:sub(2, 3), 16) / 255
  local g = tonumber(hex:sub(4, 5), 16) / 255
  local b = tonumber(hex:sub(6, 7), 16) / 255
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

---Black or white, whichever reads against a background of `bg_hex` --
---guarantees legible text on an accent chip regardless of how bright or dark
---the derived (or fallback) accent color turns out to be.
---@param bg_hex string
---@return "#000000"|"#ffffff"
function M.contrast_fg(bg_hex)
  return luminance(bg_hex) > 0.5 and "#000000" or "#ffffff"
end

---The color to fade a separator into when there is no bespoke "empty
---statusline area" group to read -- the statusline's own background.
---@return string hex
function M.statusline_bg()
  return read_hl("StatusLine", "bg") or read_hl("Normal", "bg") or "#1a1b26"
end

return M
