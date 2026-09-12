# Documentation — ui.nvim

What is where, and which question each page answers.

| Page | Answers |
| --- | --- |
| [configuration.md](configuration.md) | Both setup entry points, the six statusline variants, what is not configurable |
| [BINDINGS.md](BINDINGS.md) | Every command, keymap and autocommand — including the ones that deliberately do not exist |
| [health.md](health.md) | Every line `:checkhealth ui` can print, and what to do about it |

`:help ui` is the same reference inside the editor.

---

## The legacy page

`README-legacy-wkdnvchad.md` is the original module README from before the
extraction. It is long, and parts of it describe internals that have since
moved — `vim.g.ui_profile` and `vim.g.ui_debug`, for instance, are documented
there and exist nowhere in the code.

It is kept rather than rewritten because it records reasoning the new pages
only summarize. Read it for the *why* of a statusline module, not for the
current API.

The per-module `README.md` files under `lua/ui/**` are in the same position:
accurate about intent, occasionally stale about names. `docs/map/` (generated
by `scripts/gen_map.lua`, not committed) is the current structure.
