# ui.slots

Numbered **slots**: each one is an action, not just a path. A slot can open a
file, open an address, copy text to the clipboard, run an Ex command with fixed
arguments, call a Lua function, or jump to a mark of
[sessions.nvim](https://github.com/StefanBartl/sessions.nvim). They are shown as
a stack of rounded chips at the edge of the editor, or in a focusable panel with
a preview. The number of slots has no upper bound in memory; what is saved
between sessions is limited (see "The data file").

Off until asked for:

```lua
require("ui").setup({
  slots = {
    enabled = true,                    -- a table does not switch it on by itself
    show = true,                       -- open the bar at startup
    keys = { apply = "<leader>%d", panel = "<leader>sp", add = "<leader>sa" },
    slots = {
      [1] = { kind = "file", path = "{root}/TODO.md" },
      [2] = { kind = "yank", text = "git rebase -i HEAD~{count}" },
      [3] = { kind = "cmd", cmd = "Telescope", args = "live_grep cwd={cwd}" },
      [4] = { kind = "url", url = "https://neovim.io/doc/" },
      [5] = { kind = "lua", fn = function(ctx) vim.notify("slot " .. ctx.n) end },
    },
  },
})
-- or, without ui.setup:
require("ui.slots").setup({ ... })
```

`slots = true` is the same as `{ enabled = true }`; **a table only sets the
options** and needs `enabled = true` to switch the slots on. `ui.setup({ all = true })` does
**not** switch the slots on. Requiring `ui.slots` registers no command, no key
and no autocommand; `:UI slots ...` and every API function switch it on for the
session.

## Kinds

| `kind` | Payload | Does | Kept in the data file |
| --- | --- | --- | --- |
| `file` | `path`, `line?`, `col?`, `target?` | opens the file (a missing one is reported, never created); a network path (`\\host\share`) only from `setup()` | yes |
| `url` | `url` | opens `http`, `https` or `mailto` addresses with the system opener; `file:` only from `setup()` (the opener would run a program as readily as show a document) | yes |
| `yank` | `text`, `register?` | puts the text into the clipboard registers | yes |
| `mark` | `index` | the n-th mark of sessions.nvim | yes (the index only) |
| `cmd` | `cmd`, `args?` (a string, split into words before the placeholders go in, or a list that is taken as it is), `bang?`, `raw_values?` | runs an Ex command (`bang = true` for `:Foo!`); a value that a placeholder puts in and that holds `\|`, a backtick or starts with `+`/`!` is refused rather than quoted, unless `raw_values = true` (for commands that read `<q-args>`/`<f-args>`) | **no** |
| `lua` | `fn` | calls the function with `{ slot, n, count, ... }` | **no** |

`cmd` and `lua` run code, so they come from `setup()` or from Lua only; a data
file that names them is ignored. The same goes for what a data file, the editor
and `add()` may not name (a `file:` address, a network path): they are refused
with the reason, and an entry of a data file is dropped. Your own kinds:
`require("ui.slots").register_kind(name, kind)`.

Every slot also takes `label`, `icon` and `style`.

### Placeholders

`{file} {dir} {root} {cwd} {line} {col} {word} {sel} {clip} {count}` are put in
when the slot runs (and in the preview), read from the window you came from
(from the panel too: `<CR>`, `y` and the rows). `{{` and `}}` are literal
braces. An unknown name stays in the text and is warned about when the slot runs;
`:checkhealth ui` names it for the slots written in `setup({ slots = ... })`, and
`cmd` refuses it in `args`. In an address a value is percent-encoded, except a
placeholder that starts the address (`{clip}`, `{clip}/path`): that is the
address itself, and the scheme that comes out is checked.

## Using it

- `:UI slots` lists them; `:UI slots <n>` runs slot n; `add [n]` puts the
  current file in the next free (or the given) slot; `yank <n>`; `clear <n>|all`;
  `move <from> <to>`; `kinds`; `toggle`, `open`, `close`; `panel`; `edit [n]`.
- **The bar** (`layout = "chips"`): a click runs a slot, a right click opens a
  menu (apply, edit, copy, clear; for a file also open in a split, vsplit or
  tab), the wheel scrolls. With more slots than rows it scrolls like an
  accordion. `style` is `rounded` (default), `double`, `ascii`, `solid` or
  `minimal`; `side` is `right` or `left`; `width` caps the width of a chip.
- **The panel** (`:UI slots panel`): `<CR>` run, type a number to go to that
  slot (`1`, then `2` = slot 12), `e` edit, `a` add, `dd` clear, `y` copy,
  `<C-j>`/`<C-k>` move, `K` the preview, `q`/`<Esc>` close.
- **The preview** (`K`): a file shows its lines at the position it was last left
  at (capped by `preview.max_kb` and `preview.max_lines`); a directory its
  entries; an address its host -- or, with `preview.fetch = true` **and**
  [hover.nvim](https://github.com/StefanBartl/hover.nvim) installed, its page as
  hover.nvim shows it, "loading ..." first. Fetching is a request to that host,
  so it is off by default, and once on it happens for the slot under the cursor
  whenever the preview is shown (also while it follows the cursor). An address
  built from placeholders (`{clip}`, `{file}`, ...) is never fetched: it would
  put your own data into a request. `preview.mode` is `key` (default: `K` opens
  it), `auto` (open by itself, so the preview of the row you start on is there at
  once) or `off`; `preview.delay` is how long the cursor must rest before the
  preview follows it to another row (in `auto` and after `K`).
- **The editor** (`a`/`e`, `:UI slots edit`): pick the kind, fill a form.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled`, `show` | `false` | switch on at startup; open the bar at startup |
| `layout` | `"chips"` | `"chips"` or `"panel"` (what `toggle`/`open`/`close` act on) |
| `side` | `"right"` | edge of the editor for the bar and the panel |
| `width` | `0.25` | how wide the panel is, and the most a chip of the bar may be: a fraction of the editor (up to 1) or a number of columns (above 1) |
| `style` | `"rounded"` | chip style |
| `overflow` | `"accordion"` | what a bar with too many slots does (the only value) |
| `scope` | `"project"` | one data file per project, or `"global"` |
| `persist` | `true` | keep the dynamic slots in the data file |
| `data_dir` | `stdpath("data")/ui/slots` | where the data file lives |
| `save_delay_ms` | `100` | how long after a change the data file is written (`0`: at once) |
| `target` | `"current"` | where a file opens: `current`, `split`, `vsplit`, `tab` |
| `clipboard` | `{ "+", "*", '"' }` | registers a `yank` slot writes |
| `preview` | `{ mode = "key", delay = 150, max_kb = 1536, max_lines = 4000, fetch = false }` | see above |
| `keys` | `{}` | `apply` (one `%d`, for 1 to 9), `count`, `add`, `panel`; nothing is mapped by default |
| `slots` | `{}` | fixed slots, `[n] = { kind = ..., ... }` |
| `kinds` | `{}` | kinds of your own |
| `persistable_kinds` | `file, url, yank, mark` | what a data file may hold |
| `max_file_kb`, `max_string_len` | `256`, `4096` | the largest data file (a bigger list is not saved), and the longest string in a slot |

A wrong option is replaced by its default; it is reported when `setup()` runs and
by `:checkhealth ui` (also a wrong entry of `keys`).

## The data file

The slots made while working (`add`, the editor) are kept per project in
`stdpath("data")/ui/slots/project-<hash>.json` (`global.json` with
`scope = "global"`). The file is read as untrusted input: a format marker,
size and string limits, only the kinds in `persistable_kinds`; a file that is
not ours is left untouched. Fixed slots from `setup({ slots })` win over a
dynamic one with the same number and are not written back.

**It has a size limit.** A list that takes more than `max_file_kb` (256 KB: some
thousand short paths) is not saved -- with an error on every change after it --
and a file above the limit is not read at all. Raise `max_file_kb` for a longer
list. There is no limit on the number of slots in a session.

## Lua API

`apply(n)`, `add(opts)`, `yank(n)`, `clear(n)`, `clear_all()`, `move(from, to)`,
`list()`, `get(n)`, `last_applied()`, `register_kind(name, kind)`, `panel()`,
`edit(n)`, `setup(opts)`, `enable()`, `disable()`.

## Limits

- **A long list.** The bar and the panel draw every slot from its name as
  written and look closely (is the file there, is it the file you are in, has
  it unsaved changes) only at what is in view, so ten thousand slots open in a
  fraction of a second. A row far down shows its `✗` and its marker when it
  comes into view. The slot of the file you are in (for the bar's focus, the
  panel's start row and the remembered cursor position) is found by the path as
  written; a slot with a placeholder in its path is also asked by real path (the
  first 30 of them), and so are the first 10 slots whose path is somewhere else,
  in case it is a link to the file (200 of each when the panel opens). A
  `{clip}`, `{sel}` or `{word}` path never says which file it is for. `add`
  compares the new file with every file slot by real path: noticeable from a few
  thousand slots.
- **Entries a data file loses.** An entry that is not read (a `file:` address, a
  network path, a kind that may not be there, a number a `setup()` slot has) is
  dropped with one message; the file is copied to
  `<file>.dropped-<time>-<pid>-<n>` before it is saved again (and not saved at
  all while the copy fails).
- Keys on the bar: a click is taken away from the editor on Neovim 0.11+; on
  0.10 it also moves the cursor under the bar.
- Two sessions in the same project write the same data file; the last wins.
- The page preview of an address needs hover.nvim and `preview.fetch = true`, and
  shows text only.
