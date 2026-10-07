-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `kit.sheet`: every field of a form in ONE float, labelled rows, inline
--- validation, a Submit/Cancel button row.
---
--- Driven from Normal mode like the form specs in `ui_kit_spec.lua` (this
--- headless runner never enters Insert mode, and every key under test is mapped
--- for `i` and `n`). Typing is the buffer written to plus the `TextChanged` the
--- keystroke would have fired; a mouse click is the `<LeftMouse>` mapping's own
--- callback with `getmousepos()` stubbed. What only a real UI can show -- the
--- label column, the cursor, a real click, Insert mode -- is
--- `ui_kit_sheet_ui_spec.lua`'s.

local kit = require("ui.kit")

local api = vim.api

-- `:startinsert` from a mapping leaves a pending Insert mode that this runner prints as
-- "-- (insert) --" on every redraw; nothing here looks at it.
vim.o.showmode = false

---@param k string
local function keys(k)
  api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "x", false)
end

--- Close every float. A sheet closed from the outside is a cancel, so this also
--- ends whatever is still open.
local function close_floats()
  for _ = 1, 10 do
    local closed = false
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
        closed = true
      end
    end
    if not closed then
      return
    end
  end
end

---@param fields table[]
---@param extra? table
---@return table result  # { surf, values, cancelled, submits }
local function open(fields, extra)
  local result = { submits = 0, fields = #fields }
  result.surf = kit.sheet(vim.tbl_extend("force", {
    fields = fields,
    on_submit = function(values)
      result.values = values
      result.submits = result.submits + 1
    end,
    on_cancel = function()
      result.cancelled = (result.cancelled or 0) + 1
    end,
  }, extra or {}))
  return result
end

--- What the user typed into row `i`: the buffer, and the `TextChanged` a real
--- keystroke would have fired.
---@param r table
---@param i integer
---@param text string
local function type_into(r, i, text)
  api.nvim_buf_set_lines(r.surf.bufnr, i - 1, i, false, { text })
  api.nvim_exec_autocmds("TextChanged", { buffer = r.surf.bufnr })
end

---@param r table
---@return string[]
local function lines_of(r)
  return api.nvim_buf_get_lines(r.surf.bufnr, 0, -1, false)
end

--- The messages drawn under the fields right now.
---@param r table
---@return string[]
local function shown_errors(r)
  local ns = api.nvim_get_namespaces().lib_kit_sheet
  local out = {}
  for _, m in ipairs(api.nvim_buf_get_extmarks(r.surf.bufnr, ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      out[#out + 1] = vl[1][1]
    end
  end
  return out
end

--- Left-click at (`line`, `column`) of the focused float, 1-based like
--- `getmousepos()`, by running the mapping that `<LeftMouse>` is bound to.
---@param line integer
---@param column integer
local function click_at(line, column)
  local real = vim.fn.getmousepos
  vim.fn.getmousepos = function()
    return { winid = api.nvim_get_current_win(), line = line, column = column }
  end
  local map = vim.fn.maparg("<LeftMouse>", "n", false, true)
  local ok, err = pcall(map.callback)
  vim.fn.getmousepos = real
  assert(ok, err)
end

---@param r table
---@param label string
local function click_button(r, label)
  local n = r.fields
  local line = api.nvim_buf_get_lines(r.surf.bufnr, n + 1, n + 2, false)[1]
  local from = assert(line:find("[ " .. label .. " ]", 1, true), "no such button: " .. label)
  click_at(n + 2, from + 2)
end

local THREE = {
  { name = "a", label = "Alpha" },
  { name = "b", label = "Beta", required = true },
  { name = "c", label = "Gamma" },
}

describe("kit.sheet", function()
  after_each(close_floats)

  describe("the component", function()
    it("is reachable as kit.sheet and as kit.popup({ type = 'sheet' })", function()
      local direct = open(THREE)
      assert.is_true(direct.surf:is_valid())
      close_floats()
      local viaPopup = kit.popup({
        type = "sheet",
        fields = THREE,
        on_submit = function() end,
      })
      assert.is_true(viaPopup:is_valid())
    end)

    it("shows every field at once: one row each, then a blank line and the buttons", function()
      local r = open({
        { name = "a", label = "Alpha", default = "one" },
        { name = "b", label = "Beta", kind = "select", choices = { "x", "y" }, default = "y" },
        { name = "c", label = "Gamma" },
      })
      assert.same({ "one", "y", "", "" }, vim.list_slice(lines_of(r), 1, 4))
      assert.equals(5, #lines_of(r))
      assert.equals("[ Submit ]  [ Cancel ]", vim.trim(lines_of(r)[5]))
      assert.equals(5, api.nvim_win_get_height(r.surf.winid), "all of it, no scrolling")
    end)

    it("opens its buffer without auto-indent", function()
      local r = open(THREE)
      for _, name in ipairs({ "autoindent", "smartindent", "cindent" }) do
        assert.is_false(vim.bo[r.surf.bufnr][name], name .. " is off")
      end
    end)

    it("keeps the labels out of the buffer: they are the window's 'statuscolumn'", function()
      local r = open(THREE)
      for _, line in ipairs(lines_of(r)) do
        assert.is_nil(line:find("Alpha", 1, true))
      end
      assert.is_truthy(vim.wo[r.surf.winid].statuscolumn:find("ui.kit.sheet", 1, true))
    end)

    it("draws the column from the label, a marker for a required field and the focus", function()
      local r = open(THREE, { focus = "b" })
      local sheet = require("ui.kit.sheet")
      local winid = r.surf.winid
      local function column(lnum)
        vim.g.statusline_winid = winid
        vim.v.lnum = lnum
        return sheet.column()
      end
      assert.is_truthy(column(1):find("KitMuted#Alpha", 1, true))
      assert.is_truthy(column(2):find("KitAccent#Beta", 1, true), "the focused label")
      assert.is_truthy(column(2):find("KitError#* ", 1, true), "the required marker")
      assert.is_truthy(column(1):find("KitError#  ", 1, true), "no marker on an optional one")
      assert.equals(
        "%#KitMuted#" .. string.rep(" ", 7),
        column(4),
        "a row that is no field gets blanks as wide as the label column"
      )
    end)

    it("takes its button labels, title and starting focus from the options", function()
      local r = open(THREE, {
        title = "Fill in",
        submit_label = "Create",
        cancel_label = "Abort",
        focus = "c",
      })
      assert.equals("[ Create ]  [ Abort ]", vim.trim(lines_of(r)[5]))
      assert.equals("Fill in", api.nvim_win_get_config(r.surf.winid).title[1][1])
      assert.equals("c", r.surf:state().focus)
    end)

    it("opening on another field does not check the first, which was never visited", function()
      local r = open({
        { name = "n", label = "N", required = true },
        { name = "m", label = "M" },
      }, { focus = "m" })
      assert.equals("m", r.surf:state().focus)
      assert.same({}, r.surf:state().errors)
    end)

    it("opens on the first field by default, or the one given by position", function()
      assert.equals("a", open(THREE).surf:state().focus)
      close_floats()
      assert.equals("c", open(THREE, { focus = 3 }).surf:state().focus)
    end)

    it("answers an empty field list like kit.form: submit with nothing, no float", function()
      local r = open({})
      assert.is_nil(r.surf)
      assert.same({}, r.values)
    end)

    it("calls on_cancel instead of stalling when the float could not be opened", function()
      local saved_surface = package.loaded["ui.kit.surface"]
      package.loaded["ui.kit.sheet"] = nil
      package.loaded["ui.kit.surface"] = {
        open = function()
          return nil
        end,
      }
      local sheet = require("ui.kit.sheet")
      local cancelled, submitted = false, false
      local returned = sheet.open({
        fields = THREE,
        on_submit = function()
          submitted = true
        end,
        on_cancel = function()
          cancelled = true
        end,
      })
      package.loaded["ui.kit.surface"] = saved_surface
      package.loaded["ui.kit.sheet"] = nil
      require("ui.kit.sheet")
      assert.is_nil(returned)
      assert.is_true(cancelled)
      assert.is_false(submitted)
    end)
  end)

  describe("moving between the fields", function()
    it("walks fields and buttons with <Tab>/<S-Tab>, wrapping around", function()
      local r = open(THREE)
      local seen = {}
      for _ = 1, 6 do
        seen[#seen + 1] = r.surf:state().focus
        keys("<Tab>")
      end
      assert.same({ "a", "b", "c", "submit", "cancel", "a" }, seen)
      keys("<S-Tab><S-Tab>")
      assert.equals("cancel", r.surf:state().focus, "<S-Tab> from the first wraps to the last")
    end)

    it("moves with <Down>/<Up> and j/k too, but they stop at the ends", function()
      local r = open(THREE)
      keys("<Up>")
      assert.equals("a", r.surf:state().focus)
      keys("<Down>")
      keys("j")
      assert.equals("c", r.surf:state().focus)
      for _ = 1, 5 do
        keys("<Down>")
      end
      assert.equals("cancel", r.surf:state().focus)
      keys("k")
      assert.equals("submit", r.surf:state().focus)
    end)

    it("moves to the next field with <CR>, and presses Submit on the last one", function()
      local r = open(THREE)
      type_into(r, 2, "b-value")
      keys("<CR>")
      assert.equals("b", r.surf:state().focus)
      keys("<CR>")
      assert.equals("c", r.surf:state().focus)
      assert.is_nil(r.values)
      keys("<CR>")
      assert.same({ a = "", b = "b-value", c = "" }, r.values)
      assert.is_false(r.surf:is_valid())
    end)

    it("puts the focus on the field under a click, and presses a clicked button", function()
      local r = open(THREE)
      click_at(3, 1)
      assert.equals("c", r.surf:state().focus)
      click_button(r, "Cancel")
      assert.equals(1, r.cancelled)
      assert.is_false(r.surf:is_valid())
    end)

    it("leaves a click that is in no field and on no button as it was", function()
      local r = open(THREE)
      click_at(4, 1) -- the blank line
      assert.equals("a", r.surf:state().focus)
      assert.is_true(r.surf:is_valid())
    end)

    it("locks the buffer while a button has the focus, unlocks it on a text row", function()
      local r = open(THREE)
      assert.is_true(vim.bo[r.surf.bufnr].modifiable)
      keys("<Down><Down><Down>")
      assert.equals("submit", r.surf:state().focus)
      assert.is_false(vim.bo[r.surf.bufnr].modifiable)
      keys("<Up>")
      assert.is_true(vim.bo[r.surf.bufnr].modifiable)
    end)

    it("keeps the cursor on the focused row whatever moved it", function()
      local r = open(THREE)
      keys("<Down>")
      api.nvim_win_set_cursor(r.surf.winid, { 4, 0 })
      api.nvim_exec_autocmds("CursorMoved", { buffer = r.surf.bufnr })
      assert.equals(2, api.nvim_win_get_cursor(r.surf.winid)[1])
    end)
  end)

  describe("the buttons", function()
    it("submits with <CR> on Submit, from the button row", function()
      local r = open(THREE)
      type_into(r, 2, "x")
      keys("<Down><Down><Down>")
      assert.equals("submit", r.surf:state().focus)
      keys("<CR>")
      assert.same({ a = "", b = "x", c = "" }, r.values)
    end)

    it("cancels with <CR> on Cancel, <Esc> from anywhere, and a click on Cancel", function()
      local r = open(THREE)
      keys("<Tab><Tab><Tab><Tab>")
      assert.equals("cancel", r.surf:state().focus)
      keys("<CR>")
      assert.equals(1, r.cancelled)
      assert.is_nil(r.values)

      local r2 = open(THREE)
      keys("<Esc>")
      assert.equals(1, r2.cancelled)
      assert.is_false(r2.surf:is_valid())
    end)

    it("does not stop Insert mode on the way to a refused click on Submit", function()
      -- The click used to move the focus onto the button first, which stops Insert
      -- mode -- after the mapping returns, so the `startinsert` of the refused submit,
      -- which puts the focus back on the bad field, was ignored and the field ended
      -- up in Normal mode (ui_kit_sheet_ui_spec.lua shows it for real).
      local r = open(THREE)
      assert.equals("a", r.surf:state().focus)
      local stops = 0
      local real_cmd = vim.cmd
      vim.cmd = setmetatable({}, {
        __call = function(_, c, ...)
          if c == "stopinsert" then
            stops = stops + 1
          end
          return real_cmd(c, ...)
        end,
        __index = real_cmd,
      })
      local ok, err = pcall(click_button, r, "Submit")
      vim.cmd = real_cmd
      assert(ok, err)
      assert.equals("b", r.surf:state().focus, "the blank required field has the focus again")
      assert.is_nil(r.values, "the submit was refused")
      assert.equals(0, stops, "nothing stopped Insert mode on the way")
    end)

    it("moves along the buttons with h/l and presses with <Space>", function()
      local r = open(THREE)
      keys("<Down><Down><Down>")
      assert.equals("submit", r.surf:state().focus)
      keys("l")
      assert.equals("cancel", r.surf:state().focus)
      keys("l")
      assert.equals("submit", r.surf:state().focus, "wraps")
      keys("h")
      assert.equals("cancel", r.surf:state().focus)
      keys("<Space>")
      assert.equals(1, r.cancelled)
    end)

    it("fires exactly one callback, once, however the sheet is left", function()
      local r = open(THREE)
      type_into(r, 2, "x")
      r.surf:submit()
      r.surf:cancel()
      r.surf:submit()
      assert.equals(1, r.submits)
      assert.is_nil(r.cancelled)

      local r2 = open(THREE)
      api.nvim_win_close(r2.surf.winid, true)
      assert.equals(1, r2.cancelled, "closing the window is a cancel")
      r2.surf:cancel()
      assert.equals(1, r2.cancelled)
    end)
  end)

  describe("a select field", function()
    local FIELDS = {
      { name = "n", label = "Name" },
      { name = "area", label = "Area", kind = "select", choices = { "one", "two", "three" } },
      { name = "z", label = "Z" },
    }

    it("shows its first choice, or the one named by default, and returns the choice", function()
      local r = open(FIELDS)
      assert.equals("one", lines_of(r)[2])
      r.surf:submit()
      assert.equals("one", r.values.area)

      local r2 = open({
        { name = "area", kind = "select", choices = { "one", "two", "three" }, default = "three" },
      })
      assert.equals("three", lines_of(r2)[1])
    end)

    it("cycles with h/l and the arrows, wrapping", function()
      local r = open(FIELDS)
      keys("<Tab>")
      assert.is_false(vim.bo[r.surf.bufnr].modifiable, "a choice is not typed")
      keys("l")
      assert.equals("two", lines_of(r)[2])
      keys("<Right><Right>")
      assert.equals("one", lines_of(r)[2])
      keys("h")
      assert.equals("three", lines_of(r)[2])
      keys("<Left>")
      assert.equals("two", lines_of(r)[2])
      assert.equals("two", r.surf:state().values.area)
    end)

    it("opens kit.select over the choices with <CR>/<Space>; a pick moves on", function()
      local r = open(FIELDS)
      keys("<Tab>")
      keys("<CR>")
      assert.is_true(kit.chooser.is_open())
      kit.chooser.move(1)
      kit.chooser.submit()
      assert.equals("two", lines_of(r)[2])
      assert.equals("z", r.surf:state().focus, "a pick is an answer: on to the next field")
      assert.equals(r.surf.winid, api.nvim_get_current_win())

      keys("<S-Tab>")
      keys("<Space>")
      assert.is_true(kit.chooser.is_open())
      kit.chooser.close()
    end)

    it("focuses the sheet again when the chooser is dismissed", function()
      local r = open(FIELDS)
      keys("<Tab>")
      keys("<CR>")
      kit.chooser.close()
      vim.wait(200, function()
        return api.nvim_get_current_win() == r.surf.winid
      end, 10)
      assert.equals(r.surf.winid, api.nvim_get_current_win())
      assert.equals("area", r.surf:state().focus)
      assert.equals("one", lines_of(r)[2], "nothing was picked")
    end)

    it("is a plain text field when it has no choices", function()
      local r = open({ { name = "k", kind = "select", choices = {} } })
      assert.is_true(vim.bo[r.surf.bufnr].modifiable)
    end)
  end)

  describe("a text field", function()
    it("returns what is typed, and the default when nothing is", function()
      local r = open({
        { name = "a", label = "A", default = "dflt" },
        { name = "b", label = "B" },
      })
      assert.equals("dflt", lines_of(r)[1])
      type_into(r, 2, "typed")
      r.surf:submit()
      assert.same({ a = "dflt", b = "typed" }, r.values)
    end)

    it("expands ~ and $VAR in the value when expand_env is set", function()
      vim.env.SHEET_SPEC_DIR = "/some/dir"
      local r = open({
        { name = "p", label = "P", expand_env = true },
        { name = "q", label = "Q" },
      })
      type_into(r, 1, "$SHEET_SPEC_DIR/x")
      type_into(r, 2, "$SHEET_SPEC_DIR/x")
      r.surf:submit()
      assert.equals("/some/dir/x", r.values.p:gsub("\\", "/"))
      assert.equals("$SHEET_SPEC_DIR/x", r.values.q, "only on request")
      vim.env.SHEET_SPEC_DIR = nil
    end)

    it("masks a secret field on screen but hands on the real text", function()
      local r = open({
        { name = "pw", label = "Password", secret = true, default = "hunter2", mask = "#" },
      })
      local ns = api.nvim_get_namespaces().lib_kit_sheet
      local marks = api.nvim_buf_get_extmarks(r.surf.bufnr, ns, 0, -1, { details = true })
      assert.equals(7, #marks)
      assert.equals("#", marks[1][4].conceal)
      assert.equals(2, vim.wo[r.surf.winid].conceallevel)
      r.surf:submit()
      assert.equals("hunter2", r.values.pw)
    end)

    it("takes <Tab> for completion on a field with `completion`, <Down> to leave it", function()
      local r = open({
        { name = "f", label = "File", completion = "file" },
        { name = "g", label = "G" },
      })
      keys("<Tab>")
      assert.equals("f", r.surf:state().focus, "<Tab> is the completion key there")
      keys("<Down>")
      assert.equals("g", r.surf:state().focus)
    end)

    it("joins a paste that carries a newline into one row and keeps the button row", function()
      local r = open(THREE)
      local before = lines_of(r)
      api.nvim_buf_set_lines(r.surf.bufnr, 0, 1, false, { "some/path", "" })
      api.nvim_exec_autocmds("TextChanged", { buffer = r.surf.bufnr })
      local after = lines_of(r)
      assert.equals(#before, #after)
      assert.equals("some/path", after[1])
      assert.equals(before[#before], after[#after])

      api.nvim_buf_set_lines(r.surf.bufnr, 0, 1, false, { "one", "two", "three" })
      api.nvim_exec_autocmds("TextChanged", { buffer = r.surf.bufnr })
      assert.equals("one two three", lines_of(r)[1])
      assert.equals(#before, #lines_of(r))
    end)

    it("keeps what was typed into a row that was left before its TextChanged fired", function()
      -- Keys that arrive in one go (a macro, a paste with a tab in it) move the focus
      -- before the row they typed into got its `TextChanged`. The repair copy of that
      -- row was stale then, and the next layout repair wrote it back over the text.
      local r = open(THREE)
      api.nvim_buf_set_lines(r.surf.bufnr, 0, 1, false, { "typed" }) -- no TextChanged
      keys("<Tab>")
      assert.equals("b", r.surf:state().focus)
      api.nvim_buf_set_lines(r.surf.bufnr, 1, 2, false, { "pasted", "twice" })
      api.nvim_exec_autocmds("TextChanged", { buffer = r.surf.bufnr })
      assert.equals("typed", lines_of(r)[1])
      assert.equals("pasted twice", lines_of(r)[2])
    end)

    it("puts the layout right before it moves on, and lands on the intended row", function()
      local r = open(THREE)
      local before = lines_of(r)
      api.nvim_buf_set_lines(r.surf.bufnr, 0, 1, false, { "one", "two" }) -- no TextChanged
      keys("<Tab>")
      local after = lines_of(r)
      assert.equals(#before, #after)
      assert.equals("one two", after[1])
      assert.equals("b", r.surf:state().focus)
      assert.equals(2, api.nvim_win_get_cursor(r.surf.winid)[1])
    end)

    it("puts the rows back when a line was deleted", function()
      local r = open({
        { name = "a", label = "A", default = "keep" },
        { name = "b", label = "B", default = "this" },
      })
      api.nvim_buf_set_lines(r.surf.bufnr, 1, 2, false, {})
      api.nvim_exec_autocmds("TextChanged", { buffer = r.surf.bufnr })
      assert.equals("keep", lines_of(r)[1])
      assert.equals("this", lines_of(r)[2])
      assert.equals(4, #lines_of(r))
    end)
  end)

  describe("validation", function()
    local function digits(v)
      if v:match("^%d+$") then
        return true
      end
      return false, "digits only"
    end

    it("blocks submit while a required field is blank, and jumps to it", function()
      local r = open(THREE)
      keys("<Tab><Tab>")
      assert.equals("c", r.surf:state().focus)
      r.surf:submit()
      assert.is_nil(r.values, "nothing is handed on")
      assert.is_true(r.surf:is_valid())
      assert.equals("b", r.surf:state().focus, "the first field that fails")
      assert.same({ "✗ required" }, shown_errors(r))
    end)

    it("treats a blank value as empty, and takes the text of required_message", function()
      local r = open(THREE, { required_message = "must be filled" })
      type_into(r, 2, "   ")
      r.surf:submit()
      assert.same({ "✗ must be filled" }, shown_errors(r))
    end)

    it("shows the message of validate(), under the field, in the error highlight", function()
      local r = open({ { name = "n", label = "N", validate = digits }, { name = "m" } })
      type_into(r, 1, "12x")
      keys("<Tab>")
      assert.same({ "✗ digits only" }, shown_errors(r))
      local ns = api.nvim_get_namespaces().lib_kit_sheet
      local mark = api.nvim_buf_get_extmarks(r.surf.bufnr, ns, 0, -1, { details = true })[1]
      assert.equals(0, mark[2], "on the row of the field it belongs to")
      assert.equals("KitError", mark[4].virt_lines[1][1][2])
    end)

    it("grows the window by a row per message, and gives the rows back", function()
      local r = open({ { name = "n", label = "N", validate = digits }, { name = "m" } })
      local h = api.nvim_win_get_height(r.surf.winid)
      type_into(r, 1, "x")
      keys("<Tab>")
      assert.equals(h + 1, api.nvim_win_get_height(r.surf.winid))
      keys("<S-Tab>")
      type_into(r, 1, "12")
      assert.same({}, shown_errors(r))
      assert.equals(h, api.nvim_win_get_height(r.surf.winid))
    end)

    it("checks a field when it is left, not while it is first being typed into", function()
      local r = open({ { name = "n", label = "N", validate = digits }, { name = "m" } })
      type_into(r, 1, "x")
      assert.same({}, r.surf:state().errors, "still typing")
      keys("<Tab>")
      assert.same({ n = "digits only" }, r.surf:state().errors)
    end)

    it("checks a field that shows an error again on every edit", function()
      local r = open({ { name = "n", label = "N", validate = digits }, { name = "m" } })
      type_into(r, 1, "x")
      keys("<Tab><S-Tab>")
      assert.same({ n = "digits only" }, r.surf:state().errors)
      type_into(r, 1, "1")
      assert.same({}, r.surf:state().errors, "gone the moment it is right")
      type_into(r, 1, "1a")
      assert.same({}, r.surf:state().errors, "a field that is clean is checked when it is left")
      keys("<Tab>")
      assert.same({ n = "digits only" }, r.surf:state().errors)
    end)

    it("checks a `live` field on every edit from the first", function()
      local r = open({ { name = "n", label = "N", validate = digits, live = true } })
      type_into(r, 1, "x")
      assert.same({ n = "digits only" }, r.surf:state().errors)
    end)

    describe("a field that depends on another", function()
      -- A number that has to be free in the chosen area.
      local taken = { one = "100", two = "200" }

      ---@return table r
      local function open_number_and_area()
        local r
        r = open({
          {
            name = "n",
            label = "N",
            depends_on = "area",
            validate = function(v)
              local area = r.surf:state().values.area
              return taken[area] ~= v, "taken in " .. area
            end,
          },
          { name = "area", label = "Area", kind = "select", choices = { "one", "two" } },
        })
        return r
      end

      it("is checked again when the field it names changes", function()
        local r = open_number_and_area()
        type_into(r, 1, "100")
        keys("<Tab>") -- leaving the number: taken in `one`
        assert.same({ n = "taken in one" }, r.surf:state().errors)
        keys("l") -- area -> two: 100 is free there
        assert.same({}, r.surf:state().errors, "the message went with the area change")
        keys("h") -- area -> one: taken again
        assert.same({ n = "taken in one" }, r.surf:state().errors)
        assert.same({ "✗ taken in one" }, shown_errors(r))
      end)

      it("stays quiet while it is blank and untouched", function()
        local r = open({
          { name = "n", label = "N", required = true, depends_on = "area" },
          { name = "area", label = "Area", kind = "select", choices = { "one", "two" } },
        }, { focus = "area" })
        keys("l")
        assert.same({}, r.surf:state().errors, "no message before the number was filled in")
      end)

      it("is checked again when the text field it names is edited", function()
        local r
        r = open({
          { name = "a", label = "A" },
          {
            name = "b",
            label = "B",
            depends_on = { "a" },
            validate = function(v)
              return v ~= r.surf:state().values.a, "same as A"
            end,
          },
        })
        type_into(r, 2, "x")
        type_into(r, 1, "y")
        assert.same({}, r.surf:state().errors)
        type_into(r, 1, "x")
        assert.same({ b = "same as A" }, r.surf:state().errors)
        type_into(r, 1, "z")
        assert.same({}, r.surf:state().errors)
      end)
    end)

    it("does not flag a blank `live` field because of the TextChanged of opening", function()
      local r = open({ { name = "n", label = "N", required = true, live = true } })
      -- The writes that built the sheet fire one `TextChanged` once the loop runs.
      api.nvim_exec_autocmds("TextChanged", { buffer = r.surf.bufnr })
      assert.same({}, r.surf:state().errors)
      type_into(r, 1, "x")
      type_into(r, 1, "")
      assert.same({ n = "required" }, r.surf:state().errors, "but a real edit is")
    end)

    it("calls validate with the value on_submit will get (after expand_env)", function()
      vim.env.SHEET_SPEC_V = "42"
      local got
      local r = open({
        {
          name = "n",
          label = "N",
          expand_env = true,
          validate = function(v)
            got = v
            return true
          end,
        },
      })
      type_into(r, 1, "$SHEET_SPEC_V")
      r.surf:submit()
      vim.env.SHEET_SPEC_V = nil
      assert.equals("42", got)
    end)

    it("does not call validate for an empty optional field, and does for a required one", function()
      local calls = 0
      local function counting()
        calls = calls + 1
        return false, "no"
      end
      local r = open({ { name = "n", label = "N", validate = counting } })
      r.surf:submit()
      assert.equals(0, calls)
      assert.same({ n = "" }, r.values)

      local r2 = open({ { name = "n", label = "N", required = true, validate = counting } })
      r2.surf:submit()
      assert.equals(0, calls, "a blank required field fails before the validator")
      assert.same({ "✗ required" }, shown_errors(r2))
    end)

    it("rejects on a falsy first return, with its message or 'invalid'", function()
      local r = open({
        {
          name = "a",
          validate = function()
            return nil, "from nil"
          end,
        },
        {
          name = "b",
          validate = function()
            return false
          end,
        },
        {
          name = "c",
          validate = function()
            return "a truthy string"
          end,
        },
      })
      type_into(r, 1, "x")
      type_into(r, 2, "x")
      type_into(r, 3, "x")
      r.surf:submit()
      assert.same({ a = "from nil", b = "invalid" }, r.surf:state().errors)
    end)

    it("turns a validator that raises into a message instead of an error", function()
      local r = open({
        {
          name = "a",
          validate = function()
            error("boom", 0)
          end,
        },
      })
      type_into(r, 1, "x")
      r.surf:submit()
      assert.is_nil(r.values)
      assert.same({ "✗ boom" }, shown_errors(r))
    end)

    it("submits once every field is fine, with the keyed table", function()
      local r = open({
        { name = "n", label = "N", required = true, validate = digits },
        { name = "t", label = "T" },
      })
      type_into(r, 1, "x")
      r.surf:submit()
      assert.is_nil(r.values)
      type_into(r, 1, "977")
      type_into(r, 2, "title")
      r.surf:submit()
      assert.same({ n = "977", t = "title" }, r.values)
    end)

    it("also validates a select field's choice", function()
      local r = open({
        {
          name = "area",
          kind = "select",
          choices = { "ok", "bad" },
          validate = function(v)
            return v == "ok", "pick another"
          end,
        },
      })
      keys("<CR>")
      kit.chooser.move(1)
      kit.chooser.submit()
      r.surf:submit()
      assert.is_nil(r.values)
      assert.same({ area = "pick another" }, r.surf:state().errors)
    end)
  end)

  describe("driven from code", function()
    it("focus_field moves the focus by name or position and ignores an unknown one", function()
      local r = open(THREE)
      r.surf:focus_field("c")
      assert.equals("c", r.surf:state().focus)
      r.surf:focus_field(2)
      assert.equals("b", r.surf:state().focus)
      r.surf:focus_field("nope")
      assert.equals("b", r.surf:state().focus)
    end)

    it("validate() shows every message now, without submitting or moving the focus", function()
      local r = open({
        {
          name = "n",
          label = "N",
          default = "x",
          validate = function()
            return false, "no"
          end,
        },
        { name = "m", label = "M", required = true },
      })
      r.surf:focus_field("m")
      assert.is_false(r.surf:validate())
      assert.same({ n = "no", m = "required" }, r.surf:state().errors)
      assert.same({ "✗ no", "✗ required" }, shown_errors(r))
      assert.equals("m", r.surf:state().focus)
      assert.is_nil(r.values)

      type_into(r, 1, "")
      type_into(r, 2, "ok")
      assert.is_true(r.surf:validate())
      assert.same({}, r.surf:state().errors)
    end)

    it("works through kit.sync, like the other on_submit/on_cancel components", function()
      vim.defer_fn(function()
        for _, w in ipairs(api.nvim_list_wins()) do
          if api.nvim_win_get_config(w).relative ~= "" then
            api.nvim_set_current_win(w)
            api.nvim_buf_set_lines(api.nvim_win_get_buf(w), 1, 2, false, { "synced" })
            keys("<CR><CR><CR>")
          end
        end
      end, 20)
      local values, cancelled = kit.sync(kit.sheet, { fields = THREE }, 2000)
      assert.is_false(cancelled)
      assert.equals("synced", values.b)
    end)
  end)
end)
