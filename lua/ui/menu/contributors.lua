---@module 'ui.menu.contributors'
--- What sister plugins (and the user) add to the menu, and when they are left
--- out.
---
--- A contributor is a plugin that ships `<plugin>.integrations.menu` with a
--- `submenu()` (no trigger, no renderer dependency); this module composes it.
--- It appears only when ALL of these hold, each an opt-out that is on by default:
---
---  1. the plugin is installed (its module `require`s);
---  2. ui.nvim's side is not switched off:
---     `ui.setup({ menu = { integrations = { <name> = false } } })`
---     (or `integrations = false` for none at all);
---  3. the plugin's side is not switched off: its `submenu()` returns nil (no
---     entries), or its module offers `enabled()` and that returns false.
---     Plugins name that switch `integrations.ui_menu = false` in their own setup.
---
--- The user's own rows (`extra`) live here too, because they obey the same
--- kind of gating (`plugin` installed, `ft`, `when`).

local contextmenu = require("ui.contextmenu")
local icons = require("ui.menu.icons")
local notify = require("lib.nvim.notify").create("[ui.menu]")

local M = {}

---@param ft string|string[]|nil
---@param buf integer
---@return boolean
local function ft_matches(ft, buf)
  if ft == nil then
    return true
  end
  local cur = vim.bo[buf].filetype
  if type(ft) == "string" then
    return cur == ft
  end
  return vim.tbl_contains(ft, cur)
end

---@param name string
---@return boolean
local function installed(name)
  return package.loaded[name] ~= nil or pcall(require, name)
end

---@param ft string|nil
---@return boolean
local function is_markdown(ft)
  return ft == "markdown" or ft == "md" or ft == "mdx" or (ft or ""):match("^markdown%.") ~= nil
end

--- The contributors ui.nvim knows by name. `applies` is a cheap pre-check
--- (usually the filetype) that skips the `require` of a plugin that obviously
--- does not qualify.
---@type Ui.Menu.ContributorSpec[]
local BUILTIN = {
  {
    name = "markdown",
    module = "markdown.integrations.menu",
    applies = function(buf)
      return is_markdown(vim.bo[buf].filetype)
    end,
  },
  { name = "open", module = "open.integrations.menu" },
  { name = "dap", module = "wkddap.integrations.menu" },
  { name = "cascade", module = "cascade.integrations.menu" },
  { name = "fileops", module = "fileops.integrations.menu" },
  { name = "images", module = "images.integrations.menu" },
  { name = "spotlight", module = "spotlight.integrations.menu" },
  {
    name = "color_my_ascii",
    module = "color_my_ascii.integrations.menu",
    ft = "markdown",
  },
  { name = "lsp", module = "lsp.integrations.menu" },
  { name = "gopath", module = "gopath.integrations.menu" },
}

--- Contributors and rows added at runtime (`register`/`add`), kept apart from
--- the ones `setup` was given so a second `setup` does not drop them.
---@type Ui.Menu.ContributorSpec[]
local registered = {}
---@type Ui.Menu.Extra[]
local added = {}

