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
local highlights = require("ui.statusline.highlights")
local layout = require("ui.statusline.layout")
local hover = require("ui.statusline.hover")
local clickable = require("ui.statusline.utils.clickable")

local M = {}

-- One `clickable` registry id per key that has ever needed the generic
-- right/double-click "manage this module" handler -- registered once, on
-- first use, and reused on every later redraw. `clickable.wrap` itself
-- cannot be called from inside `generate()` (its own doc comment: wrap at
-- module-load time, not per redraw, or the registry grows without bound),
-- which is exactly what calling it here on every single statusline redraw
-- would do -- this cache is what makes reusing the same protocol safe.
---@type table<string, integer>
local generic_click_ids = {}

---@param key string
---@return integer
local function generic_click_id(key)
  local id = generic_click_ids[key]
  if id then
    return id
  end
  id = clickable.register({
    r = function()
      require("ui.statusline.menu").open(key)
    end,
    dbl = function()
      require("ui.statusline.menu").open(key)
    end,
  })
  generic_click_ids[key] = id
  return id
end

-- `%#Group#` directives inside a rendered segment -- `%<id>@UiSlClick@` and
-- `%X` are never matched (no literal "#" pair), so this leaves click regions
-- (a module's own, or the generic one `generic_click_id` adds below) intact.
local HL_DIRECTIVE = "%%#([%w_]+)#"

---@param text string
---@return string
local function recolor_for_hover(text)
  return (
    text:gsub(HL_DIRECTIVE, function(group)
      return "%#" .. highlights.hover_variant(group) .. "#"
    end)
  )
end

--- Base module sets available as an `order` key's fallback, by theme name.
--- Only `default` exists -- see `ui.statusline.themes.default`'s own doc
--- comment for why `minimal`/`vscode`/`vscode_colored` are not ported.
---@type table<string, Ui.Statusline.ThemeModule>
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

--- IDEEN-statusline.md's "Adaptive Segmentauswahl nach Fensterbreite": drop
--- every catalog key NOT tagged `essential` while the statusline's own
--- window is narrower than `responsive_width`, instead of the alternative
--- this idea explicitly rejected -- a parallel "compact" `order` list a host
--- would have to hand-maintain per preset, drifting from the real one the
--- moment either changes.
---
--- Built lazily from `ui.statusline.catalog` (not required at module load:
--- `catalog.lua` requires nothing back from here, but resolving it only once
--- `responsive` is actually used keeps a host that never opts in from paying
--- for a table walk on every redraw).
---@type table<string, boolean>|nil
local essential_by_key = nil

---@param key string
---@return boolean
local function is_essential(key)
  if not essential_by_key then
    essential_by_key = {}
    for _, entry in ipairs(require("ui.statusline.catalog")) do
      essential_by_key[entry.key] = entry.essential == true
    end
  end
  local known = essential_by_key[key]
  -- A key the catalog does not know at all is a host's own custom module --
  -- kept rather than silently dropped, since this module has no basis to
  -- judge it either way.
  if known == nil then
    return true
  end
  return known
end

-- Whether an invalid `responsive_width` has already warned this session --
-- `should_go_compact` runs on every redraw, so this dedups the same way
-- `warn_once` below does for `order`/theme keys; kept as its own flag rather
-- than reordering this module to put that helper first.
local responsive_width_warned = false

---@param cfg Ui.Statusline.Config
---@return boolean
local function should_go_compact(cfg)
  if not cfg.responsive then
    return false
  end
  local winid = vim.g.statusline_winid or 0
  local ok, width = pcall(vim.api.nvim_win_get_width, winid)
  if not ok then
    return false
  end

  -- ERR-22: `responsive_width` is documented as a positive integer column
  -- count (docs/modules.md's "Responsive mode"), but `width < (cfg
  -- .responsive_width or 80)` only ever caught an ABSENT value -- a wrong
  -- type (or a non-positive number) reached this comparison unguarded.
  -- That matters more here than for a broken segment inside `M.generate`'s
  -- own `order` walk: every one of those calls is wrapped in its own
  -- `pcall` and blanks itself with a one-time warning, but `M.render()` --
  -- the zero-argument entrypoint Neovim's `'%!'` statusline option actually
  -- calls -- runs `should_go_compact` before any of that, with no pcall of
  -- its own. An invalid value here used to throw straight out of Neovim's
  -- statusline callback on every single redraw instead of degrading.
  local threshold = cfg.responsive_width
  if type(threshold) ~= "number" or threshold <= 0 then
    if threshold ~= nil and not responsive_width_warned then
      responsive_width_warned = true
      notify.warn(
        ("ui.statusline.render: responsive_width must be a positive number, got %s (%s) -- using the default (80)"):format(
          tostring(threshold),
          type(threshold)
        )
      )
    end
    threshold = 80
  end

  return width < threshold
end

---@param message string
---@param key string # de-duplicates on this, not on the message text
local function warn_once(key, message)
  if warned[key] then
    return
  end
  warned[key] = true
  notify.warn(message)
end

---@type table<string, Ui.Statusline.CatalogEntry>|nil
local catalog_by_key = nil

---@param key string
---@return Ui.Statusline.CatalogEntry|nil
local function catalog_entry(key)
  if not catalog_by_key then
    catalog_by_key = {}
    for _, entry in ipairs(require("ui.statusline.catalog")) do
      catalog_by_key[entry.key] = entry
    end
  end
  return catalog_by_key[key]
end

--- Make `entry.key` resolvable by `M.generate()`, requiring its module in
--- if it is a standalone one `cfg.modules` does not have yet. A builtin key
--- resolves against `ui.statusline.themes.default` with no `modules` entry
--- at all (see `ui.statusline.catalog`'s own doc comment on `builtin`), so
--- there is nothing to do for those beyond `order` membership itself.
---
--- Exported (not local) for `ui.statusline.menu.add_module` -- the "Add
--- module" menu entry needs the exact same "does this key need its module
--- required in" logic `apply_saved_order` below already has, and neither
--- side should drift from the other.
---@param cfg Ui.Statusline.Config
---@param entry Ui.Statusline.CatalogEntry
---@return boolean ok, string|nil err
function M.ensure_module_loaded(cfg, entry)
  if entry.builtin or not entry.source then
    return true
  end
  cfg.modules = cfg.modules or {}
  if cfg.modules[entry.key] ~= nil then
    return true
  end
  local ok, mod = pcall(require, entry.source)
  if not ok then
    return false, tostring(mod)
  end
  cfg.modules[entry.key] = mod
  return true
end

-- Whether the saved layout has already been restored once this "session"
-- (the stretch between an `enable()` and the `disable()` that ends it) --
-- see `apply_saved_order`'s own doc comment for why this matters at all.
---@type boolean
local restored_saved_order = false

--- Restore `order` from `ui.statusline.state`'s saved file onto `cfg`, if
--- one exists and this is the first `enable()` since the last `disable()`
--- (i.e. an actual start, not a later `:UI variant`/menu-driven re-`enable()`
--- within the same running session) -- a no-op otherwise, or when nothing
--- was ever saved (`state.read()` returns nil), costing one file stat and
--- nothing else.
---
--- BUG this guard fixes: applying the saved `order` on EVERY `enable()` call
--- meant that once a layout had ever been saved, `:UI variant <name>` -- and
--- the "Add module"/"Remove" menu, mutating `cfg.order` only for the very
--- config `apply_saved_order` was about to stomp right back over -- stopped
--- visibly doing anything: every one of those calls reaches `enable()`
--- again, and the saved file would win every single time regardless of what
--- was just switched to. "Saved layout wins on the next start, but not
--- forever" is what `ui.statusline.menu`'s own "restored on every future
--- start" notification promises -- restoring on every `enable()` instead
--- broke that promise the moment a host (or `:UI variant`) called it twice.
---
--- A catalog key the saved list names that also needs a standalone module
--- gets it required in via `M.ensure_module_loaded`; a key the saved list
--- names that resolves to neither a catalog entry nor an existing
--- `cfg.modules` entry is left to `M.generate()`'s own "no module for %q"
--- warn-once -- not this function's job to catch.
---
--- Deliberately NOT routed through `ui.statusline.menu` (which would also
--- reach `ui.contextmenu`/`ui.kit.menu` behind it): this runs on every
--- `enable()`, including a plain startup that never opens a menu at all, and
--- `ui.statusline.state`'s own file I/O is all it actually needs.
---@param cfg Ui.Statusline.Config
---@return nil
local function apply_saved_order(cfg)
  if restored_saved_order then
    return
  end
  restored_saved_order = true

  local saved = require("ui.statusline.state").read()
  if not saved then
    return
  end

  for _, key in ipairs(saved.order) do
    if key ~= "%=" then
      local entry = catalog_entry(key)
      if entry then
        local ok, err = M.ensure_module_loaded(cfg, entry)
        if not ok then
          warn_once(
            "saved-layout:" .. key,
            ("ui.statusline.render: saved layout could not load %q: %s"):format(
              entry.source,
              tostring(err)
            )
          )
        end
      end
    end
  end

  cfg.order = saved.order
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

  if should_go_compact(cfg) then
    local compact = {}
    for _, key in ipairs(order) do
      if key == "%=" or is_essential(key) then
        compact[#compact + 1] = key
      end
    end
    order = compact
  end

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

  local hovered_key = hover.current_key()
  ---@type table<string, string>
  local rendered_by_key = {}

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

      ---@type string|nil
      local rendered = nil
      if type(mod) == "function" then
        local ok, out = pcall(mod)
        if ok then
          rendered = out
        else
          warn_once(
            "error:" .. key,
            ("ui.statusline.render: module %q errored: %s"):format(key, tostring(out))
          )
        end
      elseif type(mod) == "string" then
        rendered = mod
      else
        warn_once(
          "missing:" .. key,
          ("ui.statusline.render: no module for %q -- rendering it empty"):format(key)
        )
      end

      if rendered and rendered ~= "" then
        if key == hovered_key then
          rendered = recolor_for_hover(rendered)
        end
        -- A module already wrapped in its own click protocol (git_clickable,
        -- diagnostics_clickable, variant, ...) keeps whatever handlers it
        -- registered for itself; only a plain segment gets the generic
        -- "manage this module" one, so nothing here overrides a module's own
        -- right/double click.
        if not rendered:find("@UiSlClick@", 1, true) then
          rendered = "%" .. generic_click_id(key) .. "@UiSlClick@" .. rendered .. "%X"
        end
        rendered_by_key[key] = rendered
      end

      result[#result + 1] = rendered or ""
    end
  end

  layout.record(vim.g.statusline_winid or 0, order, rendered_by_key)

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
--- its own. A saved layout (`ui.statusline.state`, `apply_saved_order`) is
--- restored only on the FIRST call after `disable()` (or ever), not on a
--- later variant switch within the same session -- see that function's own
--- doc comment for why.
---@param cfg Ui.Statusline.Config
---@return nil
function M.enable(cfg)
  apply_saved_order(cfg)

  current = cfg
  highlights.ensure()
  vim.o.statusline = "%!v:lua.require('ui.statusline.render').render()"
  primitives.autocmds()
  hover.enable()
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
  hover.disable()
  -- The next `enable()` is a fresh start again (see `apply_saved_order`'s
  -- own doc comment on why "only the first `enable()`" matters at all).
  restored_saved_order = false
end

--- The config `enable()` last stored, or nil. For tests and `:checkhealth`
--- -- not meant as something a variant module reads.
---@return Ui.Statusline.Config|nil
function M.current()
  return current
end

return M
