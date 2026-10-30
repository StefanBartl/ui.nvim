# ui.vim_ui

`vim.ui.select` and `vim.ui.input` through the kit. About a hundred calls in the plugins go through these two
functions; with this switched on they look like every other dialog of the kit, and none of those plugins is
changed.

Off until asked for:

```lua
require("ui").setup({ vim_ui = true })
-- or with options, and without ui.setup:
require("ui.vim_ui").enable({
  buttons_max = 4,        -- up to this many entries (and only if the buttons fit the screen): button dialog
  chooser_max = 12,       -- up to this many: the kit's chooser; more go to the fallback
  fallback_select = nil,  -- function(items, opts, on_choice) for the long lists, see below
  passthrough_kinds = {}, -- `opts.kind` values that always go to the fallback, e.g. { "codeaction" }
  select = true,          -- false: leave vim.ui.select alone
  input = true,           -- false: leave vim.ui.input alone
})
```

`require("ui.vim_ui").disable()` (or `ui.setup({ vim_ui = false })`) puts the previous functions back. A function
somebody wrapped on top of ours stays where it is.

Every `enable(opts)` starts from these defaults (options of an earlier call do not stay). An unknown key (with a
did-you-mean hint) or a value of the wrong type or out of range (`buttons_max`/`chooser_max` are whole numbers
`>= 0`) is warned about once and ignored, so its default applies; `require("ui.vim_ui").issues()` and
`:checkhealth ui` ("Module options") list what the last call ignored.

## What it does

- **`vim.ui.select`**
  - A short list is one row of buttons (`kit.confirm`), the first one focused. A medium one is the kit's chooser
    (`kit.select`). A longer one, an empty one, and a call whose `opts.kind` is in `passthrough_kinds` go to the
    fallback unchanged.
  - The contract is kept: `on_choice(item, idx)` gets the original entry (`format_item` only decides what is shown),
    `on_choice(nil, nil)` when dismissed, each called once.
- **`vim.ui.input`**
  - `kit.input` with `prompt` (a trailing colon is dropped), `default` and `completion`; `on_confirm(nil)` when
    cancelled.
- **A float that cannot open** hands the call to the fallback (the previous function) instead of answering "cancelled".

The fallback is `fallback_select`, else the `vim.ui.select` that was there when this was switched on, else the
runtime's own.

## With snacks as the picker for long lists

snacks.nvim replaces `vim.ui.select` itself (`picker.ui_select`, on by default when the picker is enabled), so whichever
`setup()` runs last wins. Switch that off and name snacks as the fallback:

```lua
-- snacks.nvim
opts = { picker = { enabled = true, ui_select = false } }

-- ui.nvim
require("ui").setup({
  vim_ui = {
    fallback_select = function(items, opts, on_choice)
      Snacks.picker.select(items, opts, on_choice)
    end,
  },
})
```

## Notes

- It talks to the kit directly and not to `lib.nvim.ui.dialog`: the dialog's own fallback asks through
  `vim.ui.select`, which would be this provider again.
- `kit.select({ respect_override = true })` hands its call to `vim.ui.select` when something else owns it; with this
  provider on, that reaches the provider once, which opens the chooser itself (no loop).
- Tests can answer the dialogs it opens with `kit.set_dialog_hook` (see the kit README).
