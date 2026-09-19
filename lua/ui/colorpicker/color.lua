---@module 'ui.colorpicker.color'
--- The colour arithmetic behind `ui.colorpicker`: hex <-> rgb <-> hsl, a
--- lightness shift, and a luminance-based "which text colour reads on this
--- background". Pure functions over numbers and `#rrggbb` strings; nothing
--- here touches a buffer or a highlight group.

local M = {}

---Parse `#rrggbb`, `#rgb`, `rrggbb` or `rgb` into 0-255 channels.
---@param hex string
---@return integer|nil r
---@return integer|nil g
---@return integer|nil b
function M.parse(hex)
  if type(hex) ~= "string" then
    return nil, nil, nil
  end
  local s = hex:gsub("^#", "")
  if #s == 3 then
    s = s:gsub("(%x)", "%1%1")
  end
  if #s ~= 6 or not s:match("^%x+$") then
    return nil, nil, nil
  end
  return tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16)
end

---Whether `hex` parses.
---@param hex string
---@return boolean
function M.valid(hex)
  return M.parse(hex) ~= nil
end

---@param n number
---@return integer
local function clamp255(n)
  return math.max(0, math.min(255, math.floor(n + 0.5)))
end

---`#rrggbb` (lower case) from 0-255 channels.
---@param r number
---@param g number
---@param b number
---@return string
function M.to_hex(r, g, b)
  return ("#%02x%02x%02x"):format(clamp255(r), clamp255(g), clamp255(b))
end

---Normalise any accepted spelling to `#rrggbb`, or nil.
---@param hex string
---@return string|nil
function M.normalize(hex)
  local r, g, b = M.parse(hex)
  if not r then
    return nil
  end
  return M.to_hex(r, g, b)
end

---0-255 channels to hue (0-360), saturation (0-100), lightness (0-100).
---@param r number
---@param g number
---@param b number
---@return number h
---@return number s
---@return number l
function M.rgb_to_hsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local max, min = math.max(r, g, b), math.min(r, g, b)
  local l = (max + min) / 2
  if max == min then
    return 0, 0, l * 100
  end
  local d = max - min
  local s = l > 0.5 and d / (2 - max - min) or d / (max + min)
  local h
  if max == r then
    h = (g - b) / d + (g < b and 6 or 0)
  elseif max == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60, s * 100, l * 100
end

---@param p number
---@param q number
---@param t number
---@return number
local function hue_to_rgb(p, q, t)
  if t < 0 then
    t = t + 1
  end
  if t > 1 then
    t = t - 1
  end
  if t < 1 / 6 then
    return p + (q - p) * 6 * t
  end
  if t < 1 / 2 then
    return q
  end
  if t < 2 / 3 then
    return p + (q - p) * (2 / 3 - t) * 6
  end
  return p
end

---Hue (0-360), saturation (0-100), lightness (0-100) to 0-255 channels.
---@param h number
---@param s number
---@param l number
---@return number r
---@return number g
---@return number b
function M.hsl_to_rgb(h, s, l)
  h = (h % 360) / 360
  s = math.max(0, math.min(100, s)) / 100
  l = math.max(0, math.min(100, l)) / 100
  if s == 0 then
    return l * 255, l * 255, l * 255
  end
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return hue_to_rgb(p, q, h + 1 / 3) * 255,
    hue_to_rgb(p, q, h) * 255,
    hue_to_rgb(p, q, h - 1 / 3) * 255
end

---@param h number
---@param s number
---@param l number
---@return string hex
function M.hsl_to_hex(h, s, l)
  return M.to_hex(M.hsl_to_rgb(h, s, l))
end

---@param hex string
---@return number|nil h
---@return number|nil s
---@return number|nil l
function M.hex_to_hsl(hex)
  local r, g, b = M.parse(hex)
  if not r then
    return nil, nil, nil
  end
  return M.rgb_to_hsl(r, g, b)
end

---`hex` with its lightness shifted by `delta` percentage points (negative
---darkens), saturation and hue kept.
---@param hex string
---@param delta number
---@return string|nil
function M.shift_lightness(hex, delta)
  local h, s, l = M.hex_to_hsl(hex)
  if not h then
    return nil
  end
  return M.hsl_to_hex(h, s, l + delta)
end

---Relative luminance (0-1) per WCAG, for picking a readable text colour.
---@param hex string
---@return number|nil
function M.luminance(hex)
  local r, g, b = M.parse(hex)
  if not r then
    return nil
  end
  local function lin(c)
    c = c / 255
    if c <= 0.03928 then
      return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
  end
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end

---`"#000000"` or `"#ffffff"`, whichever reads better on `hex`.
---@param hex string
---@return string
function M.contrast(hex)
  local lum = M.luminance(hex) or 0
  return lum > 0.4 and "#000000" or "#ffffff"
end

---The `#rrggbb`/`#rgb` literal that contains byte column `col` (0-based)
---of `line`, if any: the hex, its 0-based start column and its end column
---(exclusive).
---@param line string
---@param col integer
---@return string|nil hex
---@return integer|nil start_col
---@return integer|nil end_col
function M.hex_at(line, col)
  if type(line) ~= "string" then
    return nil, nil, nil
  end
  local init = 1
  while true do
    local s, e = line:find("#%x%x%x%x%x%x%f[^%x]", init)
    if not s then
      s, e = line:find("#%x%x%x%f[^%x]", init)
    end
    if not s then
      return nil, nil, nil
    end
    if col >= s - 1 and col < e then
      return line:sub(s, e), s - 1, e
    end
    init = e + 1
  end
end

return M
