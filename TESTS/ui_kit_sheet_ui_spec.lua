-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `kit.sheet` in a real, UI-attached Neovim.
---
--- `ui_kit_sheet_spec.lua` drives the sheet from Normal mode, because this
--- runner has no UI and never enters Insert mode. That cannot show what the
--- person at the keyboard meets: where the labels sit (they are the window's
--- 'statuscolumn', drawn only on a real screen), which mode each row opens in,
--- where the cursor is, what the red message under a field looks like, and where
--- a real mouse click lands. So this file starts a child Neovim with `--embed`,
--- attaches a UI to it so that its main loop runs for real, and talks to it over
--- RPC -- the way `ui_kit_form_back_ui_spec.lua` does for `kit.form`.

---@type integer|nil
local chan

--- Root of the first runtimepath entry that carries `rel`.
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
---@return any
local function lua(code)
  return vim.rpcrequest(chan, "nvim_exec_lua", code, {})
end

--- What a person would see of the focused float.
---@return table
local function state()
  return lua([[
    local s = _G.SHEET
    return {
      mode = vim.api.nvim_get_mode().mode,
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
      modifiable = vim.bo.modifiable,
      height = vim.api.nvim_win_get_height(0),
      textoff = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff,
      sheet = s and s:is_valid() and s:state() or nil,
      result = _G.RESULT,
    }
  ]])
end

--- Poll until `cond(state)` holds; returns the state it held for.
---@param cond fun(s: table): boolean
---@param what string
---@return table
local function expect(cond, what)
  local last
  local ok = vim.wait(3000, function()
    last = state()
    return cond(last)
  end, 20)
  assert.is_true(ok, what .. " -- last state: " .. vim.inspect(last))
  return last
end

---@param keys string
local function input(keys)
  vim.rpcrequest(chan, "nvim_input", keys)
end

--- The screen as the user sees it: one list of cells per row (1-based rows).
---@return string[][]
local function screen_cells()
  return lua([[
    vim.cmd("redraw")
    local rows = {}
    for r = 1, vim.o.lines do
      local cells = {}
      for c = 1, vim.o.columns do
        cells[c] = vim.fn.screenstring(r, c)
      end
      rows[r] = cells
    end
    return rows
  ]])
end

--- The screen as text, trailing blanks dropped.
---@return string[]
local function screen_text()
  local out = {}
  for r, cells in ipairs(screen_cells()) do
    out[r] = (table.concat(cells):gsub("%s+$", ""))
  end
  return out
end

--- Where `needle` is on the screen: 0-based row and column of its first cell
--- (what `nvim_input_mouse` takes), nil when it is not there.
---@param needle string
---@return { row: integer, col: integer }|nil
local function find_on_screen(needle)
  local want = vim.fn.split(needle, "\\zs")
  for r, cells in ipairs(screen_cells()) do
    for c = 1, #cells - #want + 1 do
      local hit = true
      for k = 1, #want do
        if cells[c + k - 1] ~= want[k] then
          hit = false
          break
        end
      end
      if hit then
        return { row = r - 1, col = c - 1 }
      end
    end
  end
  return nil
end

---@param needle string
---@return string
local function screen_has(needle)
  return table.concat(screen_text(), "\n"):find(needle, 1, true) and "yes" or "no"
end

---@param row integer
---@param col integer
local function click(row, col)
  vim.rpcrequest(chan, "nvim_input_mouse", "left", "press", "", 0, row, col)
  vim.rpcrequest(chan, "nvim_input_mouse", "left", "release", "", 0, row, col)
end

--- Open a four-field sheet in the child: a required, validated number, a
--- select, an optional title and a secret.
local function open_sheet(extra)
  lua(([[
    _G.RESULT = nil
    _G.SHEET = require("ui.kit").sheet(vim.tbl_extend("force", {
      title = "New case",
      fields = {
        {
          name = "number",
          label = "Case number",
          required = true,
          validate = function(v)
            if v:match("^%%d+$") then
              return true
            end
            return false, "digits only"
          end,
        },
        { name = "area", label = "Area", kind = "select", choices = { "Alpha", "Beta", "Gamma" } },
        { name = "title", label = "Title" },
        { name = "token", label = "Token", secret = true },
      },
      on_submit = function(v) _G.RESULT = v end,
      on_cancel = function() _G.RESULT = "cancelled" end,
    }, %s))
  ]]):format(extra or "{}"))
  expect(function(s)
    return s.sheet ~= nil
  end, "the sheet opens")
end

