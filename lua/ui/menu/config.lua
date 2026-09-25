---@module 'ui.menu.config'
--- Defaults and merging for `ui.menu`.

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

---@type Ui.Menu.Opts
local current = vim.deepcopy(M.DEFAULTS)

--- Merge `opts` over the defaults (replacing what a previous `setup` set).
---@param opts Ui.Menu.Opts|nil
---@return Ui.Menu.Opts
function M.apply(opts)
  current = vim.tbl_deep_extend("force", vim.deepcopy(M.DEFAULTS), opts or {})
  -- Lists are replaced, not merged index by index.
  if opts and opts.extra then
    current.extra = vim.deepcopy(opts.extra)
  end
  if opts and opts.contributors then
    current.contributors = vim.deepcopy(opts.contributors)
  end
  return current
end

---@return Ui.Menu.Opts
function M.get()
  return current
end

return M
