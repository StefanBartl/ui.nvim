-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, duplicate-set-field

--- `ui.tabline.menu` -- the right-click menu of a buffer chip -- and the
--- button dispatch in `ui.tabline.utils` that reaches it: left switches (and
--- arms a drag), right opens the menu, middle closes.

local state = require("ui.bindings.keymaps.tabufline.state")
local utils = require("ui.tabline.utils")
local menu = require("ui.tabline.menu")
local render = require("ui.tabline.render")
local drag = require("ui.tabline.drag")
local reopen = require("ui.tabline.reopen")

--- A named, listed buffer, made current -- which is what feeds `vim.t.bufs`.
---@param name string
---@return integer
local function open_named_buffer(name)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

--- Flatten a menu into its selectable labels: nested entries included,
--- separators and headings left out.
---@param items table[]
---@return string[]
local function labels(items)
  local out = {}
  local function walk(list)
    for _, item in ipairs(list) do
      if item.items then
        out[#out + 1] = item.name
        walk(item.items)
      elseif item.name ~= "separator" and not item.__heading then
        out[#out + 1] = item.name
      end
    end
  end
  walk(items)
  return out
end

---@param items table[]
---@param name string
---@return table|nil
local function find(items, name)
  for _, item in ipairs(items) do
    if item.name == name then
      return item
    end
    if item.items then
      local hit = find(item.items, name)
      if hit then
        return hit
      end
    end
  end
  return nil
end

local function has(items, name)
  return find(items, name) ~= nil
end

describe("ui.tabline.menu.items", function()
  local a, b, c

  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    a = open_named_buffer("tabline-menu-spec-a.txt")
    b = open_named_buffer("tabline-menu-spec-b.txt")
    c = open_named_buffer("tabline-menu-spec-c.txt")
    vim.t.bufs = { a, b, c }
  end)

  after_each(function()
    for _, buf in ipairs({ a, b, c }) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    pcall(vim.cmd, "tabclose")
  end)

  it("offers close, move and buffer actions for a middle tab", function()
    local items = menu.items(b)
    for _, name in ipairs({
      "Close",
      "Close others",
      "Close to the left",
      "Close to the right",
      "Move to position…",
      "Move left",
      "Move right",
      "Move to start",
      "Move to end",
      "Copy path",
      "Open in split",
      "Open in vertical split",
      "Move to new tab page",
    }) do
      assert.is_true(has(items, name), name)
    end
  end)

  it("does not offer moving or closing leftwards on the first tab", function()
    local items = menu.items(a)
    assert.is_false(has(items, "Close to the left"))
    assert.is_false(has(items, "Move left"))
    assert.is_false(has(items, "Move to start"))
    assert.is_true(has(items, "Close to the right"))
    assert.is_true(has(items, "Move right"))
  end)

  it("does not offer moving or closing rightwards on the last tab", function()
    local items = menu.items(c)
    assert.is_false(has(items, "Close to the right"))
    assert.is_false(has(items, "Move right"))
    assert.is_false(has(items, "Move to end"))
    assert.is_true(has(items, "Close to the left"))
    assert.is_true(has(items, "Move left"))
  end)

  it("drops the actions that need a neighbour when there is only one tab", function()
    vim.t.bufs = { b }
    local items = menu.items(b)
    assert.is_true(has(items, "Close"))
    assert.is_false(has(items, "Close others"))
    assert.is_false(has(items, "Move to position…"))
    assert.is_false(has(items, "Move to new tab page"))
  end)

  it("offers Save only on a modified tab", function()
    assert.is_false(has(menu.items(b), "Save"))
    vim.bo[b].modified = true
    assert.is_true(has(menu.items(b), "Save"))
    vim.bo[b].modified = false
  end)

  it("offers Close saved only when saved and unsaved tabs are both present", function()
    assert.is_false(has(menu.items(b), "Close saved"))
    vim.bo[c].modified = true
    assert.is_true(has(menu.items(b), "Close saved"))
    vim.bo[a].modified = true
    vim.bo[b].modified = true
    assert.is_false(has(menu.items(b), "Close saved")) -- nothing saved left to close
    vim.bo[a].modified = false
    vim.bo[b].modified = false
    vim.bo[c].modified = false
  end)

  it("titles the menu with the tab's own file name", function()
    local first = menu.items(b)[1]
    assert.is_true(first.__heading)
    assert.equals("tabline-menu-spec-b.txt", first.name)
  end)

  it("nests the path copies under one entry", function()
    local copy = find(menu.items(b), "Copy path")
    assert.is_table(copy.items)
    assert.same({ "Absolute path", "Relative path", "File name" }, labels(copy.items))
  end)

  describe("entries act on the clicked tab, not the current one", function()
    it("Move to end", function()
      vim.api.nvim_set_current_buf(c)
      find(menu.items(a), "Move to end").cmd()
      assert.same({ b, c, a }, vim.t.bufs)
      assert.equals(c, vim.api.nvim_get_current_buf())
    end)

    it("Move left / Move right / Move to start", function()
      find(menu.items(b), "Move left").cmd()
      assert.same({ b, a, c }, vim.t.bufs)
      find(menu.items(b), "Move right").cmd()
      assert.same({ a, b, c }, vim.t.bufs)
      find(menu.items(c), "Move to start").cmd()
      assert.same({ c, a, b }, vim.t.bufs)
    end)

    it("Close others keeps the clicked tab and lands on it", function()
      vim.api.nvim_set_current_buf(c)
      find(menu.items(b), "Close others").cmd()

      vim.wait(1000, function()
        return not vim.api.nvim_buf_is_loaded(a) and not vim.api.nvim_buf_is_loaded(c)
      end)

      assert.is_false(vim.api.nvim_buf_is_loaded(a))
      assert.is_false(vim.api.nvim_buf_is_loaded(c))
      assert.is_true(vim.api.nvim_buf_is_loaded(b))
      assert.equals(b, vim.api.nvim_get_current_buf())
    end)

    it("Close to the right closes only what is right of the clicked tab", function()
      find(menu.items(a), "Close to the right").cmd()

      vim.wait(1000, function()
        return not vim.api.nvim_buf_is_loaded(b) and not vim.api.nvim_buf_is_loaded(c)
      end)

      assert.is_true(vim.api.nvim_buf_is_loaded(a))
      assert.is_false(vim.api.nvim_buf_is_loaded(b))
      assert.is_false(vim.api.nvim_buf_is_loaded(c))
    end)

    it("Close to the left closes only what is left of the clicked tab", function()
      find(menu.items(c), "Close to the left").cmd()

      vim.wait(1000, function()
        return not vim.api.nvim_buf_is_loaded(a) and not vim.api.nvim_buf_is_loaded(b)
      end)

      assert.is_false(vim.api.nvim_buf_is_loaded(a))
      assert.is_false(vim.api.nvim_buf_is_loaded(b))
      assert.is_true(vim.api.nvim_buf_is_loaded(c))
    end)

    it("Close on a background tab does not move the current window", function()
      vim.api.nvim_set_current_buf(c)
      find(menu.items(a), "Close").cmd()

      vim.wait(1000, function()
        return not vim.api.nvim_buf_is_loaded(a)
      end)

      assert.is_false(vim.api.nvim_buf_is_loaded(a))
      assert.equals(c, vim.api.nvim_get_current_buf())
    end)
  end)

  describe("Move to position…", function()
    local real_input = require("ui.kit").input
    local submit

    before_each(function()
      require("ui.kit").input = function(opts)
        submit = opts.on_submit
        return nil
      end
      find(menu.items(a), "Move to position…").cmd()
    end)

    after_each(function()
      require("ui.kit").input = real_input
    end)

    it("moves to an absolute slot", function()
      submit("3")
      assert.same({ b, c, a }, vim.t.bufs)
    end)

    it("moves relative to where the tab is with a sign", function()
      submit("+1")
      assert.same({ b, a, c }, vim.t.bufs)
      submit("-1")
      assert.same({ a, b, c }, vim.t.bufs)
    end)

    it("clamps a slot past the end", function()
      submit("99")
      assert.same({ b, c, a }, vim.t.bufs)
    end)

    it("refuses a non-number and leaves the order alone", function()
      submit("two")
      submit("")
      submit("1.5")
      assert.same({ a, b, c }, vim.t.bufs)
    end)

    it("starts on the tab's current position", function()
      local seen
      require("ui.kit").input = function(opts)
        seen = opts.default
      end
      find(menu.items(c), "Move to position…").cmd()
      assert.equals("3", seen)
    end)
  end)

  describe("pins", function()
    it("offers 'Pin' on an unpinned tab, 'Unpin' on a pinned one", function()
      assert.is_true(has(menu.items(b), "Pin"))
      assert.is_false(has(menu.items(b), "Unpin"))

      state.set_pinned(b, true)
      assert.is_false(has(menu.items(b), "Pin"))
      assert.is_true(has(menu.items(b), "Unpin"))
    end)

    it("the 'Pin'/'Unpin' entry toggles the clicked tab's pin state", function()
      find(menu.items(b), "Pin").cmd()
      assert.is_true(state.is_pinned(b))
      find(menu.items(b), "Unpin").cmd()
      assert.is_false(state.is_pinned(b))
    end)

    it("Close others excludes a pinned tab from the set it closes", function()
      state.set_pinned(a, true)

      find(menu.items(b), "Close others").cmd()
      vim.wait(1000, function()
        return not vim.api.nvim_buf_is_loaded(c)
      end)
      assert.is_true(vim.api.nvim_buf_is_loaded(a)) -- pinned: survived "Close others"
      assert.is_false(vim.api.nvim_buf_is_loaded(c))
      assert.is_true(vim.api.nvim_buf_is_loaded(b))
      -- `c` deliberately not nilled out: the outer after_each's
      -- `ipairs({ a, b, c })` stops dead at the first nil hole -- see
      -- tabufline_state_spec.lua's own `wipe()` helper doc comment for why.
      -- Deleting an already-closed buffer there is a harmless pcall no-op.
    end)

    it("Close to the left drops a pinned tab from the slice it closes", function()
      state.set_pinned(b, true) -- pin block regroups b to the front: { b, a, c }
      -- "Close to the left" of c would otherwise be { b, a } -- b is excluded,
      -- but a alone still makes the entry worth offering.
      local entry = find(menu.items(c), "Close to the left")
      assert.is_table(entry, "entry should still be offered: a is left to close")
      entry.cmd()
      vim.wait(1000, function()
        return not vim.api.nvim_buf_is_loaded(a)
      end)
      assert.is_false(vim.api.nvim_buf_is_loaded(a))
      assert.is_true(vim.api.nvim_buf_is_loaded(b)) -- pinned: survived
    end)

    it("hides 'Close to the left' once the only tab to the left is pinned", function()
      state.set_pinned(a, true)
      assert.is_false(has(menu.items(b), "Close to the left"))
    end)

    it("hides 'Close others' once every other tab is pinned", function()
      state.set_pinned(a, true)
      state.set_pinned(c, true)
      assert.is_false(has(menu.items(b), "Close others"))
    end)
  end)

  describe("reopen closed tab", function()
    before_each(function()
      reopen.clear()
    end)

    after_each(function()
      reopen.clear()
    end)

    it("is absent from the menu while nothing has been closed", function()
      assert.is_false(has(menu.items(b), "Reopen closed tab"))
    end)

    it("lists a closed file once something has been recorded", function()
      local scratch_dir = vim.fn.stdpath("run") .. "/ui-tabline-menu-reopen-spec"
      vim.fn.mkdir(scratch_dir, "p")
      local path = scratch_dir .. "/reopen-me.txt"
      vim.fn.writefile({ "x" }, path)

      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      vim.bo[buf].buflisted = true
      vim.t.bufs = { a, b, c, buf }
      reopen.record(buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      vim.t.bufs = { a, b, c }

      local entry = find(menu.items(b), "Reopen closed tab")
      assert.is_table(entry)
      assert.is_table(entry.items)
      assert.equals(1, #entry.items)

      entry.items[1].cmd()
      assert.equals(path, vim.api.nvim_buf_get_name(0))
      assert.is_false(reopen.has_any())

      pcall(vim.api.nvim_buf_delete, 0, { force = true })
      pcall(vim.fn.delete, scratch_dir, "rf")
    end)
  end)
end)

describe("ui.tabline.menu.open", function()
  local a, b
  local contextmenu = require("ui.contextmenu")
  local real_open = contextmenu.open

  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    a = open_named_buffer("tabline-menu-open-a.txt")
    b = open_named_buffer("tabline-menu-open-b.txt")
    vim.t.bufs = { a, b }
  end)

  after_each(function()
    contextmenu.open = real_open
    for _, buf in ipairs({ a, b }) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    pcall(vim.cmd, "tabclose")
  end)

  it("opens the tab's items at the pointer and keeps the chip lit while it is up", function()
    local opened, opts_seen, on_close
    contextmenu.open = function(items, opts)
      opened, opts_seen = items, opts
      return {
        on_close = function(_, cb)
          on_close = cb
        end,
      }
    end

    menu.open(a)

    assert.is_table(opened)
    assert.is_true(has(opened, "Close"))
    assert.is_true(opts_seen.mouse)
    assert.is_true(utils.is_flashing(a))

    on_close()
    assert.is_false(utils.is_flashing(a))
  end)

  it("still releases the chip when the renderer has no close hook", function()
    contextmenu.open = function()
      return nil
    end
    menu.open(a)
    assert.is_true(utils.is_flashing(a))
    vim.wait(3000, function()
      return not utils.is_flashing(a)
    end)
    assert.is_false(utils.is_flashing(a))
  end)

  it("does nothing for a buffer that has gone away", function()
    local called = false
    contextmenu.open = function()
      called = true
    end
    local gone = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_delete(gone, { force = true })
    assert.has_no.errors(function()
      menu.open(gone)
    end)
    assert.is_false(called)
  end)
end)

describe("ui.tabline.menu.pointer_on_tabline", function()
  local real_getmousepos = vim.fn.getmousepos
  local real_showtabline = vim.o.showtabline

  after_each(function()
    vim.fn.getmousepos = real_getmousepos
    vim.o.showtabline = real_showtabline
  end)

  local function pointer_row(row)
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getmousepos = function()
      return { screenrow = row, screencol = 4 }
    end
  end

  it("is true for a click on the tab bar row", function()
    vim.o.showtabline = 2
    pointer_row(1)
    assert.is_true(menu.pointer_on_tabline())
  end)

  it("is false for a click in a window", function()
    vim.o.showtabline = 2
    pointer_row(7)
    assert.is_false(menu.pointer_on_tabline())
  end)

  it("is false when there is no tabline showing at all", function()
    vim.o.showtabline = 0
    pointer_row(1)
    assert.is_false(menu.pointer_on_tabline())
  end)
end)

describe("ui.tabline.utils click dispatch", function()
  local a, b
  local real_open = menu.open

  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    a = open_named_buffer("tabline-click-a.txt")
    b = open_named_buffer("tabline-click-b.txt")
    vim.t.bufs = { a, b }
    vim.api.nvim_set_current_buf(a)
    render.enable({ order = {}, modules = {} })
  end)

  after_each(function()
    menu.open = real_open
    drag.cancel()
    render.disable()
    for _, buf in ipairs({ a, b }) do
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    pcall(vim.cmd, "tabclose")
  end)

  it("a left click switches to the chip and arms a drag", function()
    utils.on_chip_click(b, "l")
    assert.equals(b, vim.api.nvim_get_current_buf())
    assert.is_true(drag.is_active())
    assert.equals(b, drag.dragged())
  end)

  it("a right click opens the tab menu without switching", function()
    local opened_for
    menu.open = function(bufnr)
      opened_for = bufnr
    end

    utils.on_chip_click(b, "r")
    vim.wait(500, function()
      return opened_for ~= nil
    end)

    assert.equals(b, opened_for)
    assert.equals(a, vim.api.nvim_get_current_buf())
    assert.is_false(drag.is_active())
  end)

  it("a middle click closes the chip", function()
    utils.on_chip_click(b, "m")
    vim.wait(1000, function()
      return not vim.api.nvim_buf_is_loaded(b)
    end)
    assert.is_false(vim.api.nvim_buf_is_loaded(b))
    assert.equals(a, vim.api.nvim_get_current_buf())
  end)

  it("a right click on the close button opens the menu instead of closing", function()
    local opened_for
    menu.open = function(bufnr)
      opened_for = bufnr
    end

    utils.on_close_click(b, "r")
    vim.wait(500, function()
      return opened_for ~= nil
    end)

    assert.equals(b, opened_for)
    assert.is_true(vim.api.nvim_buf_is_loaded(b))
  end)

  it("a left click on the close button closes", function()
    utils.on_close_click(b, "l")
    vim.wait(1000, function()
      return not vim.api.nvim_buf_is_loaded(b)
    end)
    assert.is_false(vim.api.nvim_buf_is_loaded(b))
  end)

  describe("opting out", function()
    it("context_menu = false turns a right click into a plain switch", function()
      render.enable({ order = {}, modules = {}, context_menu = false })
      local opened = false
      menu.open = function()
        opened = true
      end

      utils.on_chip_click(b, "r")
      vim.wait(100)

      assert.is_false(opened)
      assert.equals(b, vim.api.nvim_get_current_buf())
    end)

    it("drag = false switches without arming a drag", function()
      render.enable({ order = {}, modules = {}, drag = false })
      utils.on_chip_click(b, "l")
      assert.equals(b, vim.api.nvim_get_current_buf())
      assert.is_false(drag.is_active())
    end)

    it("middle_click_close = false turns a middle click into a plain switch", function()
      render.enable({ order = {}, modules = {}, middle_click_close = false })
      utils.on_chip_click(b, "m")
      vim.wait(200)
      assert.is_true(vim.api.nvim_buf_is_loaded(b))
      assert.equals(b, vim.api.nvim_get_current_buf())
    end)
  end)
end)

describe("ui.tabline.utils close latency", function()
  -- The close waits behind the click flash so the flash can reach the screen,
  -- but it must not wait the flash's whole length -- that read as a laggy "x".
  it("closes well inside the time a flash lasts", function()
    state.setup()
    local buf = vim.api.nvim_create_buf(true, false)
    local saved = vim.t.bufs
    vim.t.bufs = { buf }

    local start = vim.uv.hrtime()
    utils.close_buffer(buf)
    vim.wait(1000, function()
      return not vim.api.nvim_buf_is_loaded(buf)
    end)
    local elapsed_ms = (vim.uv.hrtime() - start) / 1e6

    assert.is_false(vim.api.nvim_buf_is_loaded(buf))
    -- Generous over the ~25ms delay (a loaded headless run is jittery), still
    -- clearly under the 120ms flash it used to wait out.
    assert.is_true(elapsed_ms < 110, ("close took %.0fms"):format(elapsed_ms))
    vim.t.bufs = saved
  end)
end)
