---@module 'ui.slots.bindings'
--- The keymaps and autocommands of `ui.slots`, created when the feature is
--- switched on and removed when it is switched off -- nothing here exists
--- before `attach()`, and `detach()` leaves nothing behind.
---
--- Keymaps come only from the `keys` option; with `keys = {}` (the default)
--- no key is mapped at all:
---
---   * `apply`  -- a pattern with one `%d`, e.g. `"<leader>%d"`: maps slots 1 to 9;
---   * `count`  -- one key that takes a count, `12<leader>s` applies slot 12;
---   * `add`    -- put the current file into the next free slot;
---   * `panel`  -- open the slot panel.
---
--- A value of `false` (or an absent key) maps nothing.

local autocmd = require("lib.nvim.bindings.autocmd")
local config = require("ui.slots.config")
local util = require("ui.slots.util")

local M = {}

local GROUP = "ui_slots"

--- Slots a digit key can reach.
local DIRECT = 9

---@type { mode: string, lhs: string }[]
local mapped = {}

--- A leader as Neovim reads it: unset or empty means a backslash.
---@param value any
---@return string
local function leader(value)
  if type(value) ~= "string" or value == "" then
    return "\\"
  end
  return value
end

---@param lhs string
---@param rhs function
---@param desc string
local function map(lhs, rhs, desc)
  -- The leaders are put in now: `vim.keymap.del("<leader>1")` later would
  -- look for whatever the leader is by then and miss the mapping.
  local expanded = lhs
    :gsub("<[Ll]eader>", function()
      return leader(vim.g.mapleader)
    end)
    :gsub("<[Ll]ocal[Ll]eader>", function()
      return leader(vim.g.maplocalleader)
    end)
  vim.keymap.set("n", expanded, rhs, { desc = desc, silent = true })
  mapped[#mapped + 1] = { mode = "n", lhs = expanded }
end

--- What is wrong with the `keys` option, as strings.
---@param keys table
---@return string[]
function M.issues(keys)
  local out = {}
  for name, lhs in pairs(keys) do
    if name ~= "apply" and name ~= "count" and name ~= "add" and name ~= "panel" then
      out[#out + 1] = ("keys.%s: unknown key (apply, count, add, panel)"):format(tostring(name))
    elseif lhs ~= false then
      if type(lhs) ~= "string" or lhs == "" then
        out[#out + 1] = ("keys.%s: %s is not a key sequence or false"):format(
          name,
          vim.inspect(lhs)
        )
      elseif name == "apply" and select(2, lhs:gsub("%%d", "")) ~= 1 then
        out[#out + 1] = 'keys.apply: needs exactly one %d, e.g. "<leader>%d"'
      end
    end
  end
  return out
end

---@param api { apply: fun(n: integer, opts: table|nil), add: fun(), panel: fun() }
function M.attach(api)
  M.detach()
  local cfg = config.get()
  local keys = cfg.keys

  for _, issue in ipairs(M.issues(keys)) do
    util.notify(issue)
  end

  local apply = keys.apply
  if type(apply) == "string" and select(2, apply:gsub("%%d", "")) == 1 then
    for n = 1, DIRECT do
      map(apply:gsub("%%d", tostring(n)), function()
        api.apply(n)
      end, ("ui.slots: apply slot %d"):format(n))
    end
  end

  if type(keys.count) == "string" and keys.count ~= "" then
    map(keys.count, function()
      local n = vim.v.count
      if n == 0 then
        util.notify("give the slot number as a count, e.g. 12" .. keys.count)
        return
      end
      api.apply(n)
    end, "ui.slots: apply the slot given as a count")
  end

  if type(keys.add) == "string" and keys.add ~= "" then
    map(keys.add, function()
      api.add()
    end, "ui.slots: put the current file into the next free slot")
  end

  if type(keys.panel) == "string" and keys.panel ~= "" then
    map(keys.panel, function()
      api.panel()
    end, "ui.slots: open the slot panel")
  end

  local group = autocmd.group(GROUP, true)
  local store = require("ui.slots.store")

  -- The project scope follows the working directory.
  autocmd.create("DirChanged", function()
    -- Only when another project's file applies: not for :lcd inside the same
    -- project, and not when nothing is persisted (a reload would drop the
    -- slots of this session).
    if config.get().scope == "project" and store.scope_changed() then
      store.reload()
    end
  end, { group = group, desc = "ui.slots: load the slots of the new project" })

  -- Pending changes reach the disk before Neovim goes.
  autocmd.create("VimLeavePre", function()
    -- BufLeave does not fire on exit: the file you quit from is remembered here.
    pcall(require("ui.slots.kinds.file").remember_current)
    store.flush()
  end, { group = group, desc = "ui.slots: write pending slot changes" })

  -- Where the cursor was when a file slot's file was left.
  autocmd.create("BufLeave", function()
    require("ui.slots.kinds.file").remember_current()
  end, { group = group, desc = "ui.slots: remember the cursor of a slot's file" })
end

--- Remove every keymap and autocommand `attach()` made.
function M.detach()
  for _, m in ipairs(mapped) do
    pcall(vim.keymap.del, m.mode, m.lhs)
  end
  mapped = {}
  -- An empty group again: clearing also drops the autocmd records.
  autocmd.group(GROUP, true)
end

--- The keys currently mapped (for tests and the health check).
---@return string[]
function M.mapped()
  return vim.tbl_map(function(m)
    return m.lhs
  end, mapped)
end

return M
