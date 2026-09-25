---@module 'ui.menu.sections'
--- The general (non-plugin) part of the menu: Code, Clipboard, File, Delete,
--- Tools. Built per open, so entries that depend on state (a Visual selection,
--- a named file) are resolved at open time, and a section whose every entry is
--- off takes its heading down with it.

local contextmenu = require("ui.contextmenu")
local selection = require("ui.menu.selection")
local icons = require("ui.menu.icons")
local notify = require("lib.nvim.notify").create("[ui.menu]")

local M = {}

---@param name string
---@return boolean
local function installed(name)
  return package.loaded[name] ~= nil or pcall(require, name)
end

--- Format through conform.nvim when it is installed, else through the LSP.
local function format_buffer()
  local ok, conform = pcall(require, "conform")
  if ok then
    conform.format({ lsp_fallback = true })
  else
    pcall(vim.lsp.buf.format)
  end
end

local function inspect_here()
  -- A closure, not `pcall(vim.cmd, ...)`: `vim.cmd` is a callable table, which
  -- LuaLS rejects as a `pcall` argument.
  pcall(function()
    vim.cmd("Inspect")
  end)
end

---@param sel Ui.Menu.Selection|nil
local function copy_marked(sel)
  if selection.usable(sel) then
    ---@cast sel Ui.Menu.Selection
    local lines, regtype = selection.text(sel)
    vim.fn.setreg("+", lines, regtype)
    vim.fn.setreg('"', lines, regtype)
    notify.info("Copied selection to clipboard")
  else
    vim.cmd("%y+")
    notify.info("Copied entire buffer to clipboard")
  end
end

local function paste_clipboard()
  local ok, text = pcall(vim.fn.getreg, "+")
  if not ok or type(text) ~= "string" or text == "" then
    notify.info("System clipboard is empty")
    return
  end
  vim.api.nvim_put(vim.split(text, "\n", { plain = true }), "l", true, true)
end

