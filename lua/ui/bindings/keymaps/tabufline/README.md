# ui.bindings.keymaps.tabufline

Custom buffer navigation without automatic centering.

Until roadmap step 5, this was built on the external `nvchad.tabufline`
module. It no longer is: `state.lua` in this directory owns the `vim.t.bufs`
bookkeeping (`BufAdd`/`BufEnter`/`tabnew`/`BufDelete` autocmds) and the
`close_buffer()`/`move_buf()` this module used to reach into NvChad for. See
that file's own doc comment for why the bookkeeping mattered more than the
two functions — the same shape of gap the statusline render entrypoint
(step 4) found: not a symbol this repo's own code required, but setup that
used to run from NvChad's own `init.lua`.
