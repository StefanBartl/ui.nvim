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

---@alias Ui.Theme.ModeKey
---| "Normal"
---| "NTerminal"
---| "Visual"
---| "Insert"
---| "Terminal"
---| "Replace"
---| "Select"
---| "Command"
---| "Confirm"

--- Anchor group per vim-mode suffix -- the second element of each entry in
--- `ui.statusline.utils.primitives.modes`. Same recipe as `ANCHORS` above,
--- kept as a separate table because a statusline mode chip and a filetree
--- cwd-mode badge are unrelated semantics that happen to both want "one
--- accent color read from the active colorscheme".
---@type table<Ui.Theme.ModeKey, {group: string, field: "fg"|"bg"}[]>
local MODE_ANCHORS = {
  Normal = { { group = "DiagnosticOk", field = "fg" }, { group = "String", field = "fg" } },
  Insert = { { group = "DiagnosticInfo", field = "fg" }, { group = "Function", field = "fg" } },
  Visual = { { group = "DiagnosticHint", field = "fg" }, { group = "Keyword", field = "fg" } },
  Select = { { group = "DiagnosticHint", field = "fg" }, { group = "Keyword", field = "fg" } },
  Replace = { { group = "DiagnosticError", field = "fg" }, { group = "ErrorMsg", field = "fg" } },
  Command = { { group = "DiagnosticWarn", field = "fg" }, { group = "WarningMsg", field = "fg" } },
  Confirm = { { group = "DiagnosticWarn", field = "fg" }, { group = "WarningMsg", field = "fg" } },
  Terminal = { { group = "Special", field = "fg" }, { group = "Comment", field = "fg" } },
  NTerminal = { { group = "Special", field = "fg" }, { group = "Comment", field = "fg" } },
}

---@type table<Ui.Theme.ModeKey, string>
local MODE_FALLBACK_HEX = {
  Normal = "#7fd88f",
  Insert = "#7aa2f7",
  Visual = "#bb9af7",
  Select = "#bb9af7",
  Replace = "#e06c75",
  Command = "#e0af68",
  Confirm = "#e0af68",
  Terminal = "#4fd6be",
  NTerminal = "#4fd6be",
}

---The accent color for a statusline mode chip, e.g. "Insert" -> a blue-ish
---hex. Same always-a-hex contract as `M.accent`.
---@param mode_key Ui.Theme.ModeKey
---@return string hex
function M.mode_accent(mode_key)
  for _, anchor in ipairs(MODE_ANCHORS[mode_key] or {}) do
    local hex = read_hl(anchor.group, anchor.field)
    if hex then
      return hex
    end
  end
  return MODE_FALLBACK_HEX[mode_key] or "#a0a8b7"
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

---WCAG relative luminance of a "#rrggbb" hex (with the sRGB gamma curve, unlike the simplified `luminance`
---above, which only picks black or white), 0..1.
---@param hex string
---@return number
local function wcag_luminance(hex)
  local function channel(from)
    local c = tonumber(hex:sub(from, from + 1), 16) / 255
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * channel(2) + 0.7152 * channel(4) + 0.0722 * channel(6)
end

---WCAG contrast ratio of two "#rrggbb" colors, 1 (identical) .. 21 (black on white).
---@param a string
---@param b string
---@return number
function M.contrast_ratio(a, b)
  local la, lb = wcag_luminance(a), wcag_luminance(b)
  if la < lb then
    la, lb = lb, la
  end
  return (la + 0.05) / (lb + 0.05)
end

---@param from string
---@param to string
---@param t number 0..1
---@return string
local function mix(from, to, t)
  local out = { "#" }
  for i = 2, 6, 2 do
    local x = tonumber(from:sub(i, i + 1), 16)
    local y = tonumber(to:sub(i, i + 1), 16)
    out[#out + 1] = string.format("%02x", math.floor(x + (y - x) * t + 0.5))
  end
  return table.concat(out)
end

---`fg` itself when it reads on `bg` with at least `min` contrast; otherwise `fg` moved toward `toward` (default:
---black or white, whichever contrasts with `bg`) in small steps until it does, so the hue of the scheme survives
---as far as it can. A missing `fg` counts as `toward`. On a ground in the middle of the scale `toward` can be the
---wrong side (light grey text on mid grey: lighter does not help): then `fg` moves toward black or white, whichever
---contrasts better with `bg`, which reaches 4.58:1 on any ground, so every `min` up to 4.5 is met.
---@param fg string|nil
---@param bg string
---@param min number Required ratio (4.5 for text, 3 for symbols)
---@param toward? string
---@return string hex
function M.ensure_contrast(fg, bg, min, toward)
  toward = toward or M.contrast_fg(bg)
  if fg and M.contrast_ratio(fg, bg) >= min then
    return fg
  end
  ---@param target string
  ---@return string|nil
  local function lift(target)
    if not fg then
      return nil
    end
    for step = 1, 20 do
      local candidate = mix(fg, target, step / 20)
      if M.contrast_ratio(candidate, bg) >= min then
        return candidate
      end
    end
    return nil
  end
  if not fg then
    if M.contrast_ratio(toward, bg) >= min then
      return toward
    end
  else
    local lifted = lift(toward)
    if lifted then
      return lifted
    end
  end
  local extreme = M.contrast_ratio("#000000", bg) >= M.contrast_ratio("#ffffff", bg) and "#000000"
    or "#ffffff"
  return fg and lift(extreme) or extreme
end

---The color to fade a separator into when there is no bespoke "empty
---statusline area" group to read -- the statusline's own background.
---@return string hex
function M.statusline_bg()
  return read_hl("StatusLine", "bg") or read_hl("Normal", "bg") or "#1a1b26"
end

return M
