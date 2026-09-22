---@module 'ui.statusline.modules.git_clickable'
--- The catalog's plain `git` segment (`ui.statusline.utils.primitives.git`),
--- wrapped with two mouse actions: a left click switches branches, a right
--- click opens a context menu with the same switch plus two read-only
--- actions. Neither needs gitsigns or any git plugin beyond a `git`
--- executable on `$PATH` -- gitsigns.nvim is what `primitives.git()`'s own
--- rendered text needs, not this module's clicks.
---
--- Branch listing/checkout go through `lib.nvim.git` (GS-15) instead of a
--- raw `vim.fn.systemlist`: the original had no `-C`/`opts.dir` support, and
--- `systemlist` folds a failed command's stderr into its output, so every
--- failure notification here quoted git's own diagnosis. `lib.nvim.git`'s
--- read helpers only ever capture stdout (nothing to quote on failure, by
--- their own doc comments), but `checkout` is the one exception -- it uses
--- `run_blocking`, which does capture stderr -- so a failed checkout still
--- names git's real reason.
---
--- Left click delegates to `gitsuite.features.branch.switch()` when
--- gitsuite.nvim is loaded (its own picker: pickers.nvim when available,
--- `vim.ui.select` otherwise, plus the `GitsuiteBranchSwitched` event other
--- plugins hook) -- soft, via `ui.util.soft_require`, never a hard
--- dependency (K-5c: the two plugins would otherwise reference each other,
--- ui.nvim -> gitsuite and gitsuite -> ui.contextmenu). Without gitsuite
--- this module keeps its own bare `vim.ui.select` picker, unchanged.

local git = require("lib.nvim.git")
local soft = require("ui.util.soft_require")
local primitives = require("ui.statusline.utils.primitives")
local clickable = require("ui.statusline.utils.clickable")
local notify = require("lib.nvim.notify").create("[ui.statusline.modules.git_clickable]")

--- Every local branch, plus the current one if `git` reports one cleanly.
---@return string[] branches
---@return string|nil current
local function list_branches()
  local branches = git.refs(nil, { branches = true, remotes = false, tags = false })
  local current = git.current_branch()
  return branches, current
end

---@param name string
---@return nil
local function checkout(name)
  local ok, err = git.checkout(name)
  if not ok then
    notify.error(("git checkout %s failed: %s"):format(name, err))
    return
  end
  notify.info("Switched to branch " .. name)
end

--- The bare fallback picker: a plain `vim.ui.select` over every local
--- branch. No preview, no fly-out -- `checkout` is a real filesystem/index
--- operation, not something to fire speculatively per row the way the theme
--- picker's `:colorscheme` preview can.
---
--- Used only when gitsuite.nvim is not loaded -- see `switch_branch` below.
---@return nil
local function select_and_checkout()
  local branches, current = list_branches()
  if #branches == 0 then
    if git.in_git_repo() then
      notify.warn("No git branches found (repository has no commits yet)")
    else
      notify.warn("No git branches found (not a git repo, or git not on $PATH)")
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

--- Left click / context-menu "Switch branch": `gitsuite.features.branch.switch()`
--- when gitsuite.nvim is loaded, `select_and_checkout` above otherwise.
---@return nil
local function switch_branch()
  local gitsuite_branch = soft.try("gitsuite.features.branch")
  if gitsuite_branch then
    gitsuite_branch.switch()
    return
  end
  select_and_checkout()
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

-- No `dbl` handler: Neovim's click protocol calls this function once per
-- physical click, `clicks` naming which one it was, NOT once per completed
-- gesture -- the first click of a double click still fires with clicks == 1
-- before the second one arrives with clicks == 2 (the exact "warn if you
-- map both <LeftMouse> and <2-LeftMouse>" gotcha, here in the statusline
-- click protocol's own numbering rather than a keymap). A `dbl` here would
-- have opened `ui.statusline.menu` on top of the branch switcher
-- (this module's own `l`) just opened for that same gesture's first click.
-- Right click already reaches a menu (this module's own, below) without
-- that collision, so double click is left to just run `l` again --
-- redundant with a plain second click, but never two floats fighting over
-- the same gesture.
return clickable.wrap(primitives.git, {
  l = switch_branch,
  r = open_context_menu,
})
