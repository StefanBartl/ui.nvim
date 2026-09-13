---@module 'ui.statusline.modules.plugin_summary'
--- Statusline segment: how many plugins lazy.nvim manages, split into "own"
--- (the personal StefanBartl/*.nvim repos declared in `plugins.personal` —
--- the same canonical, drift-proof list `:MyPlugins clone`/`remove` use, see
--- `plugins.personal.list`) and "external" (everything else).
--- Explicit by construction: the split can never silently drift out of sync
--- with what is actually loaded, unlike a hand-maintained plugin name list in
--- a comment (see the fix to this sibling module's own docstring).
---
--- Unlike `plugin_progress` (transient, only visible while something is
--- running), this is a static badge, shown once lazy.nvim has loaded.
---
--- `require("lazy").stats().count` is cheap to read on every redraw; the
--- own/external split is only re-derived when that count actually changes
--- (e.g. after `:Lazy install`/`:Lazy clean`), so a normal redraw never walks
--- the personal plugin spec.

--- Total plugin count the cached text was last derived from.
---@type integer|nil
local cached_total = nil
local cached_text = ""

---@param total integer
---@return string
local function compute_text(total)
  local ok_list, list = pcall(require, "plugins.personal.list")
  local entries = ok_list and select(1, list.read()) or nil
  local own = entries and #entries or 0
  return ("%d/%d"):format(own, math.max(total - own, 0))
end

return function()
  local ok_lazy, lazy = pcall(require, "lazy")
  if not ok_lazy then
    return ""
  end

  local total = lazy.stats().count
  if total ~= cached_total then
    cached_total = total
    cached_text = compute_text(total)
  end

  -- Same "lazy" glyph lazy.nvim's own UI uses (see lua/config/lazy/init.lua's
  -- ui.icons.lazy), so this badge reads as "lazy.nvim's plugin count" at a
  -- glance. Same highlight convention as plugin_progress.
  return " %#St_LspProgress#󰂠 " .. cached_text .. " "
end
