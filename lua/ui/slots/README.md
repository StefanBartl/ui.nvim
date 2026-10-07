# ui.slots

Numbered **slots**: each one is an action, not just a path. A slot can open a
file, open an address, copy text to the clipboard, run an Ex command with fixed
arguments, call a Lua function, or jump to a mark of
[sessions.nvim](https://github.com/StefanBartl/sessions.nvim). They are shown as
a stack of rounded chips at the edge of the editor, or in a focusable panel with
a preview. There is no upper bound on the number of slots.

Off until asked for:

```lua
require("ui").setup({
  slots = {
    enabled = true,
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

`slots = true` is the same as `{ enabled = true }`. `ui.setup({ all = true })`
does **not** switch the slots on. Requiring `ui.slots` registers no command, no
key and no autocommand; `:UI slots ...` and every API function switch it on for
the session.

## Kinds

| `kind` | Payload | Does | Kept in the data file |
| --- | --- | --- | --- |
| `file` | `path`, `line?`, `col?`, `target?` | opens the file (a missing one is reported, never created); a network path (`\\host\share`) only from `setup()` | yes |
| `url` | `url` | opens `http`, `https` or `mailto` addresses with the system opener; `file:` only from `setup()` (the opener would run a program as readily as show a document) | yes |
| `yank` | `text`, `register?` | puts the text into the clipboard registers | yes |
| `mark` | `index` | the n-th mark of sessions.nvim | yes (the index only) |
| `cmd` | `cmd`, `args?` | runs an Ex command; a value with `|`, a backtick or a leading `+`/`!` is refused rather than quoted | **no** |
| `lua` | `fn` | calls the function with `{ slot, n, count, ... }` | **no** |

`cmd` and `lua` run code, so they come from `setup()` or from Lua only; a data
file that names them is ignored. The same goes for what a data file, the editor
and `add()` may not name (a `file:` address, a network path): they are refused
with the reason, and an entry of a data file is dropped. Your own kinds: `require("ui.slots").register_kind(name, kind)`.

Every slot also takes `label`, `icon` and `style`.

### Placeholders

`{file} {dir} {root} {cwd} {line} {col} {word} {sel} {clip} {count}` are put in
when the slot runs (and in the preview), read from the window you came from.
`{{` and `}}` are literal braces. An unknown name stays in the text and is
reported by `:checkhealth ui`. In an address a value is percent-encoded.

## Using it

- `:UI slots` lists them; `:UI slots <n>` runs slot n; `add [n]` puts the
  current file in the next free (or the given) slot; `yank <n>`; `clear <n>|all`;
  `move <from> <to>`; `kinds`; `toggle`, `open`, `close`; `panel`; `edit [n]`.
- **The bar** (`layout = "chips"`): a click runs a slot, a right click opens a
  menu, the wheel scrolls. With more slots than rows it scrolls like an
  accordion. `style` is `rounded` (default), `double`, `ascii`, `solid` or
  `minimal`; `side` is `right` or `left`.
- **The panel** (`:UI slots panel`): `<CR>` run, type a number to go to that
  slot (`1`, then `2` = slot 12), `e` edit, `a` add, `dd` clear, `y` copy,
  `<C-j>`/`<C-k>` move, `K` the preview, `q`/`<Esc>` close.
- **The preview** (`K`): a file shows its lines at the position it was last left
  at (capped by `preview.max_kb` and `preview.max_lines`); a directory its
  entries; an address its host -- or, with `preview.fetch = true`, its page as
  [hover.nvim](https://github.com/StefanBartl/hover.nvim) shows it, "loading ..."
  first. Fetching is a request to that host, so it is off by default, and once on
  it happens for the slot under the cursor whenever the preview is shown (also
  while it follows the cursor). An address built from placeholders (`{clip}`,
  `{file}`, ...) is never fetched: it would put your own data into a request. `preview.mode` is `key` (default), `auto` or `off`.
- **The editor** (`a`/`e`, `:UI slots edit`): pick the kind, fill a form.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled`, `show` | `false` | switch on at startup; open the bar at startup |
| `layout` | `"chips"` | `"chips"` or `"panel"` (what `toggle`/`open`/`close` act on) |
| `side`, `width` | `"right"`, `0.25` | edge, and the width of the panel (a fraction) |
| `style` | `"rounded"` | chip style |
| `scope` | `"project"` | one data file per project, or `"global"` |
| `persist` | `true` | keep the dynamic slots in `stdpath("data")/ui/slots/` |
| `target` | `"current"` | where a file opens: `current`, `split`, `vsplit`, `tab` |
| `clipboard` | `{ "+", "*", '"' }` | registers a `yank` slot writes |
| `preview` | `{ mode = "key", delay = 150, max_kb = 1536, max_lines = 4000, fetch = false }` | see above |
| `keys` | `{}` | `apply` (one `%d`, for 1 to 9), `count`, `add`, `panel`; nothing is mapped by default |
| `slots` | `{}` | fixed slots, `[n] = { kind = ..., ... }` |
| `kinds` | `{}` | kinds of your own |
| `persistable_kinds` | `file, url, yank, mark` | what a data file may hold |
| `max_file_kb`, `max_string_len` | `256`, `4096` | limits for a data file |

A wrong option is replaced by its default and reported when `setup()` runs and
by `:checkhealth ui`.

## The data file

The slots made while working (`add`, the editor) are kept per project in
`stdpath("data")/ui/slots/project-<hash>.json` (`global.json` with
`scope = "global"`). The file is read as untrusted input: a format marker,
size and string limits, only the kinds in `persistable_kinds`; a file that is
not ours is left untouched. Fixed slots from `setup({ slots })` win over a
dynamic one with the same number and are not written back.

## Lua API

`apply(n)`, `add(opts)`, `yank(n)`, `clear(n)`, `clear_all()`, `move(from, to)`,
`list()`, `get(n)`, `last_applied()`, `register_kind(name, kind)`, `panel()`,
`edit(n)`, `setup(opts)`, `enable()`, `disable()`.

## Limits

- Keys on the bar: a click is taken away from the editor on Neovim 0.11+; on
  0.10 it also moves the cursor under the bar.
- Two sessions in the same project write the same data file; the last wins.
- The preview of an address needs hover.nvim and shows text only.
