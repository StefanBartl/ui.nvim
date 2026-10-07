-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- The slot bar in a real, UI-attached Neovim.
---
--- `slots_bar_spec.lua` calls the bar's key listener with a stubbed
--- `getmousepos()`, because this runner has no UI and so no mouse input. That
--- cannot show what a person meets: that a click really reaches the listener,
--- that the focus the click moved into the bar is really given back, that the
--- wheel really scrolls, that a click elsewhere is left alone, and that the
--- right click is answered by the bar and not by the general `ui.menu`. So this
--- file starts a child Neovim with `--embed`, attaches a UI so its main loop runs
--- for real, and sends real `nvim_input_mouse` events over RPC -- the way
--- `ui_kit_sheet_ui_spec.lua` does for the sheet.

---@type integer|nil
local chan

---@param rel string
---@return string
local function root_of(rel)
  local found =
    assert(vim.api.nvim_get_runtime_file(rel, false)[1], "not on the runtimepath: " .. rel)
  local dir = vim.fs.dirname(found)
  for _ = 1, select(2, rel:gsub("/", "/")) do
    dir = vim.fs.dirname(dir)
  end
  return dir
end

---@param code string
---@param args any[]|nil
---@return any
local function lua(code, args)
  return vim.rpcrequest(chan, "nvim_exec_lua", code, args or {})
end

--- Poll until `cond()` holds.
---@param cond fun(): boolean
---@param what string
local function expect(cond, what)
  assert.is_true(vim.wait(3000, cond, 20), what)
end

--- Where the bar is and what its lines are.
---@return table
local function bar()
  return lua([[
    local st = require("ui.slots.view.chips").state()
    local cfg = st.win and vim.api.nvim_win_get_config(st.win) or {}
    return {
      win = st.win, lines = st.lines, top_n = st.top_n,
      row = cfg.row, col = cfg.col, width = cfg.width, height = cfg.height,
      current_is_bar = st.win ~= nil and vim.api.nvim_get_current_win() == st.win,
      current = vim.api.nvim_get_current_win(),
      name = vim.api.nvim_buf_get_name(0),
    }
  ]])
end

--- Click line `line` (1-based) of the bar, in the middle of its width.
---@param button string  # "left" | "right"
---@param line integer
local function click(button, line)
  local b = bar()
  local row, col = b.row + line - 1, b.col + math.floor(b.width / 2)
  vim.rpcrequest(chan, "nvim_input_mouse", button, "press", "", 0, row, col)
  vim.rpcrequest(chan, "nvim_input_mouse", button, "release", "", 0, row, col)
end

---@param direction string  # "up" | "down"
---@param line integer
local function wheel(direction, line)
  local b = bar()
  vim.rpcrequest(
    chan,
    "nvim_input_mouse",
    "wheel",
    direction,
    "",
    0,
    b.row + line - 1,
    b.col + math.floor(b.width / 2)
  )
end