--- Write the buffer, reporting instead of raising (unnamed, read-only, ...).
local function save_buffer()
  local ok, err = pcall(function()
    vim.cmd("write")
  end)
  if ok then
    notify.info("Saved " .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"))
  else
    notify.error("Could not save: " .. tostring(err))
  end
end

local function save_all()
  local ok, err = pcall(function()
    vim.cmd("silent! wall")
  end)
  if ok then
    notify.info("Saved all modified buffers")
  else
    notify.error("Could not save all: " .. tostring(err))
  end
end

---@param sel Ui.Menu.Selection|nil
local function delete_marked(sel)
  if selection.usable(sel) then
    ---@cast sel Ui.Menu.Selection
    selection.delete(sel)
    notify.info("Deleted selection")
  else
    notify.warn("No selection to delete")
  end
end

local function delete_all()
  require("ui.kit").confirm({
    question = "Delete all content in buffer?",
    on_answer = function(yes)
      if yes then
        vim.cmd("%d")
        notify.info("Buffer cleared")
      end
    end,
  })
end

local function delete_file()
  local filepath = vim.api.nvim_buf_get_name(0)
  if filepath == "" then
    notify.warn("Buffer has no associated file")
    return
  end
  local filename = vim.fn.fnamemodify(filepath, ":t")
  require("ui.kit").confirm({
    question = string.format('Delete file "%s"?', filename),
    on_answer = function(yes)
      if not yes then
        return
      end
      if vim.fn.delete(filepath) == 0 then
        vim.cmd("bdelete!")
        notify.info("File deleted: " .. filename)
      else
        notify.error("Failed to delete file: " .. filename)
      end
    end,
  })
end

--- A terminal in the current file's directory. `cwd` is passed to `jobstart`
--- rather than interpolated into a `cd <dir>; $SHELL` string: the directory
--- comes from a buffer name, and a path may contain shell metacharacters.
local function open_terminal()
  local bufname = vim.api.nvim_buf_get_name(0)
  local cwd = vim.uv.cwd() or "."
  local dir = bufname ~= "" and vim.fn.fnamemodify(bufname, ":h") or cwd
  if vim.fn.isdirectory(dir) == 0 then
    dir = cwd
  end
  vim.cmd("enew")
  local ok, job = pcall(vim.fn.jobstart, vim.o.shell, { term = true, cwd = dir })
  if not ok or type(job) ~= "number" or job <= 0 then
    -- `bwipeout`, not `bdelete`: the latter leaves the empty buffer listed.
    pcall(function()
      vim.cmd("bwipeout!")
    end)
    notify.error("could not open a terminal in " .. dir .. ": " .. tostring(job))
  end
end

local function open_color_picker()
  local ok, picker = pcall(require, "ui.colorpicker")
  if ok and picker and picker.open then
    pcall(picker.open)
  end
end

local function open_unicode_table()
  local ok, unicode = pcall(require, "emojis.unicode")
  if not ok then
    notify.warn("emojis.nvim not available")
    return
  end
  unicode.table_open()
end

--- Build the general sections for the current buffer/mode.
---@param cfg Ui.Menu.Opts
---@return Ui.ContextMenu.Item[]
function M.build(cfg)
  local out = {}
  local sec, on, hints = cfg.sections or {}, cfg.entries or {}, cfg.hints or {}
  -- Resolved now, while Visual mode (if any) is still live: the entries act
  -- on this snapshot, never on the mode at click time.
  local sel = selection.snapshot()

  ---@param key string
  ---@param label string
  ---@param fn function
  ---@param section string
  ---@return Ui.ContextMenu.Item|nil
  local function e(key, label, fn, section)
    if sec[section] == false then
      return nil
    end
    return contextmenu.entry(on[key], label, fn, hints[key], { icon = icons[key] })
  end

  contextmenu.group(
    out,
    contextmenu.heading("Code"),
    e("format", "Format Buffer", format_buffer, "code"),
    e("code_actions", "Code Actions", vim.lsp.buf.code_action, "code"),
    e("inspect", "Inspect", inspect_here, "code")
  )

  contextmenu.group(
    out,
    contextmenu.heading("Clipboard"),
    e("copy_all", "Copy All (Buffer)", function()
      vim.cmd("%y+")
    end, "clipboard"),
    e("copy_marked", "Copy Marked/Selected", function()
      copy_marked(sel)
    end, "clipboard"),
    e("paste", "Paste Content", paste_clipboard, "clipboard")
  )

  contextmenu.group(
    out,
    contextmenu.heading("File"),
    e("save", "Save", save_buffer, "file"),
    e("save_all", "Save All", save_all, "file")
  )

  contextmenu.group(
    out,
    contextmenu.heading("Delete"),
    e("delete_marked", "Delete Marked/Selected", function()
      delete_marked(sel)
    end, "delete"),
    e("delete_all", "Delete All (Clear Buffer)", delete_all, "delete"),
    e("delete_file", "Delete File", delete_file, "delete")
  )

  -- Git sits in Tools rather than in a section of its own: a named section
  -- holding a single entry is a frame around one row. Its items are
  -- gitsuite.nvim's own; absent or opted out (`integrations.git`) -> no row.
  local git_row
  if sec.tools ~= false and on.git and installed("gitsuite.integrations.menu") then
    local ok, git_menu = pcall(require, "gitsuite.integrations.menu")
    if ok and type(git_menu.items) == "function" then
      local ok_items, git_items = pcall(git_menu.items)
      if ok_items then
        git_row = contextmenu.submenu("Git Actions", git_items, { icon = icons.git })
      end
    end
  end

  contextmenu.group(
    out,
    contextmenu.heading("Tools"),
    e("terminal", "Open in terminal", open_terminal, "tools"),
    e("color_picker", "Color Picker", open_color_picker, "tools"),
    (sec.tools ~= false and on.unicode_table and installed("emojis.unicode"))
        and contextmenu.entry(true, "Unicode Table", open_unicode_table, hints.unicode_table, {
          icon = icons.unicode_table,
        })
      or nil,
    git_row
  )

  return out
end

return M
