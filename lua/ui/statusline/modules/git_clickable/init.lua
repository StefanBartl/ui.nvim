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
--- An empty list is not by itself an error -- a repository with no commits
--- yet is empty and fine. When `git` itself failed (not a repo, not on
--- `$PATH`, ...), `err` carries what it printed (`systemlist` captures it
--- the same way `checkout()` below already relies on) so the two "empty"
--- cases stay distinguishable instead of colliding on the same bare `{}`.
---@return string[] branches
---@return string|nil current
---@return string|nil err # non-nil only when the `git branch` call itself failed
local function list_branches()
  local branches = vim.fn.systemlist({ "git", "branch", "--format=%(refname:short)" })
  if vim.v.shell_error ~= 0 then
    return {}, nil, table.concat(branches, "\n")
  end

  local current_out = vim.fn.systemlist({ "git", "branch", "--show-current" })
  local current = (vim.v.shell_error == 0 and current_out[1] ~= "") and current_out[1] or nil
  return branches, current, nil
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
  local branches, current, err = list_branches()
  if #branches == 0 then
    if err then
      notify.warn(("No git branches found (not a git repo, or git not on $PATH): %s"):format(err))
    else
      notify.warn("No git branches found (repository has no commits yet)")
    end
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
--- -- `ui.contextmenu`, this plugin's own builder API and the one every
--- sibling migrated to, rather than a bespoke float.
---
--- Required here rather than at module load: this file is pulled in on the
--- first statusline redraw, and `ui.contextmenu` reaches `ui.kit.menu`
--- behind it -- no reason to pay for the kit unless someone right-clicks.
---
--- It used to require `lib.nvim.contextmenu`, the pre-migration copy. That
--- was not only the wrong module but the wrong *behaviour*: the lib copy has
--- no `set_enabled`, so a host that had switched the menu off with
--- `ui.setup({ menu = false })` still got one here.
---@return nil
local function open_context_menu()
  local contextmenu = require("ui.contextmenu")

  local _, current = list_branches()
  local items = {}
  contextmenu.group(
    items,
    contextmenu.entry(true, "Switch branch", switch_branch),
    contextmenu.entry(current ~= nil, "Copy branch name", function()
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
