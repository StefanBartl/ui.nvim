-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- The slot panel and the editor in a real, UI-attached Neovim: real keys, a
--- real focus, real mouse events. `slots_panel_spec.lua` drives the same code
--- from callbacks; what only a running UI shows is that the keys reach the
--- panel, that the focus really goes in and comes back, that the sheet and the
--- chooser really open, and that a right click or a click in the code behaves.

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

---@param cond fun(): boolean
---@param what string
local function expect(cond, what)
  assert.is_true(vim.wait(3000, cond, 20), what)
end

---@param keys string
local function input(keys)
  vim.rpcrequest(chan, "nvim_input", keys)
end

--- Where we are.
---@return table
local function state()
  return lua([[
    local panel = require("ui.slots.view.panel")
    return {
      open = panel.is_open(),
      current = panel.current(),
      lines = panel.lines(),
      win = vim.api.nvim_get_current_win(),
      main = _G.MAIN,
      name = vim.api.nvim_buf_get_name(0),
      mode = vim.api.nvim_get_mode(),
      chooser = require("ui.kit.chooser").is_open(),
      reg = vim.fn.getreg("a"),
      slots = #require("ui.slots").list(),
      floats = #vim.tbl_filter(function(w)
        return vim.api.nvim_win_get_config(w).relative ~= ""
      end, vim.api.nvim_list_wins()),
    }
  ]])
end

describe("the slot panel in a real Neovim", function()
  local dir, file

  ---@param extra integer|nil  # yank slots after the file slot
  local function open_panel(extra)
    lua(
      [[
      local file, data, extra = ...
      vim.api.nvim_buf_set_lines(0, 0, -1, false, { "code one", "code two", "code three" })
      _G.MAIN = vim.api.nvim_get_current_win()
      local slots = require("ui.slots")
      slots.setup({ data_dir = data, persist = false, clipboard = { "a" } })
      slots.enable()
      slots.add({ kind = "file", path = file })
      for i = 1, extra do
        slots.add({ kind = "yank", text = "yank " .. i })
      end
      slots.panel()
    ]],
      { file, dir .. "/data", extra or 2 }
    )
    expect(function()
      return state().open
    end, "the panel opens")
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

  it("opens focused, with a row per slot and the cursor on the first", function()
    open_panel(2)
    local s = state()
    assert.is_true(s.open)
    assert.is_not.equals(s.main, s.win, "the focus is in the panel")
    assert.equals(3, #s.lines)
    assert.equals(1, s.current)
  end)

  it("j then <CR> runs the second slot with real keys and gives the focus back", function()
    open_panel(2)
    input("j<CR>")
    expect(function()
      return state().reg == "yank 1"
    end, "the yank slot ran")
    local s = state()
    assert.is_false(s.open)
    assert.equals(s.main, s.win, "the focus is back in the editor")
  end)

  it("<CR> on the file slot opens the file in the editor window", function()
    open_panel(1)
    input("<CR>")
    expect(function()
      return state().name:find("a.txt", 1, true) ~= nil
    end, "the file opened")
    assert.equals(state().main, state().win)
  end)

  it("typing a number jumps to that slot", function()
    open_panel(3)
    input("3")
    expect(function()
      return state().current == 3
    end, "the cursor went to slot 3")
  end)

  it("dd clears the slot and the panel redraws", function()
    open_panel(2)
    input("jdd")
    expect(function()
      return state().slots == 2
    end, "the slot is gone")
    local s = state()
    assert.is_true(s.open)
    assert.equals(2, #s.lines)
  end)

  it("<C-j> moves the slot down and the cursor goes along", function()
    open_panel(2)
    input("<C-j>")
    expect(function()
      return state().current == 2
    end, "the cursor followed the slot")
    assert.is_truthy(state().lines[1]:find("yank 1", 1, true))
  end)

  it("a double click on a row runs that slot", function()
    open_panel(2)
    local cfg = lua([[return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())]])
    -- inside the border: one row down, one column in
    local row, col = cfg.row + 1 + 1, cfg.col + 1 + 3
    for _ = 1, 2 do
      vim.rpcrequest(chan, "nvim_input_mouse", "left", "press", "", 0, row, col)
      vim.rpcrequest(chan, "nvim_input_mouse", "left", "release", "", 0, row, col)
    end
    expect(function()
      return state().reg == "yank 1"
    end, "the second row ran")
  end)

  it("a right click on a row opens the slot's menu, not Neovim's own", function()
    open_panel(2)
    lua([[
      _G.MENU = nil
      local select = require("ui.kit.select")
      select.open = function(opts) _G.MENU = opts.title end
    ]])
    local cfg = lua([[return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())]])
    local row, col = cfg.row + 1 + 1, cfg.col + 1 + 3
    vim.rpcrequest(chan, "nvim_input_mouse", "right", "press", "", 0, row, col)
    vim.rpcrequest(chan, "nvim_input_mouse", "right", "release", "", 0, row, col)
    expect(function()
      return lua([[return _G.MENU]]) == "slot 2"
    end, "the menu is that of slot 2")
    assert.is_false(vim.rpcrequest(chan, "nvim_get_mode").blocking, "no native popup menu")
  end)

  it("a click in the code closes the panel", function()
    open_panel(2)
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "press", "", 0, 0, 2)
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "release", "", 0, 0, 2)
    expect(function()
      return not state().open
    end, "the panel closed when the focus left")
  end)

  it("q closes it", function()
    open_panel(1)
    input("q")
    expect(function()
      return not state().open
    end, "closed")
    assert.equals(state().main, state().win)
  end)

  it("a opens the real kind chooser, and <Esc> brings the panel back", function()
    open_panel(1)
    input("a")
    expect(function()
      return state().chooser
    end, "the kind chooser is open")
    assert.is_false(state().open, "the panel stepped aside")
    input("<Esc>")
    expect(function()
      return state().open
    end, "the panel is back after the editor was cancelled")
  end)

  it("choosing a kind opens the real sheet, <Esc> on it brings the panel back", function()
    open_panel(1)
    input("a")
    expect(function()
      return state().chooser
    end, "the kind chooser is open")
    input("<CR>") -- the first kind: file
    expect(function()
      return not state().chooser and state().floats >= 1 and not state().open
    end, "the sheet is open")
    local text = lua([[
      local out = {}
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative ~= "" and type(c.title) == "table" then
          for _, chunk in ipairs(c.title) do out[#out + 1] = chunk[1] end
        end
      end
      return table.concat(out, " ")
    ]])
    assert.is_truthy(text:find("New file slot", 1, true), text)
    input("<Esc>")
    expect(function()
      return state().open
    end, "the panel is back")
  end)

  it("e on a yank slot opens the sheet for that slot", function()
    open_panel(2)
    input("j")
    input("e")
    expect(function()
      return not state().open and state().floats >= 1
    end, "the sheet opens")
    local text = lua([[
      local out = {}
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        local c = vim.api.nvim_win_get_config(w)
        if c.relative ~= "" and type(c.title) == "table" then
          for _, chunk in ipairs(c.title) do out[#out + 1] = chunk[1] end
        end
      end
      return table.concat(out, " ")
    ]])
    assert.is_truthy(text:find("Slot 2 (yank)", 1, true), text)
    input("<Esc>")
    expect(function()
      return state().open
    end, "back in the panel")
    assert.equals(2, state().current)
  end)
end)
