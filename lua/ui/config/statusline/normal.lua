---@module 'ui.config.statusline.normal'
--- Default NvChad statusline, plus three additions: the replacer.nvim progress
--- component, filetree.nvim's cwd-mode badge, and the cursor_ctl row/column
--- progress indicator. NvChad's `nvchad.stl.utils.generate()` falls back to
--- its own built-in "default" theme order/modules whenever `order`/`modules`
--- are nil (see nvchad/stl/default.lua + nvchad/stl/utils.lua in the "ui"
--- plugin) — so this must spell out that same default order explicitly to
--- extend it, rather than leaving it nil like before.

local lazy = require("lib.lua.lazy")
local render_module = lazy.require("ui.statusline.cursor_ctl.renderer")
local progr_calc_module = lazy.require("ui.statusline.cursor_ctl.progress_calculators")
local cursor_module = lazy.require("ui.statusline.cursor_ctl")
local filetree_cwd_mode = lazy.require("ui.statusline.modules.filetree_cwd_mode")

local M = {}

-- Mirrors nvchad.stl.utils' `orders.default`, with two insertions. The `%=`
-- entries are the alignment breaks, so the list is really three groups:
-- left (up to the first `%=`), centre, right (after the second).
--
--   filetree_cwd_mode  last in the LEFT group — it belongs with mode/file/git,
--                      which describe the current buffer's context. Putting it
--                      in the right group left it floating at that group's
--                      leading edge, since diagnostics/lsp/plugin_progress
--                      are all empty most of the time.
--   plugin_progress    right group, before "cwd" — transient status, same
--                      neighbourhood as the other transient indicators. Shows
--                      whichever plugin is currently running a long operation,
--                      not one specific plugin.
--   plugin_summary     right group, right after plugin_progress — static
--                      own/external plugin count badge, same neighbourhood
--                      since both describe "the plugin layer", one transient
--                      one static.
--
-- If NvChad ever changes its own default order, update this list to match
-- (see nvchad/stl/utils.lua).
local order = {
  "mode",
  "file",
  "git",
  "filetree_cwd_mode",
  "%=",
  "lsp_msg",
  "%=",
  "diagnostics",
  "lsp",
  "plugin_progress",
  "cwd",
  "cursor",
}

M.ui = {
  statusline = {
    order = order,
    modules = {
      -- Only "plugin_progress", "plugin_summary" and "filetree_cwd_mode" are
      -- provided here; every other key in `order` above resolves to NvChad's
      -- own built-in "default" theme module (mode/file/git/lsp_msg/
      -- diagnostics/lsp/cwd/cursor), which `generate()` merges this table
      -- into rather than replaces.
      plugin_progress = require("ui.statusline.modules.plugin_progress"),
      -- plugin_summary = require("ui.statusline.modules.plugin_summary"),

      -- The label itself (PROJECT/PKG/LOCK/… vs P/N/L/… vs 1/2/3/… vs a Nerd
      -- Font glyph) is filetree's own `features.cwd_mode.indicator.style`
      -- (see lua/plugins/personal/init.lua) — this only controls how THIS
      -- statusline renders whatever text that produces.
      filetree_cwd_mode = function()
        return filetree_cwd_mode({
          badge_style = true, -- bg-filled capsule + fading separator, like `mode`. false = plain colored text.
          -- colors = { lock = "orange" },  -- override the accent per cwd mode; see the module's DEFAULT_COLOR_BY_MODE.
        })
      end,

      -- Overrides NvChad's built-in `cursor` (a fixed "%l/%v" string) with the
      -- cursor_ctl one, so the row/column progress indicator works in this
      -- variant too — it only ever lived in `custom.lua`, and was therefore
      -- lost when STATUSLINE_VARIANT switched to "normal". Uses the default
      -- theme's own separator/highlight groups (St_pos_*), not custom.lua's
      -- `get_separators()`, which is tied to `separator_style = "round"`.
      cursor = function()
        local mode = cursor_module.get_mode()
        if mode == "off" then
          return ""
        end

        -- Same left separator NvChad's own default `cursor` uses, resolved the
        -- same way (nvchad/stl/default.lua lines 5-8) so it tracks whatever
        -- `separator_style` is configured instead of hardcoding one glyph.
        local sep_style = require("nvconfig").ui.statusline.separator_style
        local sep_icons = require("nvchad.stl.utils").separators
        local separators = (type(sep_style) == "table" and sep_style) or sep_icons[sep_style]
        local sep_l = separators["left"]

        local pieces = { render_module.cursor_classic() }

        if mode == "row_progress" then
          pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
        elseif mode == "col_progress" then
          pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
        elseif mode == "rows_cols_progress" then
          pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
          pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
        end

        return "%#St_pos_sep#"
          .. sep_l
          .. "%#St_pos_icon# %#St_pos_text#"
          .. table.concat(pieces, "")
      end,
    },
  },
}

return M
