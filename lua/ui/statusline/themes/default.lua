---@module 'ui.statusline.themes.default'
--- The base module set `ui.statusline.render` falls back to for any `order`
--- key a statusline variant does not provide itself.
---
--- Ported from `nvchad/stl/default.lua`, which is what every variant that
--- does not name its own `theme` (`base`, `lspbased`, `custom_light`,
--- `normal`) resolved against before step 4 -- `custom` and `custom_minimal`
--- name a `theme` too, but cover every key in their own `order`, so that
--- value is never actually read. `minimal`/`vscode`/`vscode_colored` are not
--- ported for the same reason: nothing in this plugin's six shipped variants
--- falls through to them. `ui.statusline.render.generate()` warns once, by
--- key, if a future variant ever needs a fallback this module does not have
--- -- see that module's `resolve_theme`.
---
--- A factory, not a static table: nvchad's own `nvchad/stl/default.lua`
--- computed its separator glyphs once, from a single global `nvconfig`, at
--- require time. This plugin has no global to read -- each variant already
--- carries its own `separator_style` local (see e.g.
--- `ui.config.statusline.normal`) -- so `build()` takes that value and
--- closes the returned module table over it instead.

local primitives = require("ui.statusline.utils.primitives")

local M = {}

--- Build this theme's module table for one `separator_style`.
---@param separator_style string|{left: string, right: string}|nil
---@return table<string, fun(): string>
function M.build(separator_style)
  local sep_icons = primitives.separators
  local separators = (type(separator_style) == "table" and separator_style)
    or sep_icons[separator_style]
    or sep_icons.default
  local sep_l = separators.left
  local sep_r = separators.right

  local T = {}

  T.mode = function()
    if not primitives.is_activewin() then
      return ""
    end

    local modes = primitives.modes
    local m = vim.api.nvim_get_mode().mode
    local entry = modes[m] or { m, "Normal" }

    local current_mode = "%#St_" .. entry[2] .. "Mode#  " .. entry[1]
    local mode_sep1 = "%#St_" .. entry[2] .. "ModeSep#" .. sep_r
    return current_mode .. mode_sep1 .. "%#ST_EmptySpace#" .. sep_r
  end

  T.file = function()
    local icon, name = primitives.file()
    local label = " " .. name .. (separator_style == "default" and " " or "")
    return "%#St_file# " .. icon .. label .. "%#St_file_sep#" .. sep_r
  end

  T.git = function()
    return "%#St_gitIcons#" .. primitives.git()
  end

  T.lsp_msg = function()
    return "%#St_LspMsg#" .. primitives.lsp_msg()
  end

  T.diagnostics = primitives.diagnostics

  T.lsp = function()
    return "%#St_Lsp#" .. primitives.lsp()
  end

  T.cwd = function()
    local icon = "%#St_cwd_icon#" .. "󰉋 "
    local name = vim.uv.cwd()
    name = "%#St_cwd_text#" .. " " .. (name:match("([^/\\]+)[/\\]*$") or name) .. " "
    return (vim.o.columns > 85 and ("%#St_cwd_sep#" .. sep_l .. icon .. name)) or ""
  end

  T.cursor = "%#St_pos_sep#" .. sep_l .. "%#St_pos_icon# %#St_pos_text# %l/%v "

  return T
end

return M
