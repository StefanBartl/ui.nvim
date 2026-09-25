-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, duplicate-set-field

--- `ui.menu`: the right-click menu. Covers what the menu offers (defaults, the
--- per-entry and per-section switches, no heading over an empty section), the
--- three opt-out layers for sister-plugin contributions (installed, ui.nvim's
--- `integrations`, the plugin's own `enabled()`/nil `submenu()`), the user's
--- own `extra` rows (plugin/ft/when gates, grouping by section, `cmd`), the
--- selection that "Copy/Delete Marked" act on after Visual mode has ended, and
--- the `<RightMouse>` handler's three cases (bar, inside the selection, elsewhere).

local menu = require("ui.menu")
local contributors = require("ui.menu.contributors")
local selection = require("ui.menu.selection")
local contextmenu = require("ui.contextmenu")

--- The first item, at any depth, whose name contains `label`.
---@param list table[]
---@param label string
---@return table|nil
local function find(list, label)
  for _, it in ipairs(list) do
    if it.name and it.name:find(label, 1, true) and not it.__heading then
      return it
    end
    if it.items then
      local r = find(it.items, label)
      if r then
        return r
      end
    end
  end
end

---@param list table[]
---@param title string
---@return boolean
local function has_heading(list, title)
  for _, it in ipairs(list) do
    if it.__heading and it.name == title then
      return true
    end
  end
  return false
end

--- The rows under heading `title`, up to the next heading.
---@param list table[]
---@param title string
---@return string[]
local function rows_of(list, title)
  local out, inside = {}, false
  for _, it in ipairs(list) do
    if it.__heading then
      inside = it.name == title
    elseif inside then
      out[#out + 1] = it.name
    end
  end
  return out
end

--- Register a fake contributor module and return its name.
---@param modname string
---@param mod table
local function preload(modname, mod)
  package.preload[modname] = function()
    return mod
  end
  package.loaded[modname] = nil
end

describe("ui.menu", function()
  local buf

  before_each(function()
    contributors.reset_runtime()
    menu.setup({ mouse = false, key = false })
    buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].modified = false
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha beta", "gamma delta", "epsilon" })
    vim.fn.setreg("+", "")
  end)

  after_each(function()
    pcall(vim.cmd, "normal! \27")
    contributors.reset_runtime()
    for _, m in ipairs({ "uitest.a.menu", "uitest.b.menu", "uitest.c.menu" }) do
      package.preload[m] = nil
      package.loaded[m] = nil
    end
    menu.setup({ mouse = false, key = false })
  end)

  describe("what the general sections offer", function()
    it("has Code, Clipboard, File, Tools by default", function()
      local items = menu.items(buf)
      for _, h in ipairs({ "Code", "Clipboard", "File", "Tools" }) do
        assert.is_true(has_heading(items, h), h)
      end
      assert.is_not_nil(find(items, "Save"))
      assert.is_not_nil(find(items, "Save All"))
      assert.is_not_nil(find(items, "Copy Marked"))
    end)

    it("keeps the destructive entries off until asked for", function()
      local items = menu.items(buf)
      assert.is_nil(find(items, "Delete File"))
      assert.is_nil(find(items, "Delete All"))
      assert.is_not_nil(find(items, "Delete Marked"))

      menu.setup({ mouse = false, key = false, entries = { delete_all = true, delete_file = true } })
      items = menu.items(buf)
      assert.is_not_nil(find(items, "Delete File"))
      assert.is_not_nil(find(items, "Delete All"))
    end)

    it("a section switched off takes its heading with it", function()
      menu.setup({ mouse = false, key = false, sections = { file = false } })
      local items = menu.items(buf)
      assert.is_false(has_heading(items, "File"))
      assert.is_nil(find(items, "Save"))
    end)

    it("a section whose every entry is off shows no heading", function()
      menu.setup({
        mouse = false,
        key = false,
        entries = { delete_marked = false },
      })
      assert.is_false(has_heading(menu.items(buf), "Delete"))
    end)

    it("shows a hint next to an entry when one is configured", function()
      menu.setup({ mouse = false, key = false, hints = { save = "<C-s>" } })
      assert.equals("<C-s>", find(menu.items(buf), "Save").rtxt)
    end)
  end)

  describe("Copy / Delete Marked act on the selection, not on the mode at click time", function()
    ---@return table items
    local function built_in_visual(from, to, mode)
      vim.fn.setpos(".", { 0, from[1], from[2], 0 })
      vim.cmd("normal! " .. (mode or "v"))
      vim.fn.setpos(".", { 0, to[1], to[2], 0 })
      local items = menu.items(buf)
      -- Visual mode is over by the time a menu entry runs.
      vim.cmd("normal! \27")
      return items
    end

    it("copies the selection made before the menu opened", function()
      local items = built_in_visual({ 1, 7 }, { 2, 3 })
      find(items, "Copy Marked").cmd()
      assert.equals("beta\ngam", vim.fn.getreg("+"))
    end)

    it("copies a linewise selection as lines", function()
      local items = built_in_visual({ 1, 1 }, { 2, 1 }, "V")
      find(items, "Copy Marked").cmd()
      assert.equals("alpha beta\ngamma delta\n", vim.fn.getreg("+"))
    end)

    it("copies the whole buffer when nothing was selected", function()
      find(menu.items(buf), "Copy Marked").cmd()
      local text = vim.fn.getreg("+")
      assert.is_truthy(text:find("alpha", 1, true))
      assert.is_truthy(text:find("epsilon", 1, true))
    end)

    it("deletes only the selection", function()
      local items = built_in_visual({ 1, 1 }, { 1, 6 })
      find(items, "Delete Marked").cmd()
      assert.equals("beta", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
      assert.equals(3, vim.api.nvim_buf_line_count(buf))
    end)

    it("deletes nothing without a selection", function()
      find(menu.items(buf), "Delete Marked").cmd()
      assert.equals(3, vim.api.nvim_buf_line_count(buf))
      assert.equals("alpha beta", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
    end)

    it("ignores a selection that belongs to another buffer", function()
      local items = built_in_visual({ 1, 7 }, { 2, 3 })
      vim.cmd("enew")
      local other = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(other, 0, -1, false, { "other" })
      find(items, "Copy Marked").cmd()
      assert.is_truthy(vim.fn.getreg("+"):find("other", 1, true))
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_delete(other, { force = true })
    end)
  end)

  describe("Save", function()
    it("writes a named buffer", function()
      local path = vim.fn.tempname()
      vim.cmd("file " .. vim.fn.fnameescape(path))
      find(menu.items(buf), "Save").cmd()
      assert.equals(1, vim.fn.filereadable(path))
      vim.fn.delete(path)
    end)

    it("reports an unnamed buffer instead of raising", function()
      vim.cmd("enew")
      local unnamed = vim.api.nvim_get_current_buf()
      local it = find(menu.items(unnamed), "Save")
      assert.has_no.errors(function()
        it.cmd()
      end)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_buf_delete(unnamed, { force = true })
    end)
  end)

  describe("sister-plugin contributions: three opt-out layers", function()
    local function contributor(name, module, extra)
      return vim.tbl_extend("force", { name = name, module = module }, extra or {})
    end

    it("shows a fly-out for an installed plugin", function()
      preload("uitest.a.menu", {
        submenu = function()
          return { name = "Plugin A", items = { { name = "Do A", cmd = function() end } } }
        end,
      })
      menu.setup({
        mouse = false,
        key = false,
        contributors = { contributor("uitest_a", "uitest.a.menu") },
      })
      local items = menu.items(buf)
      assert.is_true(has_heading(items, "Integrations"))
      assert.is_not_nil(find(items, "Plugin A"))
      assert.is_not_nil(
        find(items, "Plugin A").icon,
        "a contributor without an icon gets a fallback"
      )
    end)

    it("layer 1: a plugin that is not installed is skipped without a word", function()
      menu.setup({
        mouse = false,
        key = false,
        contributors = { contributor("uitest_missing", "uitest.not.installed.menu") },
      })
      local items
      assert.has_no.errors(function()
        items = menu.items(buf)
      end)
      assert.is_false(has_heading(items, "Integrations"))
    end)

    it("layer 2: integrations.<name> = false hides it, integrations = false hides all", function()
      preload("uitest.a.menu", {
        submenu = function()
          return { name = "Plugin A", items = { { name = "x", cmd = function() end } } }
        end,
      })
      local spec = { contributor("uitest_a", "uitest.a.menu") }
      menu.setup({
        mouse = false,
        key = false,
        contributors = spec,
        integrations = { uitest_a = false },
      })
      assert.is_nil(find(menu.items(buf), "Plugin A"))

      menu.setup({ mouse = false, key = false, contributors = spec, integrations = false })
      assert.is_nil(find(menu.items(buf), "Plugin A"))

      -- Naming another plugin leaves this one on.
      menu.setup({
        mouse = false,
        key = false,
        contributors = spec,
        integrations = { something_else = false },
      })
      assert.is_not_nil(find(menu.items(buf), "Plugin A"))
    end)

    it("layer 3: the plugin opts out with enabled() == false", function()
      preload("uitest.b.menu", {
        enabled = function()
          return false
        end,
        submenu = function()
          return { name = "Plugin B", items = { { name = "x", cmd = function() end } } }
        end,
      })
      menu.setup({
        mouse = false,
        key = false,
        contributors = { contributor("uitest_b", "uitest.b.menu") },
      })
      assert.is_nil(find(menu.items(buf), "Plugin B"))
    end)

    it("layer 3: the plugin opts out by returning no submenu", function()
      preload("uitest.c.menu", {
        submenu = function()
          return nil
        end,
      })
      menu.setup({
        mouse = false,
        key = false,
        contributors = { contributor("uitest_c", "uitest.c.menu") },
      })
      assert.is_false(has_heading(menu.items(buf), "Integrations"))
    end)

    it("a plugin that raises does not take the menu down", function()
      preload("uitest.a.menu", {
        submenu = function()
          error("boom")
        end,
      })
      menu.setup({
        mouse = false,
        key = false,
        contributors = { contributor("uitest_a", "uitest.a.menu") },
      })
      local items
      assert.has_no.errors(function()
        items = menu.items(buf)
      end)
      assert.is_not_nil(find(items, "Save"))
    end)

    it("ft limits a contributor to those filetypes", function()
      preload("uitest.a.menu", {
        submenu = function()
          return { name = "Plugin A", items = { { name = "x", cmd = function() end } } }
        end,
      })
      menu.setup({
        mouse = false,
        key = false,
        contributors = { contributor("uitest_a", "uitest.a.menu", { ft = "lua" }) },
      })
      vim.bo[buf].filetype = "text"
      assert.is_nil(find(menu.items(buf), "Plugin A"))
      vim.bo[buf].filetype = "lua"
      assert.is_not_nil(find(menu.items(buf), "Plugin A"))
    end)

    it("register_contributor adds one at runtime", function()
      preload("uitest.a.menu", {
        submenu = function()
          return { name = "Plugin A", items = { { name = "x", cmd = function() end } } }
        end,
      })
      menu.register_contributor({ name = "uitest_a", module = "uitest.a.menu" })
      assert.is_not_nil(find(menu.items(buf), "Plugin A"))
      -- ...and survives a second setup().
      menu.setup({ mouse = false, key = false })
      assert.is_not_nil(find(menu.items(buf), "Plugin A"))
    end)
  end)

  describe("your own rows (extra)", function()
    it("shows a row under its own section heading", function()
      menu.setup({
        mouse = false,
        key = false,
        extra = { { label = "Do it", cmd = function() end, section = "Mine" } },
      })
      assert.same({ "Do it" }, rows_of(menu.items(buf), "Mine"))
    end)

    it("groups rows that share a section name under one heading", function()
      menu.setup({
        mouse = false,
        key = false,
        extra = {
          { label = "One", cmd = function() end, section = "Mine" },
          { label = "Other", cmd = function() end, section = "Else" },
          { label = "Two", cmd = function() end, section = "Mine" },
        },
      })
      local items = menu.items(buf)
      assert.same({ "One", "Two" }, rows_of(items, "Mine"))
      assert.same({ "Other" }, rows_of(items, "Else"))
    end)

    it("defaults the section to Custom", function()
      menu.setup({ mouse = false, key = false, extra = { { label = "X", cmd = function() end } } })
      assert.same({ "X" }, rows_of(menu.items(buf), "Custom"))
    end)

    it("plugin = ... hides the row while that plugin is not installed", function()
      preload("uitest.a.menu", {})
      menu.setup({
        mouse = false,
        key = false,
        extra = {
          { label = "Needs A", cmd = function() end, plugin = "uitest.a.menu" },
          { label = "Needs missing", cmd = function() end, plugin = "uitest.not.installed" },
          {
            label = "Needs both",
            cmd = function() end,
            plugin = { "uitest.a.menu", "uitest.nope" },
          },
        },
      })
      local items = menu.items(buf)
      assert.is_not_nil(find(items, "Needs A"))
      assert.is_nil(find(items, "Needs missing"))
      assert.is_nil(find(items, "Needs both"))
    end)

    it("ft, when and enabled gate a row", function()
      menu.setup({
        mouse = false,
        key = false,
        extra = {
          { label = "Lua only", cmd = function() end, ft = "lua" },
          {
            label = "Never",
            cmd = function() end,
            when = function()
              return false
            end,
          },
          { label = "Off", cmd = function() end, enabled = false },
        },
      })
      vim.bo[buf].filetype = "text"
      local items = menu.items(buf)
      assert.is_nil(find(items, "Lua only"))
      assert.is_nil(find(items, "Never"))
      assert.is_nil(find(items, "Off"))
      vim.bo[buf].filetype = "lua"
      assert.is_not_nil(find(menu.items(buf), "Lua only"))
    end)

    it("runs an Ex command string", function()
      menu.setup({
        mouse = false,
        key = false,
        extra = { { label = "Set var", cmd = "let g:ui_menu_spec = 42" } },
      })
      find(menu.items(buf), "Set var").cmd()
      assert.equals(42, vim.g.ui_menu_spec)
      vim.g.ui_menu_spec = nil
    end)

    it("reports a failing Ex command instead of raising", function()
      menu.setup({
        mouse = false,
        key = false,
        extra = { { label = "Bad", cmd = "NoSuchCommandAnywhere" } },
      })
      assert.has_no.errors(function()
        find(menu.items(buf), "Bad").cmd()
      end)
    end)

    it("keys = ... feeds the mapping", function()
      vim.keymap.set("n", "<Plug>(ui-menu-spec)", function()
        vim.g.ui_menu_spec_keys = true
      end)
      menu.setup({
        mouse = false,
        key = false,
        extra = { { label = "Keys", keys = "<Plug>(ui-menu-spec)" } },
      })
      find(menu.items(buf), "Keys").cmd()
      vim.api.nvim_feedkeys("", "x", false)
      assert.is_true(vim.g.ui_menu_spec_keys)
      vim.g.ui_menu_spec_keys = nil
    end)

    it("a row without cmd or keys is dropped", function()
      menu.setup({ mouse = false, key = false, extra = { { label = "Nothing" } } })
      assert.is_nil(find(menu.items(buf), "Nothing"))
    end)

    it("add() appends at runtime", function()
      menu.add({ label = "Runtime", cmd = function() end, section = "Now" })
      assert.same({ "Runtime" }, rows_of(menu.items(buf), "Now"))
    end)
  end)

  describe("triggers", function()
    local function mapped(lhs)
      local m = vim.fn.maparg(lhs, "n", false, true)
      return type(m) == "table" and m.desc ~= nil and m.desc:find("ui.menu", 1, true) ~= nil
    end

    it("binds <RightMouse> and the cursor key, and nothing else, by default", function()
      menu.setup({})
      assert.is_true(mapped("<RightMouse>"))
      assert.is_true(mapped("<A-b>"))
    end)

    it("mouse = false / key = false bind nothing", function()
      pcall(vim.keymap.del, "n", "<RightMouse>")
      pcall(vim.keymap.del, "n", "<A-b>")
      menu.setup({ mouse = false, key = false })
      assert.is_false(mapped("<RightMouse>"))
      assert.is_false(mapped("<A-b>"))
    end)

    it("a second setup replaces the bindings instead of piling up", function()
      menu.setup({ key = "<A-m>" })
      menu.setup({ key = "<A-n>" })
      assert.is_false(mapped("<A-m>"))
      assert.is_true(mapped("<A-n>"))
    end)

    it("ui.setup({ menu = { ... } }) configures and binds it; menu = true does not", function()
      pcall(vim.keymap.del, "n", "<RightMouse>")
      pcall(vim.keymap.del, "n", "<A-b>")
      require("ui").setup({ menu = true })
      assert.is_false(mapped("<RightMouse>"))
      require("ui").setup({ menu = { key = false, integrations = false } })
      assert.is_true(mapped("<RightMouse>"))
      assert.is_false(menu.config().integrations)
    end)
  end)

  describe("the <RightMouse> handler", function()
    local opened, real_open

    before_each(function()
      opened = {}
      real_open = contextmenu.open
      contextmenu.open = function(items, opts)
        opened[#opened + 1] = { mode = vim.fn.mode(), mouse = opts and opts.mouse, n = #items }
      end
    end)

    after_each(function()
      contextmenu.open = real_open
      package.loaded["ui.tabline.menu"] = nil
      package.loaded["ui.statusline.menu"] = nil
    end)

    it("opens nothing on a tab-bar click: the bar's own handler answers it", function()
      package.loaded["ui.tabline.menu"] = {
        pointer_on_tabline = function()
          return true
        end,
      }
      menu.on_right_click()
      assert.equals(0, #opened)
    end)

    it("opens nothing on a statusline module click", function()
      package.loaded["ui.tabline.menu"] = {
        pointer_on_tabline = function()
          return false
        end,
      }
      package.loaded["ui.statusline.menu"] = {
        pointer_on_statusline = function()
          return true
        end,
      }
      menu.on_right_click()
      assert.equals(0, #opened)
    end)

    it("keeps a Visual selection the pointer is inside of", function()
      package.loaded["ui.tabline.menu"] = {
        pointer_on_tabline = function()
          return false
        end,
      }
      package.loaded["ui.statusline.menu"] = {
        pointer_on_statusline = function()
          return false
        end,
      }
      local real = selection.pointer_inside
      selection.pointer_inside = function()
        return true
      end
      vim.fn.setpos(".", { 0, 1, 1, 0 })
      vim.cmd("normal! V")
      menu.on_right_click()
      selection.pointer_inside = real
      assert.equals(1, #opened)
      assert.equals("V", opened[1].mode)
      assert.is_true(opened[1].mouse)
    end)
  end)

  describe("selection.pointer_inside", function()
    local real

    before_each(function()
      real = vim.fn.getmousepos
    end)

    after_each(function()
      vim.fn.getmousepos = real
    end)

    ---@param line integer
    ---@param column integer
    local function pointer_at(line, column)
      vim.fn.getmousepos = function()
        return { winid = vim.api.nvim_get_current_win(), line = line, column = column }
      end
    end

    it("is false outside Visual mode", function()
      pointer_at(1, 1)
      assert.is_false(selection.pointer_inside())
    end)

    it("is true on a line inside a multi-line selection, false outside it", function()
      vim.fn.setpos(".", { 0, 1, 1, 0 })
      vim.cmd("normal! Vj")
      pointer_at(2, 5)
      assert.is_true(selection.pointer_inside())
      pointer_at(3, 5)
      assert.is_false(selection.pointer_inside())
    end)

    it("checks the columns of a single-line charwise selection", function()
      vim.fn.setpos(".", { 0, 1, 3, 0 })
      vim.cmd("normal! v")
      vim.fn.setpos(".", { 0, 1, 6, 0 })
      pointer_at(1, 4)
      assert.is_true(selection.pointer_inside())
      pointer_at(1, 9)
      assert.is_false(selection.pointer_inside())
    end)

    it("is false for a pointer over another window", function()
      vim.fn.setpos(".", { 0, 1, 1, 0 })
      vim.cmd("normal! V")
      vim.fn.getmousepos = function()
        return { winid = -1, line = 1, column = 1 }
      end
      assert.is_false(selection.pointer_inside())
    end)
  end)
end)