describe("the slot bar in a real Neovim", function()
  local dir, file

  --- Child with the bar open and `extra` slots after the two fixed ones.
  ---@param extra integer
  local function open_bar(extra)
    lua(
      [[
      local file, data, extra = ...
      local slots = require("ui.slots")
      -- the right-click menu is bound, as in a real setup: the bar must win
      require("ui").setup({ menu = {} })
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "code one", "code two", "code three" })
      slots.setup({
        data_dir = data, persist = false, show = true, clipboard = { "a" },
        slots = {
          [1] = { kind = "file", path = file },
          [2] = { kind = "yank", text = "from the bar" },
        },
      })
      slots.enable()
      for i = 1, extra do
        slots.add({ kind = "yank", text = "extra " .. i })
      end
      -- a slot just added is kept in sight; start from the top
      require("ui.slots.view.chips").set_focus(1)
      -- what the right click should reach, instead of the general menu
      _G.RIGHT = { select = 0, menu = 0 }
      local select = require("ui.kit.select")
      local original = select.open
      select.open = function(opts) _G.RIGHT.select = _G.RIGHT.select + 1; _G.RIGHT.title = opts.title end
      local menu = require("ui.menu")
      local original_menu = menu.open
      menu.open = function(...) _G.RIGHT.menu = _G.RIGHT.menu + 1 end
      _G.MAIN = vim.api.nvim_get_current_win()
    ]],
      { file, dir .. "/data", extra }
    )
    expect(function()
      return bar().win ~= nil
    end, "the bar opens")
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    file = dir .. "/a.txt"
    vim.fn.writefile({ "one", "two" }, file)
    chan = vim.fn.jobstart({
      vim.v.progpath,
      "--embed",
      "-n",
      "-i",
      "NONE",
      "-u",
      "NONE",
      "--cmd",
      "set mouse=a",
    }, { rpc = true })
    assert.is_true(chan > 0, "the child Neovim did not start")
    vim.rpcrequest(chan, "nvim_ui_attach", 100, 30, { rgb = true })
    vim.rpcrequest(
      chan,
      "nvim_exec_lua",
      [[
        local lib, ui = ...
        vim.opt.rtp:prepend(lib)
        vim.opt.rtp:prepend(ui)
      ]],
      { root_of("lua/lib/nvim/init.lua"), root_of("lua/ui/kit/init.lua") }
    )
  end)

  after_each(function()
    if chan then
      pcall(vim.fn.jobstop, chan)
      chan = nil
    end
    vim.fn.delete(dir, "rf")
  end)

  it("opens at the right edge with a chip per slot", function()
    open_bar(0)
    local b = bar()
    assert.equals(6, #b.lines)
    assert.equals(100 - b.width, b.col)
    assert.is_truthy(b.lines[2]:find("a.txt", 1, true))
    assert.is_truthy(b.lines[5]:find("from the bar", 1, true))
  end)

  it("a real left click applies the slot, and the focus stays in the editor", function()
    open_bar(0)
    local before = bar()
    click("left", 5) -- the yank chip
    expect(function()
      return lua([[return vim.fn.getreg("a")]]) == "from the bar"
    end, "the yank slot copied its text")
    local after = bar()
    assert.is_false(after.current_is_bar, "the focus went back")
    assert.equals(before.current, after.current)
  end)

  it("a real left click on the file chip opens the file in the editor window", function()
    open_bar(0)
    click("left", 2)
    expect(function()
      return bar().name:find("a.txt", 1, true) ~= nil
    end, "the file opened")
    assert.is_false(bar().current_is_bar)
  end)

  it("a click on the border row of a chip counts as that chip", function()
    open_bar(0)
    click("left", 4) -- the top border of the second chip
    expect(function()
      return lua([[return vim.fn.getreg("a")]]) == "from the bar"
    end, "the border row hits the chip")
  end)

  it("leaves a click in the editor to the editor", function()
    open_bar(0)
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "press", "", 0, 1, 6)
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "release", "", 0, 1, 6)
    expect(function()
      return lua([[return vim.api.nvim_win_get_cursor(0)[1] ]]) == 2
    end, "the cursor went to the clicked line")
    assert.equals(0, lua([[return _G.RIGHT.select]]))
    assert.equals("", lua([[return vim.fn.getreg("a")]]))
  end)

  it("the wheel over the bar scrolls it, and over the editor it does not", function()
    open_bar(10) -- 12 slots: more than the 28 rows hold
    local b = bar()
    assert.is_truthy(b.lines[#b.lines]:find("▼", 1, true))
    assert.equals(1, b.top_n)
    wheel("down", 2)
    expect(function()
      return bar().top_n == 2
    end, "the bar scrolled one slot")
    wheel("up", 2)
    expect(function()
      return bar().top_n == 1
    end, "and back")
    vim.rpcrequest(chan, "nvim_input_mouse", "wheel", "down", "", 0, 5, 10)
    vim.wait(150)
    assert.equals(1, bar().top_n, "the wheel over the editor leaves the bar alone")
  end)

  it("a click on the counter row scrolls by one", function()
    open_bar(10)
    local b = bar()
    click("left", #b.lines)
    expect(function()
      return bar().top_n == 2
    end, "the counter row scrolled the bar")
  end)

  it("a real right click is answered by the bar and not by the general menu", function()
    open_bar(0)
    click("right", 5)
    expect(function()
      return lua([[return _G.RIGHT.select]]) == 1
    end, "the slot menu of the bar opened")
    assert.equals("slot 2", lua([[return _G.RIGHT.title]]))
    assert.equals(0, lua([[return _G.RIGHT.menu]]), "ui.menu stayed out of it")
    assert.is_false(bar().current_is_bar)
  end)

  it("a right click in the editor still reaches the general menu", function()
    open_bar(0)
    vim.rpcrequest(chan, "nvim_input_mouse", "right", "press", "", 0, 2, 6)
    vim.rpcrequest(chan, "nvim_input_mouse", "right", "release", "", 0, 2, 6)
    expect(function()
      return lua([[return _G.RIGHT.menu]]) == 1
    end, "ui.menu answered a right click on the code")
    assert.equals(0, lua([[return _G.RIGHT.select]]))
  end)

  it("takes the bar away again, leaving nothing behind", function()
    open_bar(0)
    lua([[require("ui.slots").disable()]])
    expect(function()
      return bar().win == nil
    end, "the bar is gone")
    assert.equals(1, lua([[return #vim.api.nvim_tabpage_list_wins(0)]]))
  end)
end)
