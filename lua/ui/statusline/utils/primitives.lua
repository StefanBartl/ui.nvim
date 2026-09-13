---@module 'ui.statusline.utils.primitives'
--- Statusline primitives this plugin used to reach into `nvchad.stl.utils`
--- for: which buffer the statusline is actually rendering for
--- (`vim.g.statusline_winid` is what keeps this right for floating previews
--- and inactive splits), whether this is the active window, the mode-name /
--- highlight-group table, separator glyph sets, the git/diagnostics/lsp/file
--- summary strings a few of the statusline variants render verbatim, and the
--- LSP-progress message `lsp_msg()` reads.
---
--- Ported, not wrapped -- none of this reads a NvChad symbol or a NvChad
--- highlight group by name that this plugin does not already assume; it only
--- used to be defined in a module NvChad happened to ship. `stbufnr` through
--- `separators` were ported at roadmap step 3; `file`, `state` and
--- `autocmds` at step 4, alongside the render entrypoint that is the first
--- thing to actually call them.

local M = {}

---@return integer
M.stbufnr = function()
  return vim.api.nvim_win_get_buf(vim.g.statusline_winid or 0)
end

---@return boolean
M.is_activewin = function()
  return vim.api.nvim_get_current_win() == vim.g.statusline_winid
end

--- Mode code -> { display name, highlight-group suffix }. The suffix feeds
--- `St_<suffix>Mode`, `St_<suffix>ModeSep`, `St_<suffix>ModeText` group names
--- at the call sites, so renaming a suffix here is not cosmetic.
---@type table<string, [string, string]>
M.modes = {
  ["n"] = { "NORMAL", "Normal" },
  ["no"] = { "NORMAL (no)", "Normal" },
  ["nov"] = { "NORMAL (nov)", "Normal" },
  ["noV"] = { "NORMAL (noV)", "Normal" },
  ["noCTRL-V"] = { "NORMAL", "Normal" },
  ["niI"] = { "NORMAL i", "Normal" },
  ["niR"] = { "NORMAL r", "Normal" },
  ["niV"] = { "NORMAL v", "Normal" },
  ["nt"] = { "NTERMINAL", "NTerminal" },
  ["ntT"] = { "NTERMINAL (ntT)", "NTerminal" },

  ["v"] = { "VISUAL", "Visual" },
  ["vs"] = { "V-CHAR (Ctrl O)", "Visual" },
  ["V"] = { "V-LINE", "Visual" },
  ["Vs"] = { "V-LINE", "Visual" },
  ["\22"] = { "V-BLOCK", "Visual" },

  ["i"] = { "INSERT", "Insert" },
  ["ic"] = { "INSERT", "Insert" },
  ["ix"] = { "INSERT", "Insert" },

  ["t"] = { "TERMINAL", "Terminal" },

  ["R"] = { "REPLACE", "Replace" },
  ["Rc"] = { "REPLACE (Rc)", "Replace" },
  ["Rx"] = { "REPLACEa (Rx)", "Replace" },
  ["Rv"] = { "V-REPLACE", "Replace" },
  ["Rvc"] = { "V-REPLACE (Rvc)", "Replace" },
  ["Rvx"] = { "V-REPLACE (Rvx)", "Replace" },

  ["s"] = { "SELECT", "Select" },
  ["S"] = { "S-LINE", "Select" },
  ["\19"] = { "S-BLOCK", "Select" },
  ["c"] = { "COMMAND", "Command" },
  ["cv"] = { "COMMAND", "Command" },
  ["ce"] = { "COMMAND", "Command" },
  ["cr"] = { "COMMAND", "Command" },
  ["r"] = { "PROMPT", "Confirm" },
  ["rm"] = { "MORE", "Confirm" },
  ["r?"] = { "CONFIRM", "Confirm" },
  ["x"] = { "CONFIRM", "Confirm" },
  ["!"] = { "SHELL", "Terminal" },
}

