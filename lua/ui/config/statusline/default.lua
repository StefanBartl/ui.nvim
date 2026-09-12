---@module 'ui.config.statusline.default'
--- Full-featured generic preset: NvChad's own historical default order, plus
--- a plugin-progress indicator and the cursor_ctl row/column progress
--- indicator. NvChad's `nvchad.stl.utils.generate()` used to fall back to
--- its own built-in "default" theme order/modules whenever `order`/`modules`
--- were nil (see nvchad/stl/default.lua + nvchad/stl/utils.lua in the "ui"
--- plugin) — this spells out that same default order explicitly.
---
--- Was "normal", and used to also render filetree.nvim's cwd-mode badge.
--- That segment is a real module here (`ui.statusline.modules
--- .filetree_cwd_mode` still exists and works), but it assumes a specific
--- personal plugin most users of this repo will not have installed --
--- a preset shipped for anyone should not assume that. See
--- `docs/examples/personal-statusline-example.lua` for how to add it back
--- in a host's own config (the same mechanism that example demonstrates).

local lazy = require("lib.lua.lazy")
local render_module = lazy.require("ui.statusline.cursor_ctl.renderer")
local progr_calc_module = lazy.require("ui.statusline.cursor_ctl.progress_calculators")
local cursor_module = lazy.require("ui.statusline.cursor_ctl")

local M = {}

-- NvChad's own nvconfig.lua default for `ui.statusline.separator_style`,
-- which this variant never overrode -- now the explicit value instead of an
-- implicit fallback. See the roadmap, step 3.
local SEPARATOR_STYLE = "default"

-- Mirrors nvchad.stl.utils' `orders.default`, with one insertion. The `%=`
-- entries are the alignment breaks, so the list is really three groups:
-- left (up to the first `%=`), centre, right (after the second).
--
--   plugin_progress    right group, before "cwd" — transient status, same
--                      neighbourhood as the other transient indicators. Shows
--                      whichever plugin is currently running a long operation,
--                      not one specific plugin.
--
-- If NvChad ever changes its own default order, update this list to match
-- (see nvchad/stl/utils.lua).
local order = {
  "mode",
  "file",
  "git",
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
    separator_style = SEPARATOR_STYLE,
    modules = {
      -- Only "plugin_progress" is provided here; every other key in `order`
      -- above resolves to the built-in "default" theme module
      -- (mode/file/git/lsp_msg/diagnostics/lsp/cwd/cursor), which
      -- `generate()` merges this table into rather than replaces.
      plugin_progress = require("ui.statusline.modules.plugin_progress"),

      -- Overrides the built-in `cursor` (a fixed "%l/%v" string) with the
      -- cursor_ctl one, so the row/column progress indicator works in this
      -- preset too. Uses the default theme's own separator/highlight groups
      -- (St_pos_*), not a variant-local `get_separators()` call.
      cursor = function()
        local mode = cursor_module.get_mode()
        if mode == "off" then
          return ""
        end

        -- Same left separator the built-in default `cursor` uses, resolved
        -- the same way (nvchad/stl/default.lua lines 5-8), against this
        -- variant's own `SEPARATOR_STYLE` rather than a global config.
        local sep_icons = require("ui.statusline.utils.primitives").separators
        local separators = (type(SEPARATOR_STYLE) == "table" and SEPARATOR_STYLE)
          or sep_icons[SEPARATOR_STYLE]
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
