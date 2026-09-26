# `ui.kit`

> Ported from `lib.nvim.ui.kit` (PLAN-ui-kit-migration.md step 3: mechanical
> prefix rename, source and tests, into this plugin). The extended user guide
> and the per-component `docs/EXAMPLES/kit-*.lua` files that used to sit
> alongside this in `lib.nvim` were not ported yet — for now, `:KitPreview`
> (a live theme playground) and this README are what ships here.

A themed, composable UI toolkit. Pick a preset once and every popup is visually
coordinated, or override colors/borders per call. Built in layers on top of
`lib.nvim.window` (`make_scratch`, `nice_quit`) and `lib.nvim.ui.hl` —
nothing shells out, so it is cross-platform.

> **Phases 1–2** (this release): theme/preset engine + `surface` primitive +
> components `note`, `toast`, `input`, `select` (delegates to hover_select) and
> `prompt` (confirm/text). The layout engine, templates, native select chooser
> and button-confirm follow.

## Themes & presets

A theme is a token table (border, padding, zindex, title_pos, dims, `hl`).
Built-in presets differ mainly in border strength:

| Preset      | Border    |
| ----------- | --------- |
| `minimal`   | none      |
| `rounded`   | rounded (default) |
| `solid`     | single    |
| `double`    | double    |
| `ascii`     | ASCII glyphs (terminals without good Unicode) |
| `menu`      | rounded, but with a **coloured** frame (`Function`) — `kit.menu`'s default |

Highlights link to standard groups (`NormalFloat` / `FloatBorder` /
`FloatTitle` / `PmenuSel` / …), so the default look is correct in any
colorscheme.

```lua
require("ui.kit").setup({
  default = "rounded",
  presets = {
    myproject = { border = "double", hl = { title = "Title" } },
  },
})
```

A theme argument (anywhere one is accepted) is a preset name, a partial override
table (deep-merged over the active default), or `nil`.

## Surface

One themed float + a lifecycle handle:

```lua
local kit = require("ui.kit")
local s = kit.surface.open({ lines = { "hi" }, theme = "double", title = "X" })
s:set_lines({ "new", "content" })
s:set_title("Y")
s:focus()
s:on_close(function() end)
s:close()
```

`open(opts)` accepts `lines`, `theme`, `title`, `title_pos`, `width`, `height`,
`relative`, `row`, `col`, `zindex`, `enter`, `focusable`, `nice_quit`,
`filetype`, `modifiable`, `wo`, `bo`. Returns the handle, or `nil` on failure.

## Components

`kit.popup(opts)` dispatches on `opts.type` (convenience aliases: `kit.note`,
`kit.toast`, `kit.input`, `kit.select`, `kit.prompt`). Not-yet-built types warn
with their planned phase.

```lua
kit.popup({ type = "note",  title = "Saved", message = "Wrote 3 files", timeout = 2000 })
kit.popup({ type = "viewer", title = "Node Info", lines = { "name: foo.lua", "size: 128 B" } })
kit.popup({ type = "toast", message = "background job done" })
kit.popup({ type = "input", prompt = "New name", default = "x", on_submit = function(t) end })
kit.popup({ type = "input", prompt = "Password", secret = true, on_submit = function(pw) end })
kit.popup({ type = "input", prompt = "Path", completion = "file", on_submit = function(p) end })
kit.popup({ type = "live_input", prompt = "Filter", on_change = function(query) end })
kit.popup({ type = "form", fields = { { name = "image", label = "Image", required = true } },
            on_submit = function(values) end })
kit.popup({ type = "select", message = "Pick", selection = { "a", "b" }, on_select = function(c, i) end })
kit.popup({ type = "prompt", question = "Delete?", answer_type = "confirm", on_answer = function(yes) end })
```