-- Icon glyphs `M.git`/`M.lsp`/`M.diagnostics` need, as explicit `\xEE`/`\xEF`
-- UTF-8 byte escapes rather than literal glyphs -- same reason, and the same
-- fix, as `M.separators` below already documents for itself: these were
-- bare ASCII spaces here (no glyph at all, not even a corrupted one) while
-- `nvchad/stl/utils.lua` -- the file this module was ported from -- still
-- has every one of them intact, byte for byte. That silent loss is what
-- produced the reported "counter with no icon" (a git-changed count showing
-- as a bare "1"): not a bug in the highlight-group fix that shipped
-- alongside the double-separator fix, just never independently verified
-- against a diff of the original file until now.
local ICON_GIT_ADDED = "\xEF\x81\x95"
local ICON_GIT_CHANGED = "\xEF\x91\x99"
local ICON_GIT_REMOVED = "\xEF\x85\x86"
local ICON_GIT_BRANCH = "\xEE\xA9\xA8"
local ICON_LSP_CLIENT = "\xEF\x82\x85"
local ICON_LSP_ERROR = "\xEF\x81\x97"
local ICON_LSP_WARN = "\xEF\x81\xB1"

--- Escape a literal `%` so embedding a value into `'statusline'` cannot be
--- misread as one of its own `%`-directives (`%#Group#`, `%=`, `%N@Func@`,
--- ...). Same fix, same reasoning, as `ui.tabline.utils`' own `stl_escape`
--- (filesystem-controlled buffer names) and `ui.statusline.modules
--- .formatters.stl_escape` (LSP/Treesitter symbol text) -- a small local copy
--- rather than requiring either of those higher-level modules from this one,
--- which is meant to stay a dependency-free base layer.
---@param s string
---@return string
local function stl_escape(s)
  return (s:gsub("%%", "%%%%"))
end

--- Branch name plus added/changed/removed counts from gitsigns' buffer-local
--- state. Empty when gitsigns has not attached (no head) or has not produced
--- a status dict yet. The branch name is git-controlled, not this plugin's --
--- `%` is a valid git ref character, so it needs the same escape as any other
--- externally-sourced text this plugin renders into the statusline.
---@return string
M.git = function()
  local buf = M.stbufnr()
  local git_status = vim.b[buf].gitsigns_status_dict
  if not vim.b[buf].gitsigns_head or not git_status then
    return ""
  end

  local added = (git_status.added and git_status.added ~= 0)
      and (" " .. ICON_GIT_ADDED .. " " .. git_status.added)
    or ""
  local changed = (git_status.changed and git_status.changed ~= 0)
      and (" " .. ICON_GIT_CHANGED .. " " .. git_status.changed)
    or ""
  local removed = (git_status.removed and git_status.removed ~= 0)
      and (" " .. ICON_GIT_REMOVED .. " " .. git_status.removed)
    or ""
  local branch_name = ICON_GIT_BRANCH .. " " .. stl_escape(git_status.head)

  return " " .. branch_name .. added .. changed .. removed
end

--- Whether any LSP client is attached to the statusline's buffer, as a
--- ready-to-concatenate label.
---@return string
M.lsp = function()
  if rawget(vim, "lsp") then
    for _, client in ipairs(vim.lsp.get_clients()) do
      if client.attached_buffers[M.stbufnr()] then
        local label = " " .. ICON_LSP_CLIENT .. "  LSP "
        return (vim.o.columns > 100 and (label .. "~ " .. client.name .. " ")) or label
      end
    end
  end

  return ""
end

--- Error/warn/hint/info diagnostic counts for the statusline's buffer,
--- pre-wrapped in their `St_lsp*` highlight groups.
---@return string
M.diagnostics = function()
  if not rawget(vim, "lsp") then
    return ""
  end

  local buf = M.stbufnr()
  local err_n = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR })
  local warn_n = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.WARN })
  local hints_n = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.HINT })
  local info_n = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.INFO })

  local err = (err_n > 0) and ("%#St_lspError#" .. ICON_LSP_ERROR .. " " .. err_n .. " ") or ""
  local warn = (warn_n > 0) and ("%#St_lspWarning#" .. ICON_LSP_WARN .. " " .. warn_n .. " ") or ""
  local hints = (hints_n > 0) and ("%#St_lspHints#" .. "󰛩 " .. hints_n .. " ") or ""
  local info = (info_n > 0) and ("%#St_lspInfo#" .. "󰋼 " .. info_n .. " ") or ""

  return " " .. err .. warn .. hints .. info
