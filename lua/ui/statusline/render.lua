---@module 'ui.statusline.render'
--- This plugin's own statusline render entrypoint -- `vim.o.statusline` and
--- the `order`/`modules` walk that used to be entirely NvChad's:
--- `nvchad/init.lua` set `vim.o.statusline = "%!v:lua.require('nvchad.stl.' ..
--- theme .. '')()"`, and `nvchad/stl/<theme>.lua` called
--- `nvchad.stl.utils.generate(order, modules)`. Neither exists in this
--- plugin's own code before step 4 of the roadmap -- `ui.config.setup()`
--- assembles the `{order, modules, theme, separator_style}` table, but
--- nothing turns it into a rendered line without NvChad in between.
---
--- `M.generate(cfg)` is that walk, pure and independently testable. `M.enable`
--- / `M.render` / `M.disable` are the thin `vim.o.statusline` wiring around
--- it -- `render()` is the zero-argument function `'%!'` calls on every
--- redraw, so it takes nothing and reads whatever `enable()` last stored.
---
--- What this module does NOT do: decide when it runs. Calling `enable()` is
--- still opt-in -- a host wires it explicitly (see `ui.tabline.render`'s
--- identical shape, one option later), which is also what lets this
--- plugin's own spec suite prove the whole path works without NvChad on the
--- runtimepath at all.

local notify = require("lib.nvim.notify").create("[ui.statusline.render]")
local primitives = require("ui.statusline.utils.primitives")

local M = {}

--- Base module sets available as an `order` key's fallback, by theme name.
--- Only `default` exists -- see `ui.statusline.themes.default`'s own doc
--- comment for why `minimal`/`vscode`/`vscode_colored` are not ported.
---@type table<string, { build: fun(separator_style: any): table<string, fun(): string> }>
local THEMES = {
  default = require("ui.statusline.themes.default"),
}

-- Built theme-module tables are closures over one `separator_style`, so they
-- are cached per (theme name, separator_style) pair rather than rebuilt on
-- every redraw -- a statusline redraws on nearly every event.
---@type table<string, table<string, fun(): string>>
local theme_cache = {}

-- Which unresolvable `order` keys and theme names have already produced a
-- warning, so a key that is missing on every redraw says so once rather than
-- flooding `:messages`.
---@type table<string, true>
local warned = {}

---@param message string
---@param key string # de-duplicates on this, not on the message text
local function warn_once(key, message)
  if warned[key] then
    return
  end
  warned[key] = true
  notify.warn(message)
end

---@internal
--- Resolve the fallback module table for `theme_name` + `separator_style`,
--- or nil when the theme is not ported (warns once, by theme name).
---@param theme_name string|nil
---@param separator_style any
---@return table<string, fun(): string>|nil
local function resolve_theme(theme_name, separator_style)
  theme_name = theme_name or "default"
  local theme = THEMES[theme_name]
  if not theme then
    warn_once(
      "theme:" .. theme_name,
      ("ui.statusline.render: theme %q has no fallback module set -- "):format(theme_name)
        .. "an `order` key not covered by this variant's own `modules` will render empty. "
        .. "Only 'default' is ported; see ui.statusline.themes.default's doc comment."
    )
    return nil
  end

  local cache_key = theme_name .. "\0" .. tostring(separator_style)
  local built = theme_cache[cache_key]
  if not built then
    built = theme.build(separator_style)
    theme_cache[cache_key] = built
  end
  return built
end

--- Walk `cfg.order`, resolving each entry against `cfg.modules` first and
--- `cfg.theme`'s fallback module set second, and concatenate the result.
---
--- `"%="` (the statusline alignment break) passes through unresolved -- it
--- is not a module key, it is a literal Vim statusline directive, same as in
--- `nvchad.stl.utils.generate()`. A key resolving to neither a function nor
--- a string renders as empty and warns once rather than throwing: a broken
--- segment should blank itself, not take the rest of the statusline down
--- with it on every redraw.
---@param cfg Ui.Statusline.Config
---@return string
function M.generate(cfg)
  local order = cfg.order or {}
  local modules = cfg.modules or {}

  -- Resolved lazily, on the first key `modules` doesn't cover -- not
  -- upfront. A variant whose own `modules` already covers every key in
  -- `order` (most of them; see step 4's own note on `custom`/`custom_minimal`)
  -- never needs the fallback at all, so resolving it unconditionally meant
  -- every such variant paid `resolve_theme`'s cost, and any `cfg.theme` name
  -- with no ported fallback (e.g. "minimal") warned once per session for a
  -- theme value the render never actually reads. Found live: the personal
  -- variant sets `theme = "minimal"` purely as a label -- its own `modules`
  -- table already covers every key in its `order` -- and warned anyway.
  local theme_resolved = false
  local theme = nil
  local function fallback_theme()
    if not theme_resolved then
      theme_resolved = true
      theme = resolve_theme(cfg.theme, cfg.separator_style)
    end
    return theme
  end

  local result = {}
  for _, key in ipairs(order) do
    if key == "%=" then
      result[#result + 1] = key
    else
      local mod = modules[key]
      if mod == nil then
        local theme_mod = fallback_theme()
        mod = theme_mod and theme_mod[key]
      end

      if type(mod) == "function" then
        local ok, rendered = pcall(mod)
        if ok then
          result[#result + 1] = rendered
        else
          warn_once(
            "error:" .. key,
            ("ui.statusline.render: module %q errored: %s"):format(key, tostring(rendered))
          )
        end
      elseif type(mod) == "string" then
        result[#result + 1] = mod
      else
        warn_once(
          "missing:" .. key,
          ("ui.statusline.render: no module for %q -- rendering it empty"):format(key)
        )
      end
    end
  end

  return table.concat(result)
end

-- The config `enable()` last stored, and what the zero-argument `render()`
-- (the one `'%!'` actually calls) reads. nil until `enable()` runs, so an
-- accidental early call to `render()` blanks the statusline instead of
-- throwing.
---@type Ui.Statusline.Config|nil
local current = nil

--- Turn `cfg` into `vim.o.statusline` and start tracking LSP progress into
--- it. Safe to call more than once (a variant switch, a re-run in tests) --
--- each call replaces `current` and `primitives.autocmds()` is idempotent on
--- its own.
---@param cfg Ui.Statusline.Config
---@return nil
function M.enable(cfg)
  current = cfg
  vim.o.statusline = "%!v:lua.require('ui.statusline.render').render()"
  primitives.autocmds()
end

--- The zero-argument entrypoint `'%!'` calls on every redraw.
---@return string
function M.render()
  if not current then
    return ""
  end
  return M.generate(current)
end

--- Undo `enable()`: restore Neovim's own statusline and stop tracking the
--- config `render()` was reading. Does not unregister the `LspProgress`
--- autocmd -- it costs nothing while `current` is nil, and re-`enable()`ing
--- must not risk a duplicate handler by way of a would-be `disable()`
--- unregister racing a fresh `autocmds()` registration.
---@return nil
function M.disable()
  current = nil
  vim.o.statusline = ""
end

--- The config `enable()` last stored, or nil. For tests and `:checkhealth`
--- -- not meant as something a variant module reads.
---@return Ui.Statusline.Config|nil
function M.current()
  return current
end

return M