describe("kit.sheet in a real Neovim", function()
  before_each(function()
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
    -- Over RPC, not as `--cmd "set rtp^=<dir>"`: `:set` splits at a space and at a
    -- comma, and a checkout under `C:\Users\First Last\...` has the one.
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
  end)

  it("draws the labels as a column left of the values, and opens in Insert mode", function()
    open_sheet()
    local s = state()
    assert.equals("i", s.mode)
    assert.same({ "", "Alpha", "", "" }, vim.list_slice(s.lines, 1, 4), "values only")
    assert.equals(13, s.textoff, "the longest label, a marker slot and a space")
    local text = table.concat(screen_text(), "\n")
    assert.is_truthy(text:find("Case number* ", 1, true), "the required marker follows the label")
    assert.is_truthy(text:find("Area         Alpha", 1, true), "a select shows its choice")
    assert.is_truthy(text:find("Title", 1, true))
    assert.is_truthy(text:find("[ Submit ]  [ Cancel ]", 1, true))
    assert.is_truthy(text:find("New case", 1, true))
    -- The cursor is in the value column, not in front of the label.
    local cursor = lua([[return vim.fn.screencol()]])
    assert.is_true(cursor > 13, "cursor at screen column " .. cursor)
  end)

  it("moves between the rows with <Tab>: Insert mode on text, Normal on a choice", function()
    open_sheet()
    input("977<Tab>")
    local s = expect(function(x)
      return x.sheet.focus == "area"
    end, "<Tab> moves to the select")
    assert.equals("n", s.mode)
    assert.is_false(s.modifiable)
    input("<Tab>")
    s = expect(function(x)
      return x.sheet.focus == "title"
    end, "and on to the title")
    assert.equals("i", s.mode)
    assert.is_true(s.modifiable)
    input("hello")
    s = expect(function(x)
      return x.lines[3] == "hello"
    end, "typing goes into the row")
    assert.equals("977", s.lines[1])
  end)

  it("puts a message under the field you leave, and takes it away once fixed", function()
    open_sheet()
    local before = state().height
    input("12x<Tab>")
    local s = expect(function(x)
      return x.sheet.errors.number ~= nil
    end, "leaving a bad value flags it")
    assert.equals("digits only", s.sheet.errors.number)
    assert.equals(before + 1, s.height, "the window grew by the row")
    assert.equals("yes", screen_has("✗ digits only"))
    -- Back to the field and fix it: the message goes with the edit, not on leaving.
    input("<S-Tab><BS>")
    expect(function(x)
      return x.sheet.errors.number == nil
    end, "fixing the value clears the message at once")
    assert.equals("no", screen_has("digits only"))
    assert.equals(before, state().height, "and the row is given back")
  end)

  it("blocks submit on a blank required field and jumps back to it, in Insert mode", function()
    open_sheet()
    input("<Tab><Tab>") -- to the title, number left blank
    expect(function(x)
      return x.sheet.focus == "title"
    end, "on the title")
    input("<CR><CR>") -- title -> token -> submit
    local s = expect(function(x)
      return x.sheet.errors.number ~= nil
    end, "submit flags the blank required field")
    assert.is_nil(s.result)
    assert.equals("number", s.sheet.focus, "and the focus jumps to it")
    assert.equals("i", s.mode)
    assert.equals("yes", screen_has("✗ required"))
  end)

  it(
    "submits through <CR> on the last field, hands on the keyed values, leaves Insert mode",
    function()
      open_sheet()
      input("977123<CR>")
      expect(function(x)
        return x.sheet.focus == "area"
      end, "<CR> on the number moves on")
      input("l<CR>") -- Beta; <CR> opens the chooser
      expect(function(x)
        return x.sheet.focus == "area" and not x.modifiable
      end, "the chooser has the focus")
      input("<CR>") -- the chooser's current row (Beta): picks it and moves on
      expect(function(x)
        return x.sheet.focus == "title"
      end, "a pick moves on to the title")
      input("a title<CR>secret<CR>")
      local s = expect(function(x)
        return type(x.result) == "table"
      end, "the last <CR> submits")
      assert.same(
        { number = "977123", area = "Beta", title = "a title", token = "secret" },
        s.result
      )
      assert.equals("n", s.mode, "no Insert mode left behind")
      assert.equals("no", screen_has("Case number"), "and the float is gone")
    end
  )

  it("hides a secret on screen", function()
    open_sheet()
    input("1<Tab><Tab><Tab>topsecret")
    expect(function(x)
      return x.lines[4] == "topsecret"
    end, "the secret is in the row")
    assert.equals("no", screen_has("topsecret"))
    assert.equals("yes", screen_has("*********"))
  end)

  it("leaves no secret in the . register once the sheet is submitted or cancelled", function()
    local function dot()
      return lua([[return vim.fn.getreg(".")]])
    end
    -- The Insert run of title -> token carries the secret; submitting ends it ...
    open_sheet()
    input("1<Tab><Tab><Tab>topsecret")
    expect(function(x)
      return x.lines[4] == "topsecret"
    end, "the secret is in the row")
    input("<CR>")
    expect(function(x)
      return type(x.result) == "table"
    end, "the last <CR> submits")
    assert.equals("topsecret", state().result.token)
    vim.wait(300) -- the scrub runs once the Insert run has ended
    assert.equals("", dot(), "nothing of it is left in the register after a submit")

    -- ... and so does cancelling it.
    open_sheet()
    input("1<Tab><Tab><Tab>topsecret")
    expect(function(x)
      return x.lines[4] == "topsecret"
    end, "the secret is in the row again")
    input("<Esc>")
    expect(function(x)
      return x.result == "cancelled"
    end, "<Esc> cancels")
    vim.wait(300)
    assert.equals("", dot(), "nor after a cancel")
  end)

  it("cancels with <Esc> from a text row and from a choice", function()
    open_sheet()
    input("<Esc>")
    expect(function(x)
      return x.result == "cancelled"
    end, "<Esc> cancels")

    open_sheet()
    input("<Tab>")
    expect(function(x)
      return x.sheet.focus == "area"
    end, "on the select")
    input("<Esc>")
    expect(function(x)
      return x.result == "cancelled"
    end, "<Esc> cancels there too")
  end)

  it("focuses the row a real click lands on, with the cursor where it was clicked", function()
    open_sheet()
    input("<Tab><Tab>title text")
    expect(function(x)
      return x.lines[3] == "title text"
    end, "a title is typed")
    input("<Tab><Tab>")
    expect(function(x)
      return x.sheet.focus == "submit"
    end, "on the buttons")
    local at = assert(find_on_screen("title text"), "the title is on screen")
    click(at.row, at.col + 6)
    local s = expect(function(x)
      return x.sheet.focus == "title" and x.mode == "i"
    end, "a click on the title row focuses it, in Insert mode")
    local cursor = lua([[return vim.api.nvim_win_get_cursor(0)]])
    assert.same({ 3, 6 }, cursor)
    assert.equals("title text", s.lines[3])
  end)

  it("presses the button a real click lands on", function()
    open_sheet()
    input("977<Tab><Tab>")
    local at = assert(find_on_screen("Submit"), "the Submit button is on screen")
    click(at.row, at.col)
    local s = expect(function(x)
      return type(x.result) == "table"
    end, "a click on [ Submit ] submits")
    assert.equals("977", s.result.number)

    open_sheet()
    at = assert(find_on_screen("Cancel"), "the Cancel button is on screen")
    click(at.row, at.col + 1)
    expect(function(x)
      return x.result == "cancelled"
    end, "a click on [ Cancel ] cancels")
  end)

  it("leaves the field a refused click on [ Submit ] returns to in Insert mode", function()
    open_sheet()
    -- Insert mode on the blank, required number: submitting is refused, and the focus
    -- goes back to that field -- which has to be typed into, not commanded.
    assert.equals("i", state().mode)
    local at = assert(find_on_screen("Submit"), "the Submit button is on screen")
    click(at.row, at.col)
    local s = expect(function(x)
      return x.sheet.errors.number ~= nil
    end, "the click is refused: the blank required field is flagged")
    assert.is_nil(s.result)
    assert.equals("number", s.sheet.focus)
    vim.wait(150) -- the click's own stopinsert, were there one, lands after the mapping returns
    assert.equals("i", state().mode, "the field is in Insert mode")
    input("abc")
    expect(function(x)
      return x.lines[1] == "abc"
    end, "what is typed goes into the field (in Normal mode the first key would be a command)")

    -- The same from a select row (Normal mode): the control, which always worked.
    input("<BS><BS><BS><Tab>")
    expect(function(x)
      return x.sheet.focus == "area" and x.mode == "n" and x.lines[1] == ""
    end, "the number is blank again and the focus is on the select row")
    -- A second click within 'mousetime' (500 ms) of the first would be a double click.
    vim.wait(600)
    at = assert(find_on_screen("Submit"))
    click(at.row, at.col)
    expect(function(x)
      return x.sheet.focus == "number" and x.mode == "i"
    end, "a refused click from a select row lands in the field in Insert mode")
  end)

  it("keeps the buttons on screen, and clickable, under a long value that wraps", function()
    open_sheet()
    input("1<Tab><Tab>" .. string.rep("word ", 30))
    expect(function(x)
      return #x.lines[3] == 150
    end, "the long title is in the row")
    local s = state()
    assert.is_true(s.height >= 8, "the window grew to fit the wrapped rows: " .. s.height)
    local at = assert(find_on_screen("Submit"), "the button row is still on screen")
    -- The continuation rows start in the value column, under the first one.
    local first = assert(find_on_screen("word word"), "the value is on screen")
    local next_row = screen_cells()[first.row + 2] -- 1-based: the row below
    assert.not_equals(" ", next_row[first.col + 1], "the wrapped text starts under the value")
    assert.equals(" ", next_row[first.col], "and not under the label")
    click(at.row, at.col)
    expect(function(x)
      return type(x.result) == "table"
    end, "and the click lands on the button")
  end)

  it("keeps the rows and the button row when a paste carries a newline", function()
    open_sheet()
    vim.rpcrequest(chan, "nvim_paste", "977\n", true, -1)
    local s = expect(function(x)
      return x.lines[1] == "977 " or x.lines[1] == "977"
    end, "the paste is one row again")
    assert.equals(6, #s.lines, "four fields, the blank line, the buttons")
    assert.is_truthy(s.lines[6]:find("Submit", 1, true))
    assert.equals("i", s.mode)
    assert.is_truthy(find_on_screen("Submit"), "and the buttons are on screen")
  end)
end)
