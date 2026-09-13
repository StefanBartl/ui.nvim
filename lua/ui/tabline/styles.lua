---@module 'ui.tabline.styles'
--- Named chip-boundary decorators for `ui.tabline.modules.buffers()` --
--- `cfg.style` resolves through this registry the same way a statusline
--- variant name resolves through `ui.config.variants`: three shipped
--- entries (`rounded`/`square`/`divider`) plus whatever a host adds via
--- `M.register(name, fn)`. Before this, `cfg.style` was a closed set of
--- three string literals hardcoded into `ui.tabline.modules`'s own
--- `apply_boundaries` -- no way for a host to add a fourth look without
--- patching this repo, unlike every other named-choice knob here
--- (`separator_style`, the statusline `variant`).

local utils = require("ui.tabline.utils")

local M = {}

---@alias Ui.Tabline.StyleFn fun(chips: string[], chip_bufs: integer[], cur: integer, flush_right: boolean): nil

---@type table<string, Ui.Tabline.StyleFn>
local _registry = {}

--- "square" -- nothing added: chips sit flush against each other, no
--- boundary decoration. The look before `cfg.style` existed.
---@type Ui.Tabline.StyleFn
local function square(_chips, _chip_bufs, _cur, _flush_right) end

--- "divider" -- one plain vertical bar per internal boundary, no rounding.
---@type Ui.Tabline.StyleFn
local function divider(chips, _chip_bufs, _cur, _flush_right)
  local glyph = "%#UiTbDivider#" .. utils.DIVIDER
  for i = 1, #chips - 1 do
    chips[i] = chips[i] .. glyph
  end
end

--- "rounded" (default) -- a cap on every internal boundary. The first
--- chip's left edge is always square -- it sits directly against the bar's
--- own left edge (or `tree_offset`'s fill), never with slack in between.
--- The last chip's right edge is square only when `flush_right` says the
--- visible run actually reaches the space budget (buffers had to be
--- dropped to fit, or the auto-computed width used every column) --
--- otherwise `"%="` alignment leaves genuine empty space before
--- `tabs`/`btns`, and squaring an edge that isn't touching anything reads
--- as a cut corner rather than a frame. A single-chip run follows the same
--- two rules independently -- square on the left always, square on the
--- right only if flush.
---@type Ui.Tabline.StyleFn
local function rounded(chips, chip_bufs, cur, flush_right)
  for i, bufnr in ipairs(chip_bufs) do
    local cap_hl = "%#" .. ((bufnr == cur) and "UiTbBufOnCap" or "UiTbBufOffCap") .. "#"
    local is_last = i == #chip_bufs
    if not (is_last and flush_right) then
      chips[i] = chips[i] .. cap_hl .. utils.RIGHT_CAP
    end
    if i > 1 then
      chips[i] = cap_hl .. utils.LEFT_CAP .. chips[i]
    end
  end
end

_registry.square = square
_registry.divider = divider
_registry.rounded = rounded

---Register a chip-boundary decorator under `name` -- a host's own tabline
---look, typically. `fn` mutates `chips` in place given the parallel
---`chip_bufs` list, the current buffer (for per-chip cap highlighting) and
---whether the visible run is flush against its space budget.
---
---Registering under one of the three shipped names replaces it for the
---rest of the session -- deliberate, not guarded, same as
---`ui.config.variants.register()`: a host that wants to redefine what
---"rounded" looks like is making an explicit choice, not colliding by
---accident.
---@param name string
---@param fn Ui.Tabline.StyleFn
---@return nil
function M.register(name, fn)
  _registry[name] = fn
end

---Remove a registered style. No-op if `name` was never registered.
---@param name string
---@return nil
function M.unregister(name)
  _registry[name] = nil
end

---Every registered name, sorted -- shipped styles and host-registered ones
---alike. What `:UI tabline-style <Tab>` completes over.
---@return string[]
function M.list()
  local names = {}
  for name in pairs(_registry) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

---Whether `name` is registered (built-in or host-added).
---@param name string?
---@return boolean
function M.exists(name)
  return name ~= nil and _registry[name] ~= nil
end

---Resolve a registered name to its decorator function. `nil` if `name` is
---nil/empty or was never registered.
---@param name string?
---@return Ui.Tabline.StyleFn?
function M.resolve(name)
  if not name or name == "" then
    return nil
  end
  return _registry[name]
end

return M
