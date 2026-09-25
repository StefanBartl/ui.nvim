---@module 'ui.menu.icons'
--- The glyphs of the menu's icon column. Every one goes through
--- `lib.nvim.ui.nerd_font.glyph(hex, fallback)`: a Nerd Font glyph when
--- `vim.g.have_nerd_font` says so, else a one-cell ASCII stand-in, so the
--- column stays aligned either way. Resolved on access, not at load, so a
--- host that sets `vim.g.have_nerd_font` after requiring this still gets them.

local RAW = {
  format = { "F0AD", "~" },
  code_action = { "F0EB", "*" },
  inspect = { "F0349", "?" },
  copy_all = { "F0C5", "c" },
  copy_marked = { "F018F", "c" },
  paste = { "F0192", "v" },
  save = { "F0C7", "s" },
  save_all = { "F0193", "S" },
  delete_marked = { "F0190", "x" },
  delete_all = { "F12D", "x" },
  delete_file = { "F1F8", "x" },
  terminal = { "F120", ">" },
  color_picker = { "F03D8", "#" },
  unicode_table = { "F031", "U" },
  git = { "F02A2", "G" },
  -- Fallbacks for a contributor that names no icon of its own.
  plugin = { "F1B2", "p" },
  markdown = { "F02D", "M" },
  open = { "F0C1", "L" },
  dap = { "F188", "D" },
  cascade = { "F0E8", "C" },
  fileops = { "F15B", "F" },
  images = { "F03E", "I" },
  spotlight = { "F002", "S" },
  color_my_ascii = { "F1FC", "A" },
  lsp = { "F0E7", "L" },
  gopath = { "F14E", "g" },
}

return setmetatable({}, {
  __index = function(_, key)
    local raw = RAW[key]
    if not raw then
      return nil
    end
    return require("lib.nvim.ui.nerd_font").glyph(raw[1], raw[2])
  end,
})
