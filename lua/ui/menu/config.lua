---@module 'ui.menu.config'
--- Defaults of `ui.menu`, and its config store (`lib.lua.config.new` via
--- `ui.util.config`).

local M = {}

---@class Ui.Menu.Extra
---@field label string  # menu row text
---@field cmd? string|function  # an Ex command (`"Foo bar"`) or a callback
---@field keys? string  # instead of `cmd`: keys to feed, with remapping -- `"<leader>ha"` runs that mapping
---@field section? string  # heading it is grouped under (default `"Custom"`); entries sharing a name share one section
---@field plugin? string|string[]  # module(s) that must be installed, else the row is not shown
---@field ft? string|string[]  # only in buffers of these filetypes
---@field when? fun(buf: integer): boolean  # extra gate, evaluated at open time
---@field icon? string
---@field hint? string  # right-aligned text, usually the mapping
---@field enabled? boolean  # `false` keeps it configured but hidden

---@class Ui.Menu.ContributorSpec
---@field name string  # key for `integrations = { <name> = false }`
---@field module string  # `require`d at open time; exposes `submenu()` (and optionally `enabled()`)
---@field icon? string
---@field ft? string|string[]  # only in buffers of these filetypes
---@field applies? fun(buf: integer): boolean
---@field lazy? { label: string, plugin?: string }  # skip prewarm and the eager submenu(): show one plain entry from `label`, `require(module)` and open the real submenu only when it is picked. For a plugin lazy.nvim loads whole on any require under it (no cheap "just the label" require exists), e.g. one with no `event` trigger. `plugin` (its lazy.nvim name) lets presence be checked without loading it; defaults to `name`.

---@class Ui.Menu.Opts
---@field mouse? boolean  # bind `<RightMouse>` (default true)
---@field key? string|false  # bind this key to the same menu at the cursor (default false: no global key is taken unasked)
---@field prewarm? boolean  # load the sister plugins' menu modules in idle slices after startup, so the first open is not a stall (default true; `false` keeps lazy plugins unloaded until the first open)
---@field renderer? Ui.ContextMenu.Renderer  # default "kit": no third-party menu plugin needed
---@field native_popup? boolean  # keep Neovim's own right-click popup (default false)
---@field sections? table<string, boolean>  # `code`, `clipboard`, `file`, `delete`, `tools`
---@field entries? table<string, boolean>  # per general entry, see DEFAULTS.entries
---@field hints? table<string, string>  # right-aligned text per general entry (a mapping to show), e.g. `{ save = "<C-s>" }`
---@field integrations? boolean|table<string, boolean>  # sister-plugin contributions: `false` = none, or per name (`{ lsp = false }`)
---@field contributors? Ui.Menu.ContributorSpec[]  # more `<plugin>.integrations.menu`-style modules
---@field extra? Ui.Menu.Extra[]  # your own rows, see `Ui.Menu.Extra`

---@type Ui.Menu.Opts
M.DEFAULTS = {
  mouse = true,
  key = false,
  prewarm = true,
  renderer = "kit",
  native_popup = false,
  sections = {
    code = true,
    clipboard = true,
    file = true,
    delete = true,
    tools = true,
  },
  entries = {
    format = true,
    code_actions = true,
    inspect = true,
    copy_all = true,
    copy_marked = true,
    paste = true,
    save = true,
    save_all = true,
    delete_marked = true,
    -- Destructive beyond the buffer / the selection: off until asked for.
    delete_all = false,
    delete_file = false,
    terminal = true,
    color_picker = true,
    unicode_table = true,
    git = true,
  },
  hints = {},
  integrations = true,
  contributors = {},
  extra = {},
}

---The config store: every `apply()` starts from a fresh copy of DEFAULTS. A
---list (`extra`, `contributors`) replaces the default one as a whole; an
---unknown key (a misspelt entry or section name included) or a value of the
---wrong type is reported and left out, so its default applies (`M.issues()`).
local store = require("ui.util.config").new("ui.menu", M.DEFAULTS, {
  schema = {
    key = "string|false",
    renderer = { "string", enum = { "auto", "kit", "nvzone" } },
    hints = { "table", of = "string" },
    integrations = "boolean|table",
  },
})

--- Merge `opts` over the defaults (replacing what a previous `setup` set).
---@param opts Ui.Menu.Opts|nil
---@return Ui.Menu.Opts
function M.apply(opts)
  store.setup(opts)
  return store.get()
end

--- The options in force. The live table: read it, never write to it.
---@return Ui.Menu.Opts
function M.get()
  return store.get()
end

--- What the last `apply()` ignored, one line each; empty when everything was
--- accepted.
---@return string[]
function M.issues()
  return store.issues()
end

return M