| Type     | What it is |
| -------- | ---------- |
| `note`   | centered title + message float; optional `timeout` (ms) auto-dismiss |
| `viewer` | read-only info panel; auto-sized to content; closes on q/`<Esc>` OR the moment focus leaves it — the "show some info, dismiss it" float duplicated 6+ times across consumer plugins before this existed |
| `toast`  | ephemeral top-right message; stacks; never steals focus; auto-dismiss |
| `input`  | single-line insert-mode prompt; `<CR>` submits, `<Esc>` cancels; `secret = true` masks it as you type; `completion = "file"` (or any `getcompletion()` type) wires `<Tab>` to the native completion popup |
| `live_input` | like `input`, but also debounces keystrokes into `on_change(query)` as you type — for filter/search boxes |
| `form`   | sequential multi-field prompt — chained `input`s collected into one keyed table; `<Esc>` skips an optional field, aborts on a `required` one |
| `select` | native themed list chooser (single/multi; `j`/`k`, `<CR>`, `<Tab>` mark) |
| `prompt` | ask: `answer_type = "confirm"` (yes/no → boolean) or `"text"` |
| `confirm` | button dialog — horizontal buttons, `h`/`l`/arrows move, `<CR>` confirm, `<Esc>` cancel, left click confirms a button directly |
| `menu`    | anchored action list — `{ label, action }` items; picking runs the action. Also renders [`ui.contextmenu`](../contextmenu/README.md) tables (`name`/`cmd`, `{ name = "separator" }`, `rtxt`, `icon`, nested `items`) and takes `mouse = true` to anchor at the pointer. A row is a set of **fixed-width columns** measured across the whole level — icon, label, fly-out marker, `rtxt` — so entries line up whichever section they sit in; `icon` is a field, never a prefix on `label`. The marker follows the *label* column rather than the row, so it stays beside the list instead of against the frame, and the hint column keeps the right edge. Named groups (`contextmenu.heading`) are drawn as titled frames (`group_style` = `"box"` \| `"header"` \| `"plain"`; a menu that names nothing keeps the plain divider look). The block cursor is hidden while it is open, one left click picks, and a click or focus change elsewhere dismisses it (`hide_cursor` / `single_click` / `close_on_focus_lost` turn those off). A pick is acknowledged before it is acted on: the row lights up (`KitFlash`) for `flash_ms` (default 100) and the action follows, the way a button shows its press — the delay is the point, since a leaf action closes the menu and a flash painted at that moment would never be seen. A menu dismissed while a row is lit runs nothing (`flash_on_select = false` turns it off). Defaults to the `menu` preset, so the frame is coloured. Drilling into a submenu and walking back swap the list **inside the same window** — no flash, and the menu stays put |
| `progress`| passthrough to `lib.nvim.progress` (`:update`/`:finish`/`:cancel`) |
| `compare` | pick two items out of one picker, then view them side by side — see [Compare](#compare-pick-two-view-side-by-side) below |
| `shortlist` | promptless list+preview for a handful of items — see [Shortlist](#shortlist-promptless-list--preview) below |

## Chip (persistent corner status)

`kit.chip` is `kit.toast`'s opposite number: instead of an ephemeral,
auto-dismissing message, a chip is mounted once under a stable `id` and stays
on screen — updated in place — until unmounted or its own text says there is
nothing to show. Built for a plugin's own always-on indicator (an active
session name, an ambient container count, ...) that today only gets a
one-shot `vim.notify` toast nobody remembers five seconds later.

```lua
local chip = require("ui.kit").chip

chip.mount({
  id = "sessions",
  text = function() return require("sessions.statusline").component() end,
  anchor = "bottom-left",              -- or bottom-right / top-left / top-right
  color = "DiagnosticInfo",            -- a highlight group (theme-linked), or { fg = "#89b4fa", bg = "#1e1e2e" }
  shape = "rounded",                   -- or "rect" (borderless block) / "text" (no box at all, just coloured text)
})

-- Whenever the consumer's own state changes (a save/load/dirty event, ...):
chip.refresh("sessions")

-- A brief colour flash on top of the persistent state, e.g. right after a save:
chip.pulse("sessions", { color = "DiagnosticWarn", duration_ms = 300 })

chip.unmount("sessions")
```

An empty resolved `text` (or `visible = false`) hides the chip entirely —
no placeholder box, matching the "return `''` when idle" convention several
statusline components already use, so wiring one straight into `text` just
works. There is no polling: the consumer decides when its own state changed
and calls `refresh(id)` — same reasoning `ui.context`'s overlay gives for
being driven off events rather than a timer.

Each chip gets its own highlight group rather than sharing `ui.kit.theme`'s
global `Kit*` groups, so several chips (or a chip and a modal kit popup) can
be on screen at once with independently coloured chips. A colour given as a
highlight-group name re-tints itself on `ColorScheme`; an explicit `{ fg, bg
}` pair stays fixed. A floating window belongs to the tabpage it was opened
on, so a chip re-opens itself on `TabEnter` to follow the user across tabs.

## Layout engine (Phase 3, partial)

Turn a declarative region spec into aligned `nvim_open_win` geometry for several
coordinated floats — the "three windows that line up perfectly" primitive.

```lua
-- ready-made picker template (prompt / results / preview):
local group = kit.layout.template("picker", { theme = "rounded" })
group.slots.results:set_lines(matches)
group.slots.preview:set_lines(preview_lines)
group.close()               -- closes every slot

-- or compute geometry yourself (pure, no I/O) and mount:
local geo = kit.layout.compute({
  width = 0.8, height = 0.8, gap = 0,
  rows = {
    { name = "prompt", height = 3 },
    { cols = { { name = "results", width = 0.4 }, { name = "preview", width = 0.6 } } },
  },
})
```

### Interactive picker

`kit.picker(opts)` turns the picker template into a working, Telescope-style
picker: an insert-mode prompt drives the results slot.

```lua
local p = kit.picker({
  on_change = function(query)          -- debounced as the user types
    p.set_results(compute_matches(query))
  end,
  on_submit = function(idx, text)      -- <CR> on the highlighted result
    open(text)
  end,
})
-- <C-n>/<C-p> or arrows move the selection; <Esc> closes.
-- p.query() / p.set_results(lines) / p.move(delta) / p.submit() / p.close()
```

`kit.picker({ prompt = "plain" })` falls back to a bare
`kit.layout.template("picker")` whose prompt slot you wire yourself.

### Shortlist (promptless list + preview)

`kit.shortlist(opts)` is for a handful of items (a mark list, recent
buffers, …) that don't need fuzzy search — no prompt row, and preview sits
above the results instead of beside it, so there's room for a real file path
instead of a narrow results column's worth of it. Navigation is `kit.chooser`'s
own (`j`/`k`/arrows wrap-around, `<CR>` selects, `<Esc>`/`q` closes); the
preview follows the selection however the cursor gets there — keys, mouse,
`gg`/`G` — via `CursorMoved`, not a hand-picked set of keys.

```lua
local handle = kit.shortlist({
  items = marks,                          -- your own item values, any shape
  format_item = function(item, width)     -- results line for this item, at
    return path_shorten(item.path, width) -- most `width` columns wide
  end,
  render = function(item, surface)        -- same contract as kit.compare
    surface:set_lines(read_lines(item.path))
  end,
  on_submit = function(item, idx) open(item.path) end,
  on_close = function() end,
})
-- handle.current_item() / handle.current_index() read the highlighted item
-- without submitting -- e.g. for extra keymaps on handle.results.bufnr.
```

`format_item` is called once per item with that run's actual results-slot
width, so the label can show as much of a path as fits rather than a fixed
truncation — `lib.nvim.fs.path_shorten(path, width)` (style `"fit"`, the
default) is built for exactly this: it keeps the drive/root and the filename
visible and collapses the middle.

If `render` raises (a file it cannot read into lines, say), the pane shows one
line, `preview failed: <the error's first line>`, instead of keeping the previous
item's text under the new selection. `surface:set_lines` restores the buffer's
`modifiable` even when it is the one that raises, so a read-only preview stays
read-only.

#### Working in the preview

The preview is a real window, so it can be worked in and not only looked at.
Whether it is read-only is the caller's choice (`preview_bo = { modifiable =
false }`); with that, everything that reads works there — motions, `/`, visual
mode, `y` — and nothing can change the buffer.

| Where | Keys | Does |
| --- | --- | --- |
| list, preview | `<C-f>`, `<PageDown>` | scroll the preview one page down |
| list, preview | `<C-p>`, `<C-b>`, `<PageUp>` | one page up |
| list, preview | `<C-d>` / `<C-u>` | half a page down / up |
| list, preview | `<Tab>`, `<C-w>w`, `<C-w><C-w>`, `<C-w>W` | hop between list and preview |
| preview | `<C-w>j` | down to the list (a no-op in the list -- nothing below it) |
| list | `<C-w>k` | up to the preview (a no-op in the preview -- nothing above it) |
| preview | `<CR>` | submit at the cursor line: `on_preview_submit(item, idx, { row, col })` |
| preview | `q`, `<Esc>` | close the popup (the list has its own) |

A page is Vim's own (the window height less two lines of overlap). `<C-p>`
scrolls up on purpose although Vim means "one line up" by it: it pairs with
`<C-f>`, and `<C-b>` stays for whoever's fingers know Vim's own pair. The window
cycle stays inside the popup, because left alone `<C-w>w` walks on into the
editor window underneath and leaves the popup stranded on top. `<C-w>j`/`<C-w>k`
join it, but direction-aware rather than a blind toggle: the preview sits above
the list, so `<C-w>j` only moves from the preview down to the list and `<C-w>k`
only from the list up to the preview -- the edge case (`<C-w>j` in the list,
`<C-w>k` in the preview) is a no-op, the way a real window-cycle does nothing at
the edge of a layout, not a jump the wrong way. For the same "leaves the popup
stranded" reason, the popup closes when focus goes to any other window (a click
into the editor, `<C-w>h`, a tab switch). The focused window's border is lit
(`KitAccent`, the other one `KitBorder`) and each window carries a footer with
the keys that work in it — on a themed float that has a border.

```lua
kit.shortlist({
  items = marks,
  render = render,
  on_submit = function(item) open(item.path) end,
  -- <CR> in the preview, after the popup closed; pos = the preview cursor
  on_preview_submit = function(item, idx, pos) open(item.path, pos.row, pos.col) end,
  preview_bo = { modifiable = false },
})
```

`on_preview_submit` is optional: without it `<CR>` in the preview falls back to
`on_submit(item, idx)`. All of it is on by default and switchable:

| Option | Default | Does |
| --- | --- | --- |
| `preview_keys` | the table above | `false` binds none; a group set to a list of your own replaces that group's keys (a bare string is a list of one), set to `false` drops it. Entries that are not non-empty strings are ignored, and a group left with none is off. Groups: `scroll_down`, `scroll_up`, `half_down`, `half_up`, `focus`, `cycle`, `close`, `submit`. `close` binds on the preview **and** on the list, so `close = { "q", "<Esc>", "<C-e>" }` makes `<C-e>` a toggle for a popup that a `<C-e>` mapping opens |
| `close_on_leave` | `true` | close the popup when focus goes to a window that is neither the list nor the preview |
| `hints` | `true` | the lit border and the footers; `false` leaves both alone |

The keys are buffer-local to the two popup windows, so they never touch your
own mappings, and they are set with `record = false` — `lib.nvim`'s keymap
records are keyed by buffer number, and a new popup means a new one.

The same goes for the autocmd hooks of every popup (a surface's `WinClosed`, the
resize and selection hooks of the shortlist, picker and compare): they are
created under a group named after the window id, so `lib.nvim`'s autocmd records
would keep one entry per popup for good. They pass `record = false` too, and
`lib.nvim`'s own `close_on_focus_lost` helper does the same. Groups with a fixed
name are cleared on every open and stay recorded.

### Compare (pick two, view side by side)

`kit.compare(opts)` picks two items out of one picker, then shows both full
height, side by side — motivated by images.nvim's "browse, pick two, view
next to each other", but not image-specific: `render(item, surface)` is the
only contract, so a text diff or anything else that can paint into a
`kit.surface` works the same way.

```lua
local handle = kit.compare({
  items = candidates,
  render = function(item, surface)     -- called for the live preview AND
    surface:set_lines(read_lines(item)) -- both COMPARE panes
  end,
  on_compare = function(a, b)          -- fires once, before either COMPARE
    -- both picks known here, before either render() call for COMPARE --
    -- e.g. scale two images relative to each other instead of each to its
    -- own pane
  end,
  on_close = function(a, b) end,       -- b is nil on an aborted pick
})
```

Three states, entered in order: **SEARCH** (prompt + results + a live
preview that follows the selection) → **MARKED** (`mark_key`, default
`<M-c>`, or `<CR>`, freezes the current item; the live preview keeps
following the rest of the search) → **COMPARE** (`<CR>` again: both picks
full-height, side by side; `q`/`<Esc>` on either pane closes the whole
thing). `<CR>` does double duty on purpose — it reads as "confirm whichever
pick this is" rather than needing a second dedicated key.

`kit.chooser` is the low-level native chooser `kit.select` (and `compare`'s
own SEARCH state) delegates to — reach for it directly only when a caller
needs `current_item()`/`current_index()`/`move()` outside of `on_select`,
e.g. extra keymaps that read the highlighted item without submitting or
closing. One active instance at a time, shared with `kit.select`.

### Button-confirm

`kit.confirm(opts)` (or `kit.popup({ type = "prompt", answer_type = "confirm",
layout = "buttons" })`) shows a question with a row of horizontal buttons.

```lua
kit.confirm({ question = "Delete 3 files?", on_answer = function(yes) end })     -- Yes/No -> boolean
kit.confirm({ question = "Pick", choices = { "Keep", "Discard", "Cancel" },
              on_answer = function(choice) end })                               -- custom -> string
