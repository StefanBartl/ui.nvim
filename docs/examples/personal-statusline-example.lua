---@module 'examples.personal-statusline-example'
--- Example of a fully custom statusline built on this plugin's own segment
--- modules -- not a shipped preset. Was shipped as the "custom" preset until
--- the 2026-09-12 preset consolidation; moved here because it fails the
--- test a shipped preset has to pass: it assumes two specific personal
--- plugins (`casedesk.nvim`, `filetree.nvim`) that most users of this
--- public repo will not have installed. A preset is generic by definition;
--- a config built around plugins only its own author uses is not a preset,
--- it is a config -- this file is that config, kept as the template for
--- "how do I wire my own segments" rather than pretending to be one of the
--- four generic choices in `lua/ui/config/statusline/`.
---
--- To use this (or a copy of it, adjusted to your own segments): copy this
--- file into your OWN Neovim config, then either
---
---   1. hand it to `ui.config.setup()` directly, anonymously:
---
---        require("ui.config").setup({
---          variant = require("your_config.statusline"), -- this file, in your own config
---        })
---
---   2. or register it under a name first, so it shows up in `:UI variant`
---      and its completion next to the four shipped presets:
---
---        require("ui.config.variants").register("personal", require("your_config.statusline"))
---        require("ui.config").setup({ variant = "personal" })
---
--- See docs/configuration.md, "ui.config.variants".
---
--- No breadcrumbs module (removed 2026-09-13): a host that also uses
--- `ui.winbar.set()` to draw breadcrumbs into the winbar (`vim.wo.winbar`,
--- directly below the tabline -- a separate Neovim surface from both the
--- statusline and the tabline, see `ui.winbar`'s own doc comment) already
--- has path/symbol context there. This statusline's own former
--- "breadcrumbs" module (`ui.statusline.modules.lsp.
--- render_breadcrumbs_inherit_lspfirst`) rendered the same kind of content a
--- second time, independently, in the middle of the statusline -- not one
--- feeding the other, just two separate implementations of the same idea.
--- Add it back under a different key if your winbar draws something else.

local lazy = require("lib.lua.lazy")
local render_module = lazy.require("ui.statusline.cursor_ctl.renderer")
local progr_calc_module = lazy.require("ui.statusline.cursor_ctl.progress_calculators")
local cursor_module = lazy.require("ui.statusline.cursor_ctl")
local get_separators = lazy.require("ui.statusline.utils.get_separators")
local plugin_progress = lazy.require("ui.statusline.modules.plugin_progress")
local plugin_summary = lazy.require("ui.statusline.modules.plugin_summary")
local filetree_cwd_mode = lazy.require("ui.statusline.modules.filetree_cwd_mode")
local casedesk = lazy.require("ui.statusline.modules.casedesk")

-- ============================================================================
-- Modules
-- ============================================================================

-- The single source for this variant's separator style: the config table
-- below and the module closures that call `get_separators` both read this,
-- rather than a global config that separator style used to be read back from.
local SEPARATOR_STYLE = "round" -- "arrow", "round", "block", "default"

return {
  ui = {
    statusline = {
      theme = "minimal", -- or "vscode_colored"
      separator_style = SEPARATOR_STYLE,

      order = {
        "mode",
        "git",
        "%=",
        "diagnostics",
        "lsp",
        "plugin_progress",
        "plugin_summary",
        "casedesk",
        "filetree_cwd_mode",
        "cursor",
      },

      modules = {
        plugin_progress = function()
          return plugin_progress()
        end,

        plugin_summary = function()
          return plugin_summary()
        end,

        -- Case short-info (number · company · N replies), empty outside a
        -- case folder — see lua/bindings/usrcmds/case/, ROADMAP.md v7.
        casedesk = function()
          return casedesk()
        end,

        -- The label itself (PROJECT/PKG/LOCK/… vs P/N/L/… vs 1/2/3/… vs a
        -- Nerd Font glyph) is filetree's own `features.cwd_mode.indicator.
        -- style` (see lua/plugins/personal/init.lua) — this only controls
        -- how THIS statusline renders whatever text that produces.
        filetree_cwd_mode = function()
          return filetree_cwd_mode({
            badge_style = true, -- bg-filled capsule + fading separator, like `mode`. false = plain colored text.
            -- colors = { lock = "orange" },  -- override the accent per cwd mode; see the module's DEFAULT_COLOR_BY_MODE.
            separator_style = SEPARATOR_STYLE, -- match this variant's own separator style, not the module's default
          })
        end,

        --- Mode (overrides the built-in default, adds separators)
        --- @return string
        mode = function()
          local utils = require("ui.statusline.utils.primitives")
          if not utils.is_activewin() then
            return ""
          end

          local modes = utils.modes
          local m = vim.api.nvim_get_mode().mode
          local mode_name = modes[m][1]
          local mode_type = modes[m][2]

          local sep = get_separators(SEPARATOR_STYLE)

          local current_mode = "%#St_" .. mode_type .. "Mode#  " .. mode_name
          local mode_sep1 = "%#St_" .. mode_type .. "ModeSep#" .. sep.right

          return current_mode .. mode_sep1 .. "%#ST_EmptySpace#" .. sep.right
        end,

        --- @return string
        git = function()
          local utils = require("ui.statusline.utils.primitives")
          local git_status = utils.git()
          if not git_status or git_status == "" then
            return ""
          end

          return " %#St_gitIcons#" .. git_status .. "%#St_gitIcons# " .. " "
        end,

        --- @return string
        diagnostics = function()
          local utils = require("ui.statusline.utils.primitives")
          local diag = utils.diagnostics()
          if not diag or diag == "" then
            return ""
          end

          return diag
        end,

        --- @return string
        lsp = function()
          local utils = require("ui.statusline.utils.primitives")
          local lsp_status = utils.lsp()
          if not lsp_status or lsp_status == "" then
            return ""
          end

          return "%#St_Lsp#" .. lsp_status .. " "
        end,

        --- @return string
        cursor = function()
          local mode = cursor_module.get_mode()

          if mode == "off" then
            return ""
          end

          local pieces = { render_module.cursor_classic() }

          if mode == "row_progress" then
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
          elseif mode == "col_progress" then
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
          elseif mode == "rows_cols_progress" then
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_row_pct(), "R")
            pieces[#pieces + 1] = render_module.pct_token(progr_calc_module.compute_col_pct(), "C")
          end

          local content = table.concat(pieces, "")
          local sep = get_separators(SEPARATOR_STYLE)

          -- Cursor as in the default theme: left + right separator
          return "%#St_pos_sep#" .. sep.left .. "%#St_pos_icon# %#St_pos_text# " .. content .. " "
        end,
      },
    },
  },
}
