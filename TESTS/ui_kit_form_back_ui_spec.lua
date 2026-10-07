-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `kit.form({ back = true })` in a real, UI-attached Neovim.
---
--- The specs in `ui_kit_spec.lua` drive the kit from Normal mode, because this
--- runner has no UI and never enters Insert mode -- and that hides exactly the
--- things a person typing at a form meets: whether `<BS>` still deletes, which
--- mode the NEXT field opens in, and where a real mouse click lands (the
--- coordinates `getmousepos()` reports for a bordered float are the part that
--- is easy to get wrong and impossible to stub faithfully). So this file starts
--- a child Neovim with `--embed`, attaches a UI to it so that its main loop
--- runs for real, and talks to it over RPC: `nvim_input` for keys,
--- `nvim_input_mouse` for clicks, `nvim_exec_lua` to read the state back.

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
    local t = vim.api.nvim_win_get_config(0).title
    return {
      mode = vim.api.nvim_get_mode().mode,
      title = type(t) == "table" and t[1] and t[1][1] or t,
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
      modifiable = vim.bo.modifiable,
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

--- The second text row of the focused float (the button row) as it is drawn on
--- screen, one entry per cell, with where it is: `row` and `left` are the 0-based
--- screen row and first text column (what `nvim_input_mouse` takes) and `leftcol`
--- is how far the window has scrolled sideways.
---@return { cells: string[], row: integer, left: integer, leftcol: integer }
local function screen_cells()
  return lua([[
    vim.cmd("redraw")
    local win = vim.api.nvim_get_current_win()
    -- win_screenpos() is the corner INCLUDING the border (1-based).
    local pos = vim.fn.win_screenpos(win)
    local cells = {}
    for c = 1, vim.api.nvim_win_get_width(win) do
      cells[c] = vim.fn.screenstring(pos[1] + 2, pos[2] + c)
    end
    return { cells = cells, row = pos[1] + 1, left = pos[2], leftcol = vim.fn.winsaveview().leftcol }
  ]])
end

--- Pause long enough that the next `<BS>` is a new press, not the repeat of a
--- key that is still held (`ui.kit.input` tells them apart by the gap: 300 ms).
local function wait_past_a_held_key()
  vim.wait(400)
end

--- Open a three-field form with `back = true` in the child.
local function open_form()
  lua([[
    _G.RESULT = nil
    require("ui.kit").form({
      back = true,
      fields = {
        { name = "a", label = "A", default = "abc" },
        { name = "b", label = "B", default = "xy" },
        { name = "c", label = "C", required = true },
      },
      on_submit = function(v) _G.RESULT = v end,
      on_cancel = function() _G.RESULT = "cancelled" end,
    })
  ]])
  expect(function(s)
    return s.title == "A (1/3)"
  end, "the form opens on its first field")
end

describe("kit.form back navigation in a real Neovim", function()
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

  it("opens every field of the chain in Insert mode, going forward and going back", function()
    open_form()
    assert.equals("i", state().mode)
    input("<CR>")
    local s = expect(function(x)
      return x.title == "B (2/3)"
    end, "<CR> opens the next field")
    assert.equals("i", s.mode, "the next field is typed into, not commanded")
    input("<S-Tab>")
    s = expect(function(x)
      return x.title == "A (1/3)"
    end, "<S-Tab> goes back")
    assert.equals("i", s.mode)
    assert.equals("abc", s.lines[1])
  end)

  it("deletes with <BS> while there is text and goes back once the field is empty", function()
    open_form()
    input("<CR>") -- A -> B, which shows "xy"
    expect(function(x)
      return x.title == "B (2/3)"
    end, "on field B")
    input("<BS>")
    local s = expect(function(x)
      return x.lines[1] == "x"
    end, "<BS> deletes a character")
    assert.equals("B (2/3)", s.title)
    input("<BS>")
    expect(function(x)
      return x.lines[1] == ""
    end, "<BS> empties the field")
    assert.equals("B (2/3)", state().title)
    wait_past_a_held_key()
    input("<BS>")
    s = expect(function(x)
      return x.title == "A (1/3)"
    end, "<BS> on the empty field goes back")
    assert.equals("abc", s.lines[1], "with the previous answer to correct")
    input("<BS>")
    expect(function(x)
      return x.lines[1] == "ab"
    end, "and the first field has nowhere to go back to")
    assert.equals("A (1/3)", state().title)
  end)

  it("does not walk back through the earlier fields while <BS> is held down", function()
    open_form()
    input("<CR>") -- A -> B, which shows "xy"
    expect(function(x)
      return x.title == "B (2/3)"
    end, "on field B")
    input("<CR>") -- B -> C, empty
    expect(function(x)
      return x.title == "C (3/3)"
    end, "on field C")
    input("zz") -- two characters, so the run has something to delete first
    -- A held key is a burst of presses with no pause between them: more than
    -- enough of them to delete the text, walk back and delete the previous
    -- field's answer as well, were each one taken for a new press.
    input(string.rep("<BS>", 30))
    expect(function(x)
      return x.lines[1] == ""
    end, "the held key deletes what is in the field")
    vim.wait(100)
    assert.equals("C (3/3)", state().title, "and stops there")
    -- Let go, press again: now it is a deliberate press.
    wait_past_a_held_key()
    input("<BS>")
    local s = expect(function(x)
      return x.title == "B (2/3)"
    end, "a fresh <BS> goes back")
    assert.equals("xy", s.lines[1], "to an answer that is still there")
  end)

  it("moves onto the buttons with <Down>, and <CR> there presses the focused one", function()
    open_form()
    input("<Down>")
    local s = expect(function(x)
      return x.mode == "n" and not x.modifiable
    end, "<Down> leaves the field for the button row")
    assert.equals("A (1/3)", s.title)
    input("<CR>")
    expect(function(x)
      return x.title == "B (2/3)"
    end, "<CR> on [ Next ↵ ] submits the field")
    input("<Down>")
    input("<Tab>") -- wraps from Next to Back
    expect(function(x)
      return not x.modifiable
    end, "the buttons have focus on field B")
    input("<CR>")
    local back = expect(function(x)
      return x.title == "A (1/3)"
    end, "<CR> on [ ← Back ] goes back")
    assert.equals("abc", back.lines[1])
    assert.equals("i", back.mode)
  end)

  it("leaves Insert mode after the last field, with the answers collected", function()
    open_form()
    input("one<CR>") -- A: "abc" + "one"
    expect(function(x)
      return x.title == "B (2/3)"
    end, "on field B")
    input("<CR>")
    expect(function(x)
      return x.title == "C (3/3)"
    end, "on field C")
    input("three<CR>")
    local s = expect(function(x)
      return type(x.result) == "table"
    end, "the last <CR> submits the form")
    assert.same({ a = "abcone", b = "xy", c = "three" }, s.result)
    assert.equals("n", s.mode, "no lingering Insert mode once the chain is over")
  end)

  it("presses the button that a real mouse click lands on", function()
    open_form()
    input("<CR>") -- on field B, the row now has a Back button
    expect(function(x)
      return x.title == "B (2/3)"
    end, "on field B")
    local at = lua([[
      local win = vim.api.nvim_get_current_win()
      local line = vim.api.nvim_buf_get_lines(0, 1, 2, false)[1]
      -- win_screenpos() is the top-left corner INCLUDING the border: text starts one
      -- row down and one column in. A button label begins `from` bytes into the line;
      -- the padding before it is spaces, so bytes are cells.
      local pos = vim.fn.win_screenpos(win)
      local from = line:find("[ ← Back ]", 1, true)
      return { row = pos[1] - 1 + 2, col = pos[2] - 1 + 1 + (from - 1) + 3 }
    ]])
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "press", "", 0, at.row, at.col)
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "release", "", 0, at.row, at.col)
    local s = expect(function(x)
      return x.title == "A (1/3)"
    end, "a click on [ ← Back ] goes back")
    assert.equals("abc", s.lines[1])
  end)

  it("keeps the buttons in view, and clickable, while a long answer scrolls the field", function()
    open_form()
    -- A shows "abc"; 70 more characters are far wider than the 40-column box.
    input(string.rep("x", 70))
    expect(function(x)
      return #x.lines[1] == 73
    end, "the whole answer is in the field")
    local drawn
    local ok = vim.wait(3000, function()
      drawn = screen_cells()
      return table.concat(drawn.cells):find("Next", 1, true) ~= nil
    end, 20)
    assert.is_true(ok, "the button row is on screen: " .. vim.inspect(drawn))
    assert.is_true(drawn.leftcol > 0, "the window did scroll sideways")
    -- Click it where it is DRAWN.
    local col
    for c = 1, #drawn.cells - 3 do
      if table.concat(drawn.cells, "", c, c + 3) == "Next" then
        col = drawn.left + c - 1
        break
      end
    end
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "press", "", 0, drawn.row, col)
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "release", "", 0, drawn.row, col)
    expect(function(x)
      return x.title == "B (2/3)"
    end, "a click on [ Next ↵ ] submits the long answer")
    input("<S-Tab>")
    local back = expect(function(x)
      return x.title == "A (1/3)"
    end, "and back again")
    assert.equals("abc" .. string.rep("x", 70), back.lines[1], "with all of it")
  end)

  it("keeps a one-line field and its button row when a paste carries a newline", function()
    open_form()
    -- What a copied line usually brings along.
    vim.rpcrequest(chan, "nvim_paste", "some/path\n", true, -1)
    local s = expect(function(x)
      return x.lines[1] == "abcsome/path" and #x.lines == 2
    end, "the paste is one line again, with the row right under it")
    assert.is_truthy(s.lines[2]:find("Next", 1, true))
    assert.equals("i", s.mode)
    local drawn = screen_cells()
    assert.is_truthy(table.concat(drawn.cells):find("Next", 1, true), "and the row is on screen")
    -- Several lines are joined, not dropped.
    vim.rpcrequest(chan, "nvim_paste", "one\ntwo", true, -1)
    expect(function(x)
      return x.lines[1] == "abcsome/pathone two" and #x.lines == 2
    end, "a paste of two lines is joined with a space")
    input("<Down>")
    input("<CR>")
    expect(function(x)
      return x.title == "B (2/3)"
    end, "and the buttons still work")
  end)

  it("lets a click on blank space or on the text change nothing but the cursor", function()
    open_form()
    local at = lua([[
      local pos = vim.fn.win_screenpos(vim.api.nvim_get_current_win())
      return { row = pos[1] - 1 + 2, col = pos[2] - 1 + 1 }
    ]])
    -- Second text row, far left: inside the float, on no button.
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "press", "", 0, at.row + 1, at.col)
    vim.rpcrequest(chan, "nvim_input_mouse", "left", "release", "", 0, at.row + 1, at.col)
    -- Barrier: a key whose effect is visible, queued behind the clicks.
    input("<Down>")
    local s = expect(function(x)
      return not x.modifiable
    end, "the form is still on field A, and <Down> still reaches its buttons")
    assert.equals("A (1/3)", s.title)
  end)

  describe(
    "a field that was split by a paste or <C-j> before the focus moved onto the buttons",
    function()
      -- A line opened in Insert mode keeps the indent Neovim added (`autoindent` is on in
      -- every Neovim): `stopinsert` deletes the white space under the cursor, and the
      -- cursor was parked on the space after the `[` of the button. The row came back
      -- one space short, and the field joined with it into the answer.
      for name, split in pairs({
        ["a linewise register"] = function()
          lua([[vim.fn.setreg('"', "copied line\n", "V")]])
          input('<C-r>"')
        end,
        ["<C-j>"] = function()
          input("<C-j>")
        end,
      }) do
        it("keeps the button row whole after " .. name, function()
          open_form()
          local row = state().lines[2]
          assert.is_truthy(row:find("[ Next ↵ ]", 1, true), "the row as laid out: " .. row)
          split()
          expect(function(x)
            return #x.lines >= 2 and x.mode == "i"
          end, "the field was split")
          input("<Tab>")
          local s = expect(function(x)
            return not x.modifiable
          end, "the focus is on the buttons")
          assert.equals(row, s.lines[2], "the button row is as it was laid out")
          input("<Up>")
          s = expect(function(x)
            return x.modifiable
          end, "back in the field")
          assert.equals(2, #s.lines)
          assert.is_nil(s.lines[1]:find("Next", 1, true), "the field holds no button text")
          assert.is_truthy(s.lines[1]:find("^abc"), "but what was typed: " .. s.lines[1])
          assert.equals(row, s.lines[2])
          input("<CR>")
          expect(function(x)
            return x.title == "B (2/3)"
          end, "the next field opens")
          input("<S-Tab>")
          s = expect(function(x)
            return x.title == "A (1/3)"
          end, "and back")
          assert.is_nil(s.lines[1]:find("Next", 1, true), "the answer carries no button text")
        end)
      end
    end
  )
end)
