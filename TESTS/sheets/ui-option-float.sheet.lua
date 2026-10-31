-- Live check: the :UI option float (task ui.nvim/try-the-ui-option-float-in-a-real-session).
-- Automated: :UI opens the float, its rows match the reviewed snapshot, q closes it with no float
-- left. Left for a person: whether the rows read well, and the cheatsheet key of the real config.
return {
  id = "ui.option-float",
  title = ":UI option float",
  task = "ui.nvim/try-the-ui-option-float-in-a-real-session",
  engine = "rpc",
  steps = {
    { lua = 'require("ui").setup({ usrcmds = true })', note = "the plugin with its :UI command" },
    { keys = ":UI<CR>", note = "open the option float" },
    { wait = "vim.api.nvim_win_get_config(0).relative ~= ''", note = "a float has the focus" },
    { settle = 3000 },
    { screen = "float" },
    { keys = "q", note = "close it" },
    {
      wait = "#vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= '' end, vim.api.nvim_list_wins()) == 0",
      note = "no float is left",
    },
  },
  judge = {
    "The rows and texts of the float read well (alignment, wrapping, icons, colours)",
  },
  manual = {
    "In the real config the cheatsheet key <M-h> opens the same float",
    ":UI sticky <Tab> offers the sticky words",
  },
}
