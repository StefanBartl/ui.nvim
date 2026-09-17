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

## Contents

- [Around it](#around-it)
- [Installation](#installation)
- [Documentation](#documentation)
- [License](#license)

---

## Around it

> **[casedesk.nvim](https://github.com/StefanBartl/casedesk.nvim)**,
> **[filetree.nvim](https://github.com/StefanBartl/filetree.nvim)**,
> **[github_stats.nvim](https://github.com/StefanBartl/github_stats.nvim)**,
> **[runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim)**,
> **[recommender.nvim](https://github.com/StefanBartl/recommender.nvim)**,
> **[sessions.nvim](https://github.com/StefanBartl/sessions.nvim)** and
> **[sandbox.nvim](https://github.com/StefanBartl/sandbox.nvim)** — each
> contributes one optional statusline segment (a case-info badge, a cwd-mode
> badge, a weekly-views badge, a health ampel, an alias-suggestion count, the
> active session name, an ambient container summary); none is a dependency,
> and the segment is simply absent without it. The full list, with the exact
> wiring snippet for each, is [docs/modules.md](docs/modules.md).
>
> **[my.nvim](https://github.com/StefanBartl/my.nvim)** — the winbar's actual content owner. `ui.winbar.set()` is the
> frame's scheduled, window-validity-checked write; my.nvim's breadcrumbs
> module keeps the debouncing, skip-rules and the string itself, and hands
> the result over.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](docs/requirements.md).
>
> The traffic also runs the other way, at far greater scale: `ui.kit` (float
> pickers, input, confirm, menu, toast, viewer, ...) and `ui.contextmenu` are
> the shared UI toolkit roughly twenty sibling plugins build their prompts,
> confirmations and right-click menus on top of — every one of them through a
> `pcall`, so ui.nvim stays a soft dependency on their side too. `ui.kit` and
> `ui.contextmenu` are documented in [modules.md](docs/modules.md)'s
> "Building your own module" pointers and in their own module headers under
> [`lua/ui/kit/`](lua/ui/kit/) and
> [`lua/ui/contextmenu/`](lua/ui/contextmenu/).

---

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "StefanBartl/ui.nvim",
  lazy = false,
  dependencies = { "StefanBartl/lib.nvim" },
  config = function()
    require("ui").setup({ all = true })
  end,
},
```

`lazy = false` rather than an event: this plugin owns `vim.o.statusline` and
`vim.o.tabline`, so deferring it leaves the previous owner's frame on screen
until the trigger fires.

`setup()` takes no required options — `{ all = true }` turns on the keymaps
and the `:UI` command, `setup()` with no argument leaves both off and enables
nothing but the context menu. See
[Configuration](docs/configuration.md) for the rest, and
[Requirements](docs/requirements.md) for the one dependency and the optional
integrations.

With [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({
  "StefanBartl/ui.nvim",
  requires = { "StefanBartl/lib.nvim" },
  config = function()
    require("ui").setup({ all = true })
  end,
})
```

Or with Neovim 0.12's built-in `vim.pack`:

```lua
vim.pack.add({
  { src = "https://github.com/StefanBartl/lib.nvim" },
  { src = "https://github.com/StefanBartl/ui.nvim" },
})
require("ui").setup({ all = true })
```

Then run `:checkhealth ui`.

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
