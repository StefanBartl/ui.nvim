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
The window is `winfixbuf` unless `wo.winfixbuf = false`: a surface lives and dies
with its one buffer, so `<C-o>`, `:bnext` or `:e` in it fail with E1513 instead of
swapping the user's file in and wiping the component's buffer from under it.

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
kit.popup({ type = "sheet", fields = { { name = "image", label = "Image", required = true }, { name = "tag", label = "Tag" } },
            on_submit = function(values) end })
kit.popup({ type = "select", message = "Pick", selection = { "a", "b" }, on_select = function(c, i) end })
kit.popup({ type = "prompt", question = "Delete?", answer_type = "confirm", on_answer = function(yes) end })
```

| Type     | What it is |
| -------- | ---------- |
| `note`   | centered title + message float; optional `timeout` (ms) auto-dismiss |
| `viewer` | read-only info panel; auto-sized to content; closes on q/`<Esc>` OR the moment focus leaves it — the "show some info, dismiss it" float duplicated 6+ times across consumer plugins before this existed |
| `message_log` | scrollable, time-ordered, paginated, collapsible entry list — see [Message log](#message-log-paginated-time-ordered-entry-list) below |
| `toast`  | ephemeral top-right message; stacks; never steals focus; auto-dismiss |
| `input`  | single-line insert-mode prompt; `<CR>` submits, `<Esc>` cancels; `secret = true` masks it as you type; `completion = "file"` (or any `getcompletion()` type) wires `<Tab>` to the native completion popup |
| `live_input` | like `input`, but also debounces keystrokes into `on_change(query)` as you type — for filter/search boxes |
| `form`   | sequential multi-field prompt — chained `input`s collected into one keyed table; `<Esc>` skips an optional field, aborts on a `required` one; `back = true` adds [back navigation](#form-multi-field) (`<BS>` on an empty field, `<S-Tab>`, a `[← Back] [Skip] [Next ↵]` button row, "(2/5)" in the title) |
| `sheet`  | every field of a form at once in ONE float — a labelled row each, inline validation (`required`, `validate`) shown under the field, `[ Submit ] [ Cancel ]` buttons; see [Sheet](#sheet-every-field-at-once) |
| `select` | native themed list chooser (single/multi; `j`/`k`, `<CR>`, `<Tab>` mark) |
| `prompt` | ask: `answer_type = "confirm"` (yes/no → boolean) or `"text"` |
| `confirm` | button dialog — horizontal buttons, `h`/`l`/arrows move, `<CR>` confirm, `<Esc>` cancel, left click confirms a button directly (the button row is `ui.kit.buttons`, shared with the form's) |
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
  shape = "rounded_chip",               -- or "chip" (borderless block) / "classic" (no box at all, just coloured text)
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

#### Item mode (a list of items with marks, highlights and a preview)

With `items` (or `format`) the results slot lists ITEMS instead of plain lines:

```lua
local p = kit.picker({
  items = tasks,
  key = function(t) return t.id end,            -- identity for marks and the cursor (default: the item itself)
  text = function(t) return t.title end,        -- what the prompt's words are matched against (default: item.text)
  format = function(t) return { { t.title, "Title" }, { " " .. t.status, "Comment" } } end,
  preview = function(t, surface) surface:set_lines(read_lines(t.path)) end,   -- follows the cursor item
  selectable = function(t) return not t.heading end,   -- rows that cannot be submitted, marked or rested on (headings)
  keys = { ["<M-d>"] = function(h) finish(h.marked()) end },                 -- lhs -> function(handle), in the prompt
  title = "Tasks", results_width = 0.6,
  on_submit = function(idx, line, item) open(item) end,
  on_close = function() end,
})
-- <Tab> marks and moves down. p.current() / p.marked() / p.set_items(items, { cursor_key?, keep_marks? }) /
-- p.set_title(t) / p.is_closed()
```

The words typed in the prompt filter the list (every word must occur, any case); an empty result stays open.
`set_items` keeps the cursor on its item and the marks of items that are still there.

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

### Message log (paginated, time-ordered entry list)

`kit.message_log(opts)` is a scrollable, time-ordered, paginated, collapsible
entry list — "show a recent, growing, time-stamped list" (first consumer:
debugging.nvim's recent-messages view, backed by `lib.nvim.messages`). It
knows nothing about where entries come from: plain tables in, callbacks for
pagination and live updates.

```lua
local handle = kit.message_log({
  title = "Recent messages",
  entries = lib_messages.snapshot({ since_ms = now - 10000 }),  -- oldest first
  order = "newest_last",            -- or "newest_first"
  collapsed_default = false,
  load_more = function(direction)   -- "older" | "newer"; omit to disable pagination
    return lib_messages.snapshot({ until_ms = oldest_loaded_ms, levels = {...} })
  end,
})

