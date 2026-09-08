# Health check — ui.nvim

```vim
:checkhealth ui
```

Four sections. The first is the one that matters, and it is why this file is
short: **NvChad is a hard dependency of this plugin today.** Everything else
the report says is downstream of that.

---

## Dependencies

| Line | Means |
| --- | --- |
| ✅ `lib.nvim is available` | The root module resolves |
| ✅ `all 10 required lib.nvim modules resolve` | Every module this plugin requires by name was found |
| ✅ `nvconfig` / `nvchad.stl.utils` | Present. Neither is read by this plugin's own code any more (step 3), but nothing here sets `vim.o.statusline` either — NvChad's `nvchad.init` + `nvchad.stl.utils.generate()` is what renders the config `ui.config.setup()` assembles |
| ❌ `nvconfig is missing` / `nvchad.stl.utils is missing` | Fatal. This plugin has no render entrypoint of its own, so without NvChad's the statusline never renders at all. Install NvChad (v2.5), or do not install this plugin |
| ⚠️ `nvchad.tabufline` / `base46` / `base46.themes` missing | Guarded at every call site: the tabline keymaps and theme switching stop working, nothing throws |
| ❌ `lib.nvim is not on the runtimepath` | Install `StefanBartl/lib.nvim` |

The section **returns early** when a fatal symbol is missing. Everything below
it assembles a configuration out of exactly those symbols, so continuing would
print a wall of secondary failures that says nothing the first one did not.

The error/warning split is the useful part: it separates "this will not run"
from "this feature is off". The measured coupling and the render-entrypoint
gap step 3 surfaced are in [ROADMAP.md](ROADMAP.md), and removing both is the
plugin's entire roadmap.

---

## Configuration

| Line | Means |
| --- | --- |
| ✅ `theme "x", transparency false, toggle pair a / b` | The shipped theme block |
| ℹ️ `statusline variant: x` | Which of the six layouts is assembled |
| ✅ `variant module ui.config.statusline.x resolves` | The variant name is a module path at heart; a typo in it degrades to `normal` with a notification nobody sees twice |
| ❌ `variant "x" does not resolve` | It will silently fall back to `normal`. This line is why the check exists |
| ✅ `ui.config.setup() assembles` | The table NvChad reads through `chadrc` was produced |

---

## Modules

One line per submodule, from `package.loaded` rather than a `require` — a
module left out of `setup()` should report as off, and requiring it here would
load it and make the report a lie.

| Line | Means |
| --- | --- |
| ✅ `keymaps` / `usrcmds` | `setup()` turned it on |
| ℹ️ `… is off` | You did not ask for it. Informational, not a warning |
| ⚠️ `:UI is not registered` | `usrcmds` never ran — `require("ui").setup({ all = true })` |

---

## Statusline segments

Three soft dependencies, each blanking only its own segment when absent:
`nvim-web-devicons` (file icons), `neotest` (the test-runner segment) and
`casedesk.meta` (the working-directory badge).

An `ℹ️ not installed` line here is never a problem — it is the report saying
which part of the statusline will be empty and why.
