-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- What a secret leaves behind in the last Insert run.
---
--- `secret = true` hides a prompt's text on screen and turns its undo off, but the
--- Insert run that typed it is also what Neovim keeps in the `.` register (and
--- `<C-r>.`) and in the redo buffer: after the prompt closed, `.` in any buffer
--- typed the password there. A prompt with a secret (and a sheet with a secret
--- field) overwrites that with an empty run once it is gone.
---
--- This runner never enters Insert mode for real, so what is pinned here is that
--- the scrub runs and what it does; the whole path, mode changes included, is
--- `ui_kit_input_ui_spec.lua`'s and `ui_kit_sheet_ui_spec.lua`'s.

local kit = require("ui.kit")
local input = require("ui.kit.input")
local api = vim.api

---@param k string
local function keys(k)
  api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "x", false)
end

local function close_floats()
  for _ = 1, 10 do
    local closed = false
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
        closed = true
      end
    end
    if not closed then
      return
    end
  end
end

describe("input.scrub_insert_traces", function()
  it("empties the . register and leaves . nothing to replay", function()
    vim.cmd("enew")
    vim.cmd("normal! ihunter2\27")
    assert.equals("hunter2", vim.fn.getreg("."), "an Insert run is what `.` holds")
    input.scrub_insert_traces()
    assert.is_true(
      vim.wait(1000, function()
        return vim.fn.getreg(".") == ""
      end, 10),
      "the register is empty once the scrub has run"
    )
    api.nvim_buf_set_lines(0, 0, -1, false, { "hello" })
    vim.cmd("normal! gg0.")
    assert.same({ "hello" }, api.nvim_buf_get_lines(0, 0, -1, false), "and . types nothing")
    assert.equals(1, #api.nvim_list_wins(), "no window is left behind")
    vim.cmd("silent! %bwipeout!")
  end)

  it("leaves no buffer and no hook behind", function()
    local bufs = #api.nvim_list_bufs()
    input.scrub_insert_traces()
    vim.wait(100)
    assert.equals(bufs, #api.nvim_list_bufs(), "the scratch buffer it types into is gone")
    -- (the group only exists while a scrub waits for the end of an Insert run)
    local ok, hooks = pcall(api.nvim_get_autocmds, { group = "lib_kit_input_scrub" })
    assert.is_true(not ok or #hooks == 0, "no InsertLeave hook is left waiting")
  end)
end)

describe("a prompt with a secret", function()
  local calls
  local real

  before_each(function()
    calls = 0
    real = input.scrub_insert_traces
    input.scrub_insert_traces = function()
      calls = calls + 1
    end
  end)

  after_each(function()
    input.scrub_insert_traces = real
    close_floats()
  end)

  it("scrubs the last Insert run when it is submitted, cancelled or goes back", function()
    kit.input({ secret = true, on_submit = function() end })
    keys("<CR>")
    assert.equals(1, calls, "submitted")

    kit.input({ secret = true, on_cancel = function() end })
    keys("<Esc>")
    assert.equals(2, calls, "cancelled")

    kit.input({ secret = true, on_back = function() end })
    keys("<S-Tab>")
    assert.equals(3, calls, "back")

    local surf = kit.input({ secret = true, on_cancel = function() end })
    api.nvim_win_close(surf.winid, true)
    assert.equals(4, calls, "closed from outside")
  end)

  it("scrubs even when the callback raises", function()
    local surf = kit.input({
      secret = true,
      on_cancel = function()
        error("boom")
      end,
    })
    surf:close() -- a close answers on_cancel, and that raises
    assert.equals(1, calls)
  end)

  it("leaves a prompt without a secret alone", function()
    kit.input({ on_submit = function() end })
    keys("<CR>")
    kit.input({ on_cancel = function() end })
    keys("<Esc>")
    assert.equals(0, calls)
  end)
end)

describe("a sheet with a secret field", function()
  local calls
  local real

  before_each(function()
    calls = 0
    real = input.scrub_insert_traces
    input.scrub_insert_traces = function()
      calls = calls + 1
    end
  end)

  after_each(function()
    input.scrub_insert_traces = real
    close_floats()
  end)

  it("scrubs the last Insert run when it is submitted or cancelled", function()
    local fields = { { name = "user" }, { name = "token", secret = true } }
    local surf = kit.sheet({ fields = fields, on_submit = function() end })
    surf:submit()
    assert.equals(1, calls, "submitted")

    surf = kit.sheet({ fields = fields, on_cancel = function() end })
    surf:cancel()
    assert.equals(2, calls, "cancelled")

    surf = kit.sheet({ fields = fields, on_cancel = function() end })
    api.nvim_win_close(surf.winid, true)
    assert.equals(3, calls, "closed from outside")
  end)

  it("leaves a sheet without one alone", function()
    local surf = kit.sheet({ fields = { { name = "user" } }, on_submit = function() end })
    surf:submit()
    surf = kit.sheet({ fields = { { name = "user" } }, on_cancel = function() end })
    surf:cancel()
    assert.equals(0, calls)
  end)
end)