-- Live feed: the caller owns its own subscription and decides what belongs here.
lib_messages.on_message(function(entry)
  handle:append({ entry })
end)
```

An `entry` is `{ time_ms, level?, content }` — `time_ms` just needs to share a
clock with `opts.now_ms` (default `vim.uv.hrtime()/1e6`, monotonic) and the
other entries; this module only ever subtracts two of the caller's own
values, so an epoch clock works equally well.

| Key | Does |
| --- | --- |
| `q`, `<Esc>` | close |
| `<C-j>` | load older entries (`opts.load_more("older")`) |
| `<C-k>` | load newer entries (`opts.load_more("newer")`) |
| `<C-l>` | expand (un-collapse) |
| `<C-h>` | collapse (first content line per entry only, with a "+N more lines" marker) |
| `<C-e>` | toggle collapsed mode |
| `?` | cheatsheet (this table, plus `opts.extra_cheatsheet_lines`) |

Pagination hints render as virtual text at the top/bottom edge (`󰁝 more
above`/`󰁅 more below`) only while `opts.load_more` is set and hasn't yet
reported "nothing left" in that direction — a `load_more` call returning an
empty list hides that arrow for the rest of the popup's life, it is not
re-offered. Plain `j`/`k`/arrows always just scroll; pagination is `<C-j>`/
`<C-k>` only, on purpose (a held `j`/`↓` must never accidentally page).

`handle:append(entries)`, `handle:load_more(direction)`,
`handle:set_collapsed(value?)`, `handle:on_close(cb)`, `handle:close()`.

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

The layout, the focus highlight and the hit-test live in `ui.kit.buttons` — a
small stateless helper (`layout`, `paint`, `hit`, `wrap`, `row_width`) that the
button row under a [`kit.form`](#form-multi-field) field uses as well, so a
click lands on exactly the box that is drawn in both places. It owns no window
or keymap: a caller keeps its own `labels`/`ranges`/`focus` and hands them in.

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

#### Back navigation (`back = true`)

Off by default — a form without `back` is exactly the chain above. With
`back = true` the user can walk back through it to fix an earlier answer:

```lua
kit.form({
  back = true,
  fields = {
    { name = "image", label = "Image", required = true },
    { name = "name", label = "Name" },
    { name = "ports", label = "Ports" },
  },
  on_submit = function(values) end,
  on_cancel = function() end,
})
```

```text
╭──────────── Name (2/3) ────────────╮
│ my-container                       │
│  [ ← Back ]  [ Skip ]  [ Next ↵ ]  │
╰────────────────────────────────────╯
```

- **Keys, in the field:** `<BS>` on an **empty** field (with text it is the
  ordinary backspace), `<S-Tab>` or `<C-p>` (with a completion popup open they
  still belong to the popup) go back to the field before. `<CR>` goes forward,
  `<Esc>` keeps its meaning (skips an optional field, aborts on a `required`
  one) on every field, one reached by going back included. The first field has
  no back: those keys do nothing there and the `[← Back]` button is not drawn.
  A `<BS>` held down never walks back through the earlier answers: a `<BS>`
  that comes less than 300 ms after the previous one, on a field that is empty,
  is the held key repeating and is ignored; press it again after a pause to go
  back.
- **The previous answer is the editable text.** Going back shows that field's
  answer again, cursor at the end, so only the correction has to be typed. A
  field left half-typed keeps its text for when the user comes back to it, so
  going back and forth loses nothing; the result table is only handed to
  `on_submit` after the last field. Skipping a field again (`<Esc>`) resets it
  to its `default`, as it always did.
- **Step indicator.** The title reads `Label (2/5)`; a one-field form has none.
- **Back from the first field (`on_back`).** A form that is itself one step of a
  longer flow (a number, then an area, then these fields) can pass
  `on_back = function(values) end`. The first field then has a back as well — the
  same keys, and a `[← Back]` button — which closes the form and calls `on_back`
  with the answers so far (the first field's text as it stood, and any later
  answers the user had typed and walked back from) instead of doing nothing.
  Neither `on_submit` nor `on_cancel` fires; reopen the form with those answers
  as `default`s when the flow comes forward again. Without `on_back` the first
  field has no back, as above.
- **Buttons.** A clickable row under the field: `[← Back]` (not on the first
  field), `[Skip]` (not on a `required` field — it is `<Esc>`, which aborts
  there) and `[Next ↵]` (`[Done ↵]` on the last field — it is `<CR>`). A left
  click focuses *and* presses a button in one action, like `kit.confirm`. From
  the field, `<Down>` or `<Tab>` moves the focus onto the row, starting on
  `Next`; there `h`/`l`/`<Left>`/`<Right>`/`<Tab>`/`<S-Tab>` move it (wrapping),
  `<CR>` presses the focused button, `<Esc>` still cancels, and `<Up>`/`k`/`i`/
  `a` (or a click on the text) return to the field. The labels are read-only
  while the buttons have focus. Mouse needs `:set mouse=a`, as it always does.
  The row stays in view when a long answer scrolls the field sideways, and a
  paste that carries a newline (a copied line usually does) stays one line: its
  lines are joined with a space and the row remains under the field.
- **`kit.input` underneath.** `back` is `kit.input`'s two opt-in options, which
  can be used on their own: `on_back = function(line) end` (the keys above; it
  gets the line as it stood) and `buttons = { { id = "back" | "skip" |
  "submit", label = "…" }, … }` (`submit` is `<CR>`, `skip` is `<Esc>`, a
  `back` button needs `on_back`). Without them an input is one line and binds
  none of these keys.

Every field of a chain opens in Insert mode, the one reached by going back
included. So does whatever else a callback opens to be typed into -- a `kit.sheet`
(whose first row is text), a `kit.picker`, a `kit.live_input` or a `kit.compare`
opened from an `on_submit` -- and a prompt that was opened from a window that
was already there leaves that window in the mode it was in. A component of your
own that opens a window and asks for Insert mode with `:startinsert` counts itself
with `require("ui.kit.input").mark_opened()` so that the prompt closing under it
does not stop Insert mode.

### Sheet (every field at once)

`kit.sheet(opts)` (or `kit.popup({ type = "sheet", ... })`) is the other shape
of a form: not one prompt per field in a row, but ONE float that shows every
field at once, a row each with its label. Use it when the answers belong
together and the person should see — and be able to fix — all of them before
committing; `kit.form` stays the right tool for a short chain of questions.
Same callbacks (`on_submit(values)` / `on_cancel()`), same keyed result table,
so `kit.sync(kit.sheet, opts)` works too.

```lua
kit.sheet({
  title = "New case",
  fields = {
    { name = "number", label = "Case number", required = true, live = true,
      validate = function(v)
        if v:match("^%d+$") then return true end
        return false, "digits only"            -- the message shows under the field
      end },
    { name = "area", label = "Area", kind = "select", choices = { "EMEA", "APAC" } },
    { name = "title", label = "Title" },
    { name = "token", label = "Token", secret = true },
  },
  submit_label = "Create", cancel_label = "Abort",     -- default "Submit" / "Cancel"
  on_submit = function(values) end,  -- { number = "...", area = "EMEA", title = "...", token = "..." }
  on_cancel = function() end,
})
```

```text
╭────────────────────────── New case ──────────────────────────╮
│Case number* 12x                                              │
│             ✗ digits only                                    │
│Area         EMEA   ◂ ▸                                       │
│Title        Printer on fire                                  │
│Token        ********                                         │
│                                                              │
│                   [ Create ]  [ Abort ]                      │
╰──────────────────────────────────────────────────────────────╯
```

**Fields.** `{ name, label?, kind?, default?, required?, validate?, live?,
depends_on?, expand_env?, completion?, secret?, mask?, choices? }`:

- `kind = "text"` (default) is an editable line like [`kit.input`](#components):
  `default`, `expand_env`, `completion` and `secret` behave the same. The
  field's row opens in Insert mode.
- `kind = "select"` with `choices` (a list of strings) is a fixed choice shown
  with `◂ ▸`: `h`/`l` (or the arrows) cycle it, `<CR>`/`<Space>` open
  `kit.select` over the choices and a pick moves on to the next field.
  `default` names the choice shown first.

**Validation, next to the field.**

- `required = true` rejects a blank value ("required", or `opts.required_message`).
- `validate(value) -> ok, err` rejects when `ok` is falsy, showing `err`
  ("invalid" without one) as red text (`KitError`) in a line under the field. It
  is not called for an empty optional field, so it never has to handle `""`;
  `value` is what `on_submit` will get (after `expand_env`); a validator that
  raises is a rejection with the error as its message.
- A field is checked when the user **leaves** it and on **submit**. A field that
  shows an error is checked again on every edit, so the message goes away the
  moment the value is right; `live = true` checks a field on every edit from the
  start. `depends_on = "other"` (or a list of names) is for a validity that
  depends on another field — a number that has to be free in the chosen area: the
  field is checked again whenever one of those changes (when it has a value or a
  message showing; a blank, untouched one stays quiet).
- Submit is blocked while any field fails, and the focus jumps to the first
  invalid one. The window is resized to what is shown (a row per message), so
  the sheet grows and shrinks, staying centered.

**Keys** (the same in Insert mode on a text row and in Normal mode elsewhere):

| Key | Does |
| --- | --- |
| `<Tab>` / `<S-Tab>` | next / previous field, then the two buttons, wrapping |
| `<Down>` / `<Up>` (`j` / `k` in Normal mode) | the same without wrapping |
| `<CR>` | next field; on the last field it presses the Submit button; on a select it opens the chooser; on a button it presses it |
| `<Esc>` | cancel the whole sheet, from anywhere |
| left click | focus the field under the pointer (cursor at the click), or press the button (needs `:set mouse=a`) |
| `h` / `l`, `<Space>` | on the button row: move along / press; on a select: cycle / open the chooser |

On a field with `completion`, `<Tab>` is the completion key (as in `kit.input`)
and `<S-Tab>` still goes back unless a popup is open; move on with `<Down>`/`<CR>`.

**Drawn how.** The buffer holds only the values, one per line (then a blank line
and the buttons); the labels are the window's `'statuscolumn'`. So an edit can
never touch a label, the cursor cannot land on one, and a long value wraps under
the value column. The button row is `ui.kit.buttons`, shared with `kit.confirm`
and the form's. A paste with a newline in it is joined into its row with a
space. `KitAccent` marks the focused field's label, `KitMuted` the others,
`KitError` the messages and the `*` of a required field.

The returned surface has five extra methods, for driving a sheet from code and
from specs: `s:submit()`, `s:cancel()`, `s:focus_field(name | index)`,
`s:validate()` (check every field now so the messages show, without submitting;
returns whether all passed — for a sheet opened with values that may already be
wrong) and `s:state()` (`{ focus = <field name | "submit" | "cancel">, values, errors }`).
Opening options: `focus` (field name or position to start on), `width`
(default 60), `relative` (default `"editor"`), `theme`.

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
moment the float closes. The Insert run that typed it is also what the `.`
register (`:registers`, `<C-r>.`) and the redo buffer keep -- a `.` in any buffer
would type the password there -- so when the prompt closes (submitted, cancelled or
closed from outside; the same goes for a `kit.sheet` with a `secret` field) they are
overwritten with an empty run. A macro being recorded (`q`) still holds the keys it
saw, as it does for `vim.fn.inputsecret`.

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
does (`"dir"`, `"shellcmd"`, `"buffer"`, ...), not just `"file"`. For `"file"` and
`"dir"`, a fragment that more than 300 entries start with (for `"dir"` the files
among them count) gets its list from one directory listing, matched and sorted
as `getcompletion()` does (case ignored under `'fileignorecase'` or
`'wildignorecase'`, and always on Windows; ordered by upper case under
`'fileignorecase'`) and cut to 300 (`getcompletion()` stats every candidate:
half a second for a directory of five thousand files; this stats no file or
directory, and a link or an entry the listing gives no type for only until 300
are found, which for `"dir"` can be every link of the directory, once, as no link
to a file is a directory; a link that leads nowhere is left out, as
`getcompletion()` leaves it); typing on narrows it. A fragment with a backtick
in it is never completed:
`getcompletion()` runs the span between backticks through the shell, and the
fragment may be pasted text.

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