end

--- Named separator glyph pairs, keyed the same way `separator_style` values
--- already are across the statusline variants.
---
--- `default` and `round` were empty strings from this table's very first
--- commit in this repo (2026-09-08, the wkdnvchad extraction itself) --
--- confirmed via `git log -p`, so the loss predates every change made here
--- since. Written as explicit `\xEE\x82\xBx` UTF-8 byte escapes rather than
--- literal glyphs, specifically so an editor/clipboard/encoding pass can't
--- silently drop them the same way again -- these are the standard
--- Powerline private-use-area codepoints (U+E0B0/B2/B4/B6), the same ones
--- lualine/vim-airline ship for these exact style names.
--- `default` mirrors `round` -- NvChad's own shipped default statusline is
--- the rounded-pill look, not the hard-angled one.
---@type table<string, {left: string, right: string}>
M.separators = {
  default = { left = "\xEE\x82\xB6", right = "\xEE\x82\xB4" }, --  /
  round = { left = "\xEE\x82\xB6", right = "\xEE\x82\xB4" }, --  /
  block = { left = "█", right = "█" },
  arrow = { left = "\xEE\x82\xB2", right = "\xEE\x82\xB0" }, --  /
}

--- File icon and display name for the statusline's buffer. `nvim-web-devicons`
--- is soft: without it every file renders with the same fallback icon rather
--- than losing the segment.
---@return string icon
---@return string name
M.file = function()
  local icon = "󰈚"
  local path = vim.api.nvim_buf_get_name(M.stbufnr())
  local name = (path == "" and "Empty") or path:match("([^/\\]+)[/\\]*$")

  if name ~= "Empty" then
    local ok, devicons = pcall(require, "nvim-web-devicons")
    if ok then
      local ft_icon = devicons.get_icon(name)
      icon = (ft_icon ~= nil and ft_icon) or icon
    end
  end

  return icon, name
end

--- LSP-progress state `autocmds()` keeps current, and `lsp_msg()` reads.
--- A plain module field, not a closure return, so a variant's own module
--- function can read `M.state.lsp_msg` directly if `lsp_msg()`'s
--- column-width gate does not fit what it wants to render.
---@type { lsp_msg: string }
M.state = { lsp_msg = "" }

--- The current LSP-progress message, blanked below 120 columns -- there is
--- no room to show it, and a truncated progress line reads worse than none.
---@return string
M.lsp_msg = function()
  return vim.o.columns < 120 and "" or M.state.lsp_msg
end

--- One spinner frame per ~10% of a reported progress percentage.
---@type string[]
local SPINNERS = { "", "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥", "" }

-- Guards against a second `autocmds()` call registering a duplicate
-- `LspProgress` handler -- the render entrypoint calls this from `enable()`,
-- and `enable()` is safe to call more than once (a variant switch, a test
-- re-running setup).
local autocmds_registered = false

--- Register the `LspProgress` autocmd that keeps `M.state.lsp_msg` current
--- and redraws the statusline as progress comes in. Idempotent -- a second
--- call is a no-op rather than a second handler.
---@return nil
M.autocmds = function()
  if autocmds_registered then
    return
  end
  autocmds_registered = true

  local autocmd = require("lib.nvim.bindings.autocmd")
  local group = autocmd.group("ui_statusline_lsp_progress", true)

  autocmd.create("LspProgress", function(args)
    if not args.data or not args.data.params then
      return
    end

    local data = args.data.params.value
    local progress = ""

    if data.percentage then
      local idx = math.max(1, math.floor(data.percentage / 10))
      progress = SPINNERS[idx] .. " " .. data.percentage .. "%% "
    end

    local loaded_count = data.message and data.message:match("^(%d+/%d+)") or ""
    local str = progress .. (data.title or "") .. " " .. (loaded_count or "")
    M.state.lsp_msg = data.kind == "end" and "" or str
    vim.cmd.redrawstatus()
  end, {
    group = group,
    pattern = { "begin", "report", "end" },
    desc = "ui.statusline: track LSP progress into the statusline",
  })
end

return M
