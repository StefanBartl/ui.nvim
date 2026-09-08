# Health check — ui.nvim

```vim
:checkhealth ui
```

Five sections. As of roadmap step 5, only one thing in the first is fatal:
`lib.nvim` missing. NvChad's presence is information now, not a dependency
check — steps 3-5 replaced everything this plugin's own code used to read
out of it, one gap at a time.

---

## Dependencies

| Line | Means |
| --- | --- |
| ✅ `lib.nvim is available` | The root module resolves |
| ✅ `all 10 required lib.nvim modules resolve` | Every module this plugin requires by name was found |
| ❌ `lib.nvim is not on the runtimepath` | Fatal — install `StefanBartl/lib.nvim`. Only failure that stops the report |
| ℹ️ `NvChad is present` / `NvChad is not present` | Neither is an error. The host this plugin was extracted from still wires `chadrc.lua` to NvChad's own renderer (step 7, not done) — this line just says whether that path exists on this machine, not whether this plugin's own code needs it (it doesn't) |
| ✅ `base46` / `base46.themes` missing → ⚠️ | The one genuine soft dependency left: theme loading and the transparency toggle (step 6, undecided). Guarded at every call site — degrades, does not throw |

`nvconfig`, `nvchad.stl.utils` and `nvchad.tabufline` are gone from this
section entirely — not reclassified as soft, removed, because this plugin's
own code no longer reads any of them under any name (steps 3-5).

---

## Configuration

| Line | Means |
| --- | --- |
| ✅ `theme "x", transparency false, toggle pair a / b` | The shipped theme block |
| ℹ️ `statusline variant: x` | Which of the six layouts is assembled |
| ✅ `variant module ui.config.statusline.x resolves` | The variant name is a module path at heart; a typo in it degrades to `normal` with a notification nobody sees twice |
| ❌ `variant "x" does not resolve` | It will silently fall back to `normal`. This line is why the check exists |
| ✅ `ui.config.setup() assembles` | The table this plugin's own `ui.statusline.render` (or, until step 7, NvChad through `chadrc`) reads was produced, without touching a NvChad symbol |

---

## Statusline render entrypoint

New at step 4. Checks the module that replaced `nvchad.init` +
`nvchad.stl.utils.generate()`.

| Line | Means |
| --- | --- |
| ✅ `ui.statusline.render resolves` | `generate`/`enable`/`render`/`disable` are all present |
| ✅ `generate() renders the 'default' theme's fallback modules without NvChad` | A synthetic config ran through `generate()` and produced a string, standalone |
| ℹ️ `a config is currently enable()d` | Something called `ui.statusline.render.enable()` — `vim.o.statusline` is this plugin's, not the host's |
| ℹ️ `enable() has not been called` | The common case today: `vim.o.statusline` is whatever the host last set (NvChad, through `chadrc.lua`, until step 7) |

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

`keymaps` also covers buffer/tab navigation as of step 5 — `<Tab>`/`<S-Tab>`/
`<leader>bc`/`<leader>tr`/`<leader>tl` all run on
`ui.bindings.keymaps.tabufline.state`'s own `vim.t.bufs` bookkeeping, not
`nvchad.tabufline`. Nothing in this section reports that separately; if
`keymaps` is on, so is buffer/tab navigation.

---

## Statusline segments

Three soft dependencies, each blanking only its own segment when absent:
`nvim-web-devicons` (file icons), `neotest` (the test-runner segment) and
`casedesk.meta` (the working-directory badge).

An `ℹ️ not installed` line here is never a problem — it is the report saying
which part of the statusline will be empty and why.