```

`h`/`l`/arrows/`<Tab>` move focus (the focused button uses `KitSelection`),
`<CR>` confirms, `<Esc>`/`q` cancels (default → `false`, custom → `nil`).

**Mouse:** a left click on a button focuses *and* confirms it in one action
(needs `:set mouse=a`, as any mouse interaction does). Clicking blank space
inside the dialog is a no-op — it does not cancel, matching the rest of the
kit, where clicking empty space never dismisses a surface. Hit-testing uses
`getmousepos()` against the per-button ranges the focus highlight already
tracks, so the click target is exactly the visible `[ Label ]` box.

### Form (multi-field)

`kit.form(opts)` chains `kit.input` prompts field-by-field into one keyed
result table — the "several `vim.fn.input`/`vim.ui.input` calls in a row"
pattern (e.g. sandbox.nvim's Image/Name/Ports/Volumes/Env chain).

```lua
kit.form({
  fields = {
    { name = "image", label = "Image", required = true },  -- <Esc> here aborts the form
    { name = "name", label = "Name" },                       -- <Esc> here skips (keeps default)
    { name = "ports", label = "Ports" },
  },
  on_submit = function(values) end,  -- { image = "...", name = "...", ports = "..." }
  on_cancel = function() end,        -- fires only if a `required` field was <Esc>-ed
})
```

Each field accepts the same options as `kit.input` (`default`, `theme`,
`width`, `relative`, `expand_env`), falling back to `opts.theme`/`opts.width`/
`opts.relative` when omitted.

### Live input (debounced on_change)

`kit.live_input(opts)` is `kit.input` plus a debounced `on_change(query)` —
for filter/search boxes that need to refresh a results list or preview on
every keystroke, not just on submit (`kit.picker`'s prompt slot uses the same
debounce timer internally).

```lua
kit.live_input({
  prompt = "Filter",
  debounce = 80,  -- ms after the last keystroke before on_change fires (default 80)
  on_change = function(query) end,   -- fired repeatedly as the user types
  on_submit = function(query) end,   -- <CR>
  on_cancel = function() end,        -- <Esc>
  -- row/col (relative="editor" only) override the default centered
  -- placement, e.g. to anchor the bar to the bottom edge of a host window.
})
```

### Secret input (masked entry)

`kit.input({ secret = true, ... })` masks the input as you type — a
`vim.fn.inputsecret` replacement. Each typed character is concealed behind
`opts.mask` (default `"*"`) via `conceal`, re-derived from the buffer's actual
content on every edit (paste, backspace, mid-line insert all just work). The
underlying buffer still holds the real text — `on_submit` reads it straight
off the buffer — but it's never echoed on screen, undo is disabled on that
buffer (`undolevels = -1`), and (like every kit scratch buffer) it was never
written to disk in the first place (`swapfile = false`) and is wiped the
moment the float closes.

```lua
kit.input({
  prompt = "Registry password",
  secret = true,
  on_submit = function(password) end,
})
```

### File-path completion

`kit.input({ completion = "file", ... })` — a `vim.fn.input(..., completion =
"file")` replacement. `<Tab>` completes the last whitespace-delimited
fragment before the cursor via `vim.fn.getcompletion()` and opens Neovim's
real completion popup (`vim.fn.complete()`), so `<C-n>`/`<C-p>` cycle it same
as anywhere else. While the popup is open, `<Tab>`/`<S-Tab>` advance/retreat
the selection instead of re-triggering, and `<CR>` accepts the highlighted
candidate rather than submitting the whole prompt (a second `<CR>` — popup
now closed — submits). `completion` accepts any type name `getcompletion()`
does (`"dir"`, `"shellcmd"`, `"buffer"`, ...), not just `"file"`.

```lua
kit.input({
  prompt = "Path to executable",
  completion = "file",
  on_submit = function(path) end,
})
```

### Sync bridge (blocking wrapper)

`kit.input`/`kit.form`/`kit.live_input` are async — `on_submit`/`on_cancel`
fire later, once the user responds. `kit.sync(open_fn, opts, timeout_ms?)`
bridges one of them back to a plain return value via `vim.wait()`, for call
chains built around a blocking `vim.fn.input()` that can't easily be recast
to callback style. Only safe to call from a normal call stack (a command
handler, keymap callback, ...) — never from a fast-event/libuv callback
context, the same restriction `vim.wait()` itself has.

```lua
local values, cancelled, timed_out = kit.sync(kit.form, {
  fields = {
    { name = "condition", label = "Condition", default = "condition" },
  },
}) -- default timeout: 10 minutes (a safety net, not the expected path)
if not cancelled and values then
  vim.notify(values.condition)
end
```
