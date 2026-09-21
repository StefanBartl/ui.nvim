---@module 'ui.statusline.menu'
--- The right/double-click "manage this statusline" menu: remove the module
--- that was clicked, or add any other catalogued one. Reached from a native
--- statusline click region (either a module's own, like
--- `ui.statusline.modules.git_clickable`, or the generic one
--- `ui.statusline.render` adds to every module that has none of its own --
--- see that module's `generate()`), so unlike `ui.tabline.menu` this needs
--- no pointer hit-testing of its own to know which module was clicked; the
--- click protocol already hands that over as `key`.
---
--- Changes are runtime-only, exactly like `:UI variant <name>` (`ui.statusline
--- .modules.variant`): they mutate the live `Ui.Statusline.Config` table
--- `ui.statusline.render.enable()` was last given and trigger a redraw, but
--- nothing is written back to a host's own config -- a restart reverts to
--- whatever `order`/`modules` the host's `ui.config.setup()` call still says.

local contextmenu = require("ui.contextmenu")
local catalog = require("ui.statusline.catalog")
local notify = require("lib.nvim.notify").create("[ui.statusline.menu]")

local M = {}

---@return Ui.Statusline.Config|nil
local function active_cfg()
  return require("ui.statusline.render").current()
end

---@param cfg Ui.Statusline.Config
---@param key string
---@return boolean
local function in_order(cfg, key)
  return vim.tbl_contains(cfg.order or {}, key)
end

---@param entry Ui.Statusline.CatalogEntry
---@return nil
local function add_module(entry)
  local cfg = active_cfg()
  if not cfg then
    return
  end
  cfg.order = cfg.order or {}
  if in_order(cfg, entry.key) then
    return
  end

  -- A builtin key resolves against `ui.statusline.themes.default` with no
  -- `modules` entry at all (see `ui.statusline.catalog`'s own doc comment on
  -- `builtin`); a standalone one needs its module required in explicitly, or
  -- `render.generate()` would warn "no module for %q" on every redraw.
  if not entry.builtin and entry.source then
    cfg.modules = cfg.modules or {}
    if cfg.modules[entry.key] == nil then
      local ok, mod = pcall(require, entry.source)
      if not ok then
        notify.error(("could not load %q: %s"):format(entry.source, tostring(mod)))
        return
      end
      cfg.modules[entry.key] = mod
    end
  end

  cfg.order[#cfg.order + 1] = entry.key
  notify.info(("Added %q to the statusline (this session only)"):format(entry.key))
  pcall(vim.cmd, "redrawstatus!")
end

---@param key string
---@return nil
local function remove_module(key)
  local cfg = active_cfg()
  if not cfg or not cfg.order then
    return
  end
  for i, k in ipairs(cfg.order) do
    if k == key then
      table.remove(cfg.order, i)
      notify.info(("Removed %q from the statusline (this session only)"):format(key))
      pcall(vim.cmd, "redrawstatus!")
      return
    end
  end
end

--- The menu for a right/double click that landed on `key`'s rendered text.
---@param key string
---@return Ui.ContextMenu.Item[]
function M.items(key)
  local cfg = active_cfg()
  local items = {}

  contextmenu.group(
    items,
    contextmenu.heading(key),
    contextmenu.entry(cfg ~= nil and in_order(cfg, key), "Remove " .. key, function()
      remove_module(key)
    end)
  )

  local add_items = {}
  if cfg then
    for _, entry in ipairs(catalog) do
      if not in_order(cfg, entry.key) then
        -- Truncated rather than the full sentence: this is a menu row, not
        -- `:UI modules`'s listing -- hovering the module once it's added is
        -- what shows the whole summary (`ui.statusline.hover`).
        local short = entry.summary
        if #short > 42 then
          short = short:sub(1, 41) .. "…"
        end
        add_items[#add_items + 1] = contextmenu.entry(
          true,
          entry.key .. " — " .. short,
          function()
            add_module(entry)
          end
        )
      end
    end
  end
  contextmenu.group(items, contextmenu.submenu("Add module", add_items))

  return items
end

--- Whether the last known mouse position was on the statusline -- for a
--- host's own `<RightMouse>` dispatcher to step aside once it has replayed
--- the native click (mirrors `ui.tabline.menu.pointer_on_tabline()`; see
--- that function's own doc comment for why a dispatcher needs this check at
--- all rather than just always opening its general menu too).
---@return boolean
function M.pointer_on_statusline()
  return require("ui.statusline.hover").pointer_target() ~= nil
end

--- Open the menu for `key`, built fresh from the live config so it always
--- reflects the most recent add/remove.
---@param key string
---@return nil
function M.open(key)
  local items = M.items(key)
  if #items == 0 then
    return
  end
  contextmenu.open(items, { mouse = true })
end

return M
