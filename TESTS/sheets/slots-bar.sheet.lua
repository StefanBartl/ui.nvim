-- Live check: the ui.slots bar (task ui.nvim/slots-live-check, point 1 of the "Sichtpruefung ui.slots").
-- Automated: the bar opens with four fixed slots in the rounded style and matches the reviewed
-- snapshot. Left for a person: the other presets, light and dark themes, daily use.
return {
  id = "slots.bar-rounded",
  title = "ui.slots: bar with chips (rounded)",
  task = "ui.nvim/slots-live-check",
  engine = "rpc",
  steps = {
    -- no intro screen: it names the Neovim version, which would tie the snapshot to one release
    { lua = 'vim.opt.shortmess:append("I")' },
    {
      lua = [[require("ui").setup({ usrcmds = true, slots = { enabled = true, show = true, style = "rounded", slots = {
        [1] = { kind = "file", path = "README.md", label = "readme" },
        [2] = { kind = "url", url = "https://example.org", label = "site" },
        [3] = { kind = "cmd", cmd = "echo", args = "hi", label = "hello" },
        [4] = { kind = "lua", fn = function() end, label = "one" },
      } } })]],
      note = "four fixed slots, bar shown",
    },
    { keys = ":UI slots open<CR>", note = "open the bar" },
    { settle = 3000 },
    { screen = "bar" },
  },
  judge = {
    "The chips look right in the own colour scheme",
  },
  manual = {
    "Chips in a second preset (double, ascii, solid or minimal), light and dark theme",
    "Use a file, URL, yank, cmd and lua slot once each in daily work",
    "Preview (K in the panel) for a file and a URL",
    "Next to filetree, zen, several windows and a project switch: nothing overlaps or jumps",
  },
}
