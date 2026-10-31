-- Live check: hotkey marking of kit.confirm buttons (task ui.nvim/sichtpruefung-hotkey-markierung-der-dialog-buttons-im-echten).
-- Automated: the dialogs open, the marked letters and digits carry an attribute of their own, the
-- screen matches the reviewed snapshot. Left for a person: whether a real terminal draws it well.
return {
  id = "kit.confirm-hotkeys",
  title = "kit.confirm: hotkey marking of the buttons",
  task = "ui.nvim/sichtpruefung-hotkey-markierung-der-dialog-buttons-im-echten",
  engine = "rpc",
  steps = {
    {
      lua = [[require("ui.kit").confirm({ question = "The file exists. Overwrite it?",
        choices = { "Yes", "No", "Cancel", "Overwrite" }, default = 2, on_answer = function() end })]],
      note = "four buttons, focus on No",
    },
    { settle = 3000 },
    { screen = "letters" },
    { keys = "<Esc>", note = "close it" },
    { wait = "vim.api.nvim_win_get_config(0).relative == ''", note = "the dialog is gone" },
    {
      lua = [[require("ui.kit").confirm({ question = "Pick one",
        choices = { "+", "-", "*", "/", "=", "<", ">", "?", "!" }, on_answer = function() end })]],
      note = "nine buttons without letters: digits 1-9",
    },
    { settle = 3000 },
    { screen = "digits" },
  },
  judge = {
    "In WezTerm (and tmux) the KitHotkey underline is visible on Y, N, C, O, also on the focused button",
    "The superscript digits (also 4 to 9 with the own font) are readable and sit on the button",
  },
}
