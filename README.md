> **Alpha.** All statusline, tabline and theme code stands on Neovim's own APIs —
> neither NvChad nor base46 are required any more, including by the reference host
> this plugin was extracted from. See [the migration record](docs/nvchad-migration.md)
> for how it got there, and pin a commit if you depend on it.

# ui.nvim

```
██╗   ██╗██╗
██║   ██║██║
██║   ██║██║
██║   ██║██║
╚██████╔╝██║
 ╚═════╝ ╚═╝
       .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-alpha-red)

The frame around the window: statusline, tabline, theme assembly — standing on
Neovim's own APIs rather than a distribution's. Started from roughly 4,500
lines of working statusline, tabline and theme code extracted out of a NvChad-based
config, and replaced the coupling to NvChad and base46 symbol by symbol from there.

---

## Around it

> **[casedesk.nvim](https://github.com/StefanBartl/casedesk.nvim)** and
> **[filetree.nvim](https://github.com/StefanBartl/filetree.nvim)** — each
> contributes one optional statusline segment (a case-info badge, a cwd-mode
> badge); neither is a dependency, and the segment is simply absent without
> them.
>
> **[my.nvim](https://github.com/StefanBartl/my.nvim)** — the winbar's actual content owner. `ui.winbar.set()` is the
> frame's scheduled, window-validity-checked write; my.nvim's breadcrumbs
> module keeps the debouncing, skip-rules and the string itself, and hands
> the result over.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](docs/requirements.md).

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where.

**The Basics**

- [Requirements](docs/requirements.md) — Neovim version, required plugins, and the optional soft integrations.
- [What it does and what not](docs/scope.md) — statusline, tabline, theme and winbar; what stays out on purpose.

**Configuration**

- [Configuration](docs/configuration.md) — both setup entry points and the four statusline presets.
- [Statusline modules](docs/modules.md) — every segment this plugin ships, one line each, with a copy-pasteable wiring snippet.
- [Bindings cheatsheet](docs/BINDINGS.md) — commands, keymaps and autocommands.

**The Rest**

- [Health check](docs/health.md) — what `:checkhealth ui` reports, line by line.
- [Credits & the NvChad migration record](docs/nvchad-migration.md) — where this started, and the step-by-step decision record of how the NvChad/base46 coupling was replaced.
- [Feedback](https://github.com/StefanBartl/ui.nvim/issues)

`:help ui` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

ui.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
