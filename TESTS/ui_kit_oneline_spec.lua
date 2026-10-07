-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- A prompt's line and a button's label are ONE line of text.
---
--- `nvim_buf_set_lines` refuses a string with a newline in it, and a prompt's
--- `default` (a field of a `.case.json` that carries a multi-line note, say) or a
--- button's label (a `kit.confirm` choice) reach it unchanged: the call raised,
--- and the scratch buffer `make_scratch` had just made stayed behind, never shown.
--- `kit.sheet` always flattened its own (`one_line`); the single-line components
--- now do the same, the answer a button hands back staying what the caller gave.

local kit = require("ui.kit")
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

---@param bufnr integer
---@return string[]
local function lines_of(bufnr)
  return api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

describe("a one-line component given text with newlines", function()
  after_each(close_floats)

  describe("kit.input's default", function()
    for name, default in pairs({
      ["a newline"] = "a\nb",
      ["a CRLF"] = "a\r\nb",
      ["several newlines"] = "a\n\n\nb",
    }) do
      it("is flattened for " .. name, function()
        local before = #api.nvim_list_bufs()
        local surf = kit.input({ default = default })
        assert.is_not_nil(surf, "the prompt opens instead of raising")
        assert.same({ "a b" }, lines_of(surf.bufnr))
        surf:close()
        assert.equals(before, #api.nvim_list_bufs(), "and no buffer is left behind")
      end)
    end

    it("is flattened above a button row too, and a number is text", function()
      local surf = kit.input({
        default = "x\ny",
        buttons = { { id = "submit", label = "OK" } },
      })
      assert.equals("x y", lines_of(surf.bufnr)[1])
      assert.equals(2, #lines_of(surf.bufnr))
      local num = kit.input({ default = 5 })
      assert.same({ "5" }, lines_of(num.bufnr))
    end)

    it("is what a kit.form field opens with, and what on_submit gets back", function()
      local got
      local surf = kit.form({
        fields = { { name = "note", default = "n1\nn2" } },
        on_submit = function(v)
          got = v
        end,
      })
      assert.is_not_nil(surf)
      assert.same({ "n1 n2" }, lines_of(surf.bufnr))
      keys("<CR>")
      assert.same({ note = "n1 n2" }, got)
    end)
  end)

  describe("a button's label", function()
    it("is flattened in a kit.input button row, and the buttons still work", function()
      local submitted
      local surf = kit.input({
        buttons = { { id = "skip", label = "Sk\nip" }, { id = "submit", label = "O\r\nK" } },
        on_submit = function(v)
          submitted = v
        end,
      })
      assert.is_not_nil(surf, "the prompt opens instead of raising")
      assert.equals(2, #lines_of(surf.bufnr))
      assert.is_truthy(lines_of(surf.bufnr)[2]:find("[ Sk ip ]  [ O K ]", 1, true))
      keys("<CR>")
      assert.equals("", submitted)
    end)

    it("is flattened in kit.confirm, and the answer is the choice as it was given", function()
      local before = #api.nvim_list_bufs()
      local answered
      local confirm = require("ui.kit.confirm")
      local surf = confirm.open({
        question = "Sure?",
        choices = { "a\nb", "c" },
        on_answer = function(v)
          answered = v
        end,
      })
      assert.is_not_nil(surf, "the dialog opens instead of raising")
      local row = lines_of(surf.bufnr)
      assert.is_truthy(row[#row]:find("[ a b ]  [ c ]", 1, true), "drawn on one line")
      keys("<CR>")
      assert.equals("a\nb", answered, "the answer is the caller's own string")
      assert.equals(before, #api.nvim_list_bufs())
    end)

    it("is flattened in a kit.sheet's button row", function()
      local surf = kit.sheet({
        submit_label = "Go\nnow",
        cancel_label = "No",
        fields = { { name = "a" } },
        on_submit = function() end,
      })
      assert.is_not_nil(surf)
      local row = lines_of(surf.bufnr)
      assert.is_truthy(row[#row]:find("[ Go now ]  [ No ]", 1, true))
    end)
  end)
end)
