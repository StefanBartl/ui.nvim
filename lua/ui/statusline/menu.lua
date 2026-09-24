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
--- Add/remove changes are runtime-only, exactly like `:UI variant <name>`
--- (`ui.statusline.modules.variant`): they mutate the live
--- `Ui.Statusline.Config` table `ui.statusline.render.enable()` was last
--- given and trigger a redraw, but nothing is written back to a host's own
--- config -- a restart reverts to whatever `order`/`modules` the host's
--- `ui.config.setup()` call still says, UNLESS "Save current layout" (the
--- menu's own "Layout" group) was used -- that writes `order` to
--- `ui.statusline.state`'s JSON file, which `render.enable()` reads back and
--- applies on every future start ("Clear saved layout" deletes it again).

local contextmenu = require("ui.contextmenu")
local catalog = require("ui.statusline.catalog")
local state = require("ui.statusline.state")
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

--- Cut `text` to at most `max_width` display cells, on a character boundary
--- (not a byte one -- several catalog summaries carry multi-byte glyphs, and
--- a byte-index cut can land inside one of them; see the "Add module" row
--- below, and `ui.statusline.modules.formatters.ellipsize_middle` for the
--- same defect class fixed there).
---@param text string
---@param max_width integer
---@return string
local function truncate(text, max_width)
  if vim.fn.strdisplaywidth(text) > max_width then
    return vim.fn.strcharpart(text, 0, max_width - 1) .. "…"
  end
  return text
end

--- The first `n` words of `text`, stripped of trailing punctuation and
--- ellipsized if anything was cut -- used for the heading's "what is this"
--- hint, where a handful of words reads better than a character-count
--- truncation landing mid-word (`truncate` above, used for the "Add module"
--- row, cuts wherever the width runs out; a catalog summary is one long
--- sentence, so that lands inside a word as often as not).
---@param text string
---@param n integer
---@return string
local function short_words(text, n)
  local words = {}
  for word in text:gmatch("%S+") do
    words[#words + 1] = word
    if #words > n then
      break
    end
  end
  if #words <= n then
    return (text:gsub("[%.,]+$", ""))
  end
  words[n] = words[n]:gsub("[%.,]+$", "")
  return table.concat(words, " ", 1, n) .. "…"
end

--- The catalog entry for `key`, or nil for a host's own custom module (not
--- catalogued) -- mirrors `ui.statusline.hover`'s own lookup, kept separate
--- rather than shared since it is a handful of lines and the two modules
--- have no other coupling.
---@param key string
---@return Ui.Statusline.CatalogEntry|nil
local function catalog_entry_for(key)
  for _, entry in ipairs(catalog) do
    if entry.key == key then
      return entry
    end
  end
  return nil
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

  -- Shared with `ui.statusline.render`'s own saved-layout restore on
  -- `enable()`, so "does this key need its module required in" never
  -- drifts between the two call sites.
  local ok, err = require("ui.statusline.render").ensure_module_loaded(cfg, entry)
  if not ok then
    notify.error(("could not load %q: %s"):format(entry.source, tostring(err)))
    return
  end

  cfg.order[#cfg.order + 1] = entry.key
  notify.info(("Added %q to the statusline (this session only)"):format(entry.key))
  pcall(vim.cmd, "redrawstatus!")
end

---@return nil
local function save_current_layout()
  local cfg = active_cfg()
  if not cfg or not cfg.order or #cfg.order == 0 then
    return
  end
  local ok, err = state.write(cfg.order)
  if not ok then
    notify.error("could not save the statusline layout: " .. tostring(err))
    return
  end
  notify.info("Saved the current statusline layout -- restored on every future start")
end

---@return nil
local function clear_saved_layout()
  local ok, err = state.remove()
  if not ok then
    notify.error("could not clear the saved statusline layout: " .. tostring(err))
    return
  end
  notify.info("Cleared the saved statusline layout -- future starts use your normal config again")
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

  -- The heading names the module itself, so a short "what is this" rides
  -- along with it -- worth having for a module the user does not recognize
  -- at a glance, without repeating the full `hover` sentence right below
  -- where they just read it.
  local clicked = catalog_entry_for(key)
  local heading_text = clicked and (key .. " — " .. short_words(clicked.summary, 3)) or key

  contextmenu.group(
    items,
    contextmenu.heading(heading_text),
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
        -- what shows the whole summary (`ui.statusline.hover`). Measured and
        -- cut with `strdisplaywidth`/`strcharpart`, not `#`/`:sub` -- several
        -- summaries carry multi-byte glyphs (the traffic-light emoji, the
        -- macro-counter middle dot), and a byte-index cut can land inside
        -- one of them, same defect class `ui.statusline.modules.formatters`
        -- `ellipsize_middle` was fixed for (see TESTS/README.md).
        local short = truncate(entry.summary, 42)
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

  contextmenu.group(
    items,
    contextmenu.heading("Layout"),
    contextmenu.entry(
      cfg ~= nil and #(cfg.order or {}) > 0,
      "Save current layout",
      save_current_layout
    ),
    contextmenu.entry(state.read() ~= nil, "Clear saved layout", clear_saved_layout)
  )

  return items
end

--- Whether the last known mouse position was on a statusline module the
--- native click replay could actually have opened a menu for -- for a
--- host's own `<RightMouse>` dispatcher to step aside once it has replayed
--- the native click (mirrors `ui.tabline.menu.pointer_on_tabline()`; see
--- that function's own doc comment for why a dispatcher needs this check at
--- all rather than just always opening its general menu too).
---
--- Deliberately more than "is the pointer geometrically on the statusline
--- row": every rendered module carries a click region (`ui.statusline
--- .render`'s generic wrap, or a module's own), but the row itself is
--- wider than the modules on it -- the padding a `%=` expands into, or
--- trailing space past the last one. A click landing there has no region to
--- replay onto, so answering `true` for it purely from row geometry would
--- silence the host's own general menu for a click that neither menu ends
--- up opening. `ui.statusline.layout.key_at()` is what a real click region
--- is keyed on, so it is the more precise "was there actually something
--- here" check.
---@return boolean
function M.pointer_on_statusline()
  local target = require("ui.statusline.hover").pointer_target()
  if not target then
    return false
  end
  return require("ui.statusline.layout").key_at(target.winid, target.col, target.maxwidth) ~= nil
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
