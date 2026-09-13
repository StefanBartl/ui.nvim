---@module 'ui.statusline.modules.git_clickable'
--- The catalog's plain `git` segment (`ui.statusline.utils.primitives.git`),
--- wrapped with two mouse actions: a left click opens a dependency-free
--- branch switcher, a right click opens a context menu with the same switch
--- plus two read-only actions. Neither needs gitsigns or any git plugin
--- beyond a `git` executable on `$PATH` -- gitsigns.nvim is what
--- `primitives.git()`'s own rendered text needs, not this module's clicks.

local primitives = require("ui.statusline.utils.primitives")
local clickable = require("ui.statusline.utils.clickable")
local notify = require("lib.nvim.notify").create("[ui.statusline.modules.git_clickable]")

--- Every local branch, plus the current one if `git` reports one cleanly.
--- Empty list (not an error) outside a git repo or without `git` on `$PATH`
--- -- `vim.v.shell_error` is the only signal `systemlist` gives for that.
---@return string[] branches
---@return string|nil current
local function list_branches()
  local branches = vim.fn.systemlist({ "git", "branch", "--format=%(refname:short)" })
  if vim.v.shell_error ~= 0 then
    return {}, nil
  end

  local current_out = vim.fn.systemlist({ "git", "branch", "--show-current" })
  local current = (vim.v.shell_error == 0 and current_out[1] ~= "") and current_out[1] or nil
  return branches, current
end

---@param name string
---@return nil
local function checkout(name)
  local out = vim.fn.systemlist({ "git", "checkout", name })
  if vim.v.shell_error ~= 0 then
    notify.error(("git checkout %s failed: %s"):format(name, table.concat(out, "\n")))
    return
  end
  notify.info("Switched to branch " .. name)
end

--- Left click: a plain `vim.ui.select` over every local branch. No preview,
--- no fly-out -- `checkout` is a real filesystem/index operation, not
--- something to fire speculatively per row the way the theme picker's
--- `:colorscheme` preview can.
---@return nil
local function switch_branch()
  local branches, current = list_branches()
  if #branches == 0 then
    notify.warn("No git branches found (not a git repo, or git not on $PATH)")
    return
  end

  vim.ui.select(branches, {
    prompt = "Switch branch" .. (current and (" (current: " .. current .. ")") or ""),
  }, function(choice)
    if choice and choice ~= current then
      checkout(choice)
    end
  end)
end

--- Right click: the same switch, plus copy-branch-name and a details popup
--- -- `lib.nvim.contextmenu`, the same builder API every other menu in this
--- ecosystem uses, rather than a bespoke float.
---@return nil
local function open_context_menu()
  local ok, contextmenu = pcall(require, "lib.nvim.contextmenu")
  if not ok then
    return
  end

  local _, current = list_branches()
  local items = {}
  contextmenu.group(
    items,
    contextmenu.entry(true, "Branch wechseln", switch_branch),
    contextmenu.entry(current ~= nil, "Branch-Name kopieren", function()
      vim.fn.setreg("+", current)
      notify.info("Copied: " .. current)
    end),
    contextmenu.entry(true, "Details", function()
      local out = vim.fn.systemlist({ "git", "status", "--short", "--branch" })
      notify.info(table.concat(out, "\n"))
    end)
  )

  contextmenu.open(items)
end

return clickable.wrap(primitives.git, {
  l = switch_branch,
  r = open_context_menu,
})
