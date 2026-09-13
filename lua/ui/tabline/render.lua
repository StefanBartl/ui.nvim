---@module 'ui.tabline.render'
--- This plugin's own tabline render entrypoint -- `vim.o.tabline` and the
--- `order`/`modules` walk that used to be entirely NvChad's:
--- `nvchad.tabufline.lazyload` set `vim.o.tabline =
--- "%!v:lua.require('nvchad.tabufline.modules')()"`. Same shape as
--- `ui.statusline.render`, one option later in the roadmap (step 7's tabline
--- gap) -- see that module's own doc comment for the reasoning this mirrors.
---
--- Unlike the statusline, there is no per-key "theme" fallback table: the
--- four built-in modules (`ui.tabline.modules`) already cover the only
--- shipped `order`, and a host wanting a different segment set overrides
--- `cfg.modules`/`cfg.order` directly rather than picking a named theme.

local notify = require("lib.nvim.notify").create("[ui.tabline.render]")
local highlights = require("ui.tabline.highlights")
local builtin = require("ui.tabline.modules")

local M = {}

-- Which unresolvable `order` keys have already warned, so a persistently
-- missing module says so once per session rather than on every redraw.
---@type table<string, true>
local warned = {}

---@param key string
---@param message string
local function warn_once(key, message)
  if warned[key] then
    return
  end
  warned[key] = true
  notify.warn(message)
end

--- Walk `cfg.order`, resolving each key against `cfg.modules` first and the
--- four built-in modules second, and concatenate the result. A key that
--- resolves to neither renders empty and warns once, same failure shape as
--- `ui.statusline.render.generate` -- a broken segment should blank itself,
--- not take the whole tabline down on every redraw.
---@param cfg Ui.Tabline.Config
---@return string
function M.generate(cfg)
  -- No baked-in default order here, deliberately -- same as
  -- `ui.statusline.render.generate`: the shipped order lives in
  -- `ui.config.tabline`, one layer up, so an empty `cfg` renders empty
  -- rather than silently picking up a default this module would then be a
  -- second place that order could drift from.
  local order = cfg.order or {}
  local overrides = cfg.modules or {}

  local result = {}
  for _, key in ipairs(order) do
    local mod = overrides[key] or builtin[key]

    if type(mod) == "function" then
      local ok, rendered = pcall(mod, cfg)
      if ok then
        result[#result + 1] = rendered
      else
        warn_once(
          "error:" .. key,
          ("ui.tabline.render: module %q errored: %s"):format(key, tostring(rendered))
        )
      end
    elseif type(mod) == "string" then
      result[#result + 1] = mod
    else
      warn_once(
        "missing:" .. key,
        ("ui.tabline.render: no module for %q -- rendering it empty"):format(key)
      )
    end
  end

  return table.concat(result)
end

-- The config `enable()` last stored, and what the zero-argument `render()`
-- (the one `'%!'` actually calls) reads. nil until `enable()` runs.
---@type Ui.Tabline.Config|nil
local current = nil

--- Turn `cfg` into `vim.o.tabline`, make `vim.o.showtabline` unconditional
--- (`2`, always shown -- NvChad's own `lazyload` option is not ported; a
--- tabline that appears/disappears as buffers are opened is a bigger
--- surprise than one that is always there), and bring up the `UiTb*`
--- highlight groups. Safe to call more than once.
---@param cfg Ui.Tabline.Config
---@return nil
function M.enable(cfg)
  current = cfg
  highlights.ensure()
  vim.o.showtabline = 2
  vim.o.tabline = "%!v:lua.require('ui.tabline.render').render()"
end

--- The zero-argument entrypoint `'%!'` calls on every redraw.
---@return string
function M.render()
  if not current then
    return ""
  end
  return M.generate(current)
end

--- Undo `enable()`: restore Neovim's own tabline and stop tracking the
--- config `render()` was reading.
---@return nil
function M.disable()
  current = nil
  vim.o.tabline = ""
end

--- The config `enable()` last stored, or nil. For tests and `:checkhealth`.
---@return Ui.Tabline.Config|nil
function M.current()
  return current
end

return M