--- Register another `<plugin>.integrations.menu`-style module.
---@param spec Ui.Menu.ContributorSpec
function M.register(spec)
  if type(spec) ~= "table" or type(spec.name) ~= "string" or type(spec.module) ~= "string" then
    notify.error("register_contributor: `name` and `module` are required")
    return
  end
  registered[#registered + 1] = spec
end

--- Add a row of your own.
---@param entry Ui.Menu.Extra
function M.add(entry)
  if type(entry) ~= "table" or type(entry.label) ~= "string" then
    notify.error("add: `label` is required")
    return
  end
  added[#added + 1] = entry
end

---@param cfg Ui.Menu.Opts
---@param name string
---@return boolean
local function integration_on(cfg, name)
  local i = cfg.integrations
  if i == false then
    return false
  end
  if type(i) == "table" and i[name] == false then
    return false
  end
  return true
end

--- One fly-out per applicable, installed, not-opted-out plugin.
---@param buf integer
---@param cfg Ui.Menu.Opts
---@return Ui.ContextMenu.Item[]
local function submenus(buf, cfg)
  local out = {}
  local specs = {}
  vim.list_extend(specs, BUILTIN)
  vim.list_extend(specs, cfg.contributors or {})
  vim.list_extend(specs, registered)

  for _, c in ipairs(specs) do
    if
      integration_on(cfg, c.name)
      and ft_matches(c.ft, buf)
      and (c.applies == nil or c.applies(buf))
    then
      local ok, mod = pcall(require, c.module)
      local enabled = ok and type(mod) == "table" and type(mod.submenu) == "function"
      if enabled and type(mod.enabled) == "function" then
        local ok_e, on = pcall(mod.enabled)
        enabled = ok_e and on ~= false
      end
      if enabled then
        local ok_s, sub = pcall(mod.submenu)
        if ok_s and sub then
          -- Only where the plugin named none of its own: the icon column
          -- belongs to whoever owns the entry.
          sub.icon = sub.icon or c.icon or icons[c.name] or icons.plugin
          out[#out + 1] = sub
        end
      end
    end
  end

  -- filetree.nvim: its own tree buffer binds its own <RightMouse>, so the one
  -- thing worth offering from ANY other buffer is a single row -- open (or
  -- close) the tree, revealing this buffer's file.
  if integration_on(cfg, "filetree") and installed("filetree.integrations.menu") then
    local ok, ft_menu = pcall(require, "filetree.integrations.menu")
    local on = ok and type(ft_menu.window_entry) == "function"
    if on and type(ft_menu.enabled) == "function" then
      local ok_en, answer = pcall(ft_menu.enabled)
      on = ok_en and answer ~= false
    end
    if on then
      local ok_e, item = pcall(ft_menu.window_entry, buf)
      if ok_e and item then
        item.icon = item.icon or icons.plugin
        out[#out + 1] = item
      end
    end
  end
  return out
end

--- A user row as a menu item, or nil when its gates say no.
---@param e Ui.Menu.Extra
---@param buf integer
---@return Ui.ContextMenu.Item|nil
local function extra_item(e, buf)
  if type(e) ~= "table" or type(e.label) ~= "string" or e.enabled == false then
    return nil
  end
  if not ft_matches(e.ft, buf) then
    return nil
  end
  local plugins = type(e.plugin) == "string" and { e.plugin } or e.plugin or {}
  for _, p in ipairs(plugins) do
    if not installed(p) then
      return nil
    end
  end
  if e.when then
    -- Yours to get wrong, not to take the menu down with.
    local ok, pass = pcall(e.when, buf)
    if not ok or not pass then
      return nil
    end
  end

  local action
  if type(e.cmd) == "function" then
    action = e.cmd
  elseif type(e.cmd) == "string" then
    action = function()
      local ok, err = pcall(function()
        vim.cmd(e.cmd)
      end)
      if not ok then
        notify.error(("%s: %s"):format(e.label, tostring(err)))
      end
    end
  elseif type(e.keys) == "string" then
    action = function()
      local keys = vim.api.nvim_replace_termcodes(e.keys, true, false, true)
      vim.api.nvim_feedkeys(keys, "m", false)
    end
  else
    return nil
  end
  return contextmenu.entry(true, e.label, action, e.hint, { icon = e.icon })
end

--- The plugin/user part of the menu: an "Integrations" section of fly-outs,
--- then one section per `section` name of the user's own rows.
---@param buf integer
---@param cfg Ui.Menu.Opts
---@return Ui.ContextMenu.Item[]
function M.build(buf, cfg)
  local out = {}

  local subs = submenus(buf, cfg)
  -- An "Integrations" frame with nothing in it must not be a state that can occur.
  if #subs > 0 then
    out[#out + 1] = contextmenu.heading("Integrations")
    vim.list_extend(out, subs)
  end

  local order, by_section = {}, {}
  local rows = {}
  vim.list_extend(rows, cfg.extra or {})
  vim.list_extend(rows, added)
  for _, e in ipairs(rows) do
    local item = extra_item(e, buf)
    if item then
      local s = e.section or "Custom"
      if not by_section[s] then
        by_section[s] = {}
        order[#order + 1] = s
      end
      table.insert(by_section[s], item)
    end
  end
  for _, s in ipairs(order) do
    out[#out + 1] = contextmenu.heading(s)
    vim.list_extend(out, by_section[s])
  end
  return out
end

--- The modules worth loading ahead of the first open: every contributor that
--- is not tied to a filetype (those load when a buffer of that type is
--- around), the filetree row, and the two modules the Tools section probes.
--- Whatever the switches already rule out is not loaded.
---@param cfg Ui.Menu.Opts
---@return string[]
function M.prewarm_modules(cfg)
  local out = {}
  local specs = {}
  vim.list_extend(specs, BUILTIN)
  vim.list_extend(specs, cfg.contributors or {})
  vim.list_extend(specs, registered)
  for _, c in ipairs(specs) do
    if integration_on(cfg, c.name) and c.ft == nil and c.applies == nil then
      out[#out + 1] = c.module
    end
  end
  if integration_on(cfg, "filetree") then
    out[#out + 1] = "filetree.integrations.menu"
  end
  local on = cfg.entries or {}
  local tools = (cfg.sections or {}).tools ~= false
  if on.git and tools then
    out[#out + 1] = "gitsuite.integrations.menu"
  end
  if on.unicode_table and tools then
    out[#out + 1] = "emojis.unicode"
  end
  return out
end

--- Load `modules` one per timer tick. Requiring a lazy plugin's menu module
--- loads the whole plugin (up to ~400 ms for the heavy ones), which is a stall
--- on the first right click; spread over idle ticks after startup it is not.
---@param modules string[]
---@param done? fun()  # called after the last one
---@param delay? integer  # ms before the first one (default 300)
function M.prewarm(modules, done, delay)
  local i = 0
  local function step()
    i = i + 1
    local name = modules[i]
    if not name then
      if done then
        done()
      end
      return
    end
    if package.loaded[name] == nil then
      pcall(require, name)
    end
    vim.defer_fn(step, 20)
  end
  vim.defer_fn(step, delay or 300)
end

--- Forget what `register`/`add` collected (tests).
function M.reset_runtime()
  registered = {}
  added = {}
end

return M
