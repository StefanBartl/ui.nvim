-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- A NUL byte in caller text must not keep a kit component from opening.
---
--- A NUL in a Lua string reaches `vim.fn` as a Blob, and `strdisplaywidth()`, `strchars()`,
--- `strcharpart()` and `split()` raise E976 on it -- out of the width every component takes of
--- what it is about to show. Only `kit.input` knew (its secret mask and its title); a case title
--- read from a `.case.json` with a `\u0000` in it kept the whole `kit.select` list from opening,
--- and a NUL in a confirm question, a menu label, a toast, a sheet's label or a button's label did
--- the same to theirs. The text is measured as `lib.lua.strings.core.nul_safe` makes it -- an SOH,
--- one byte and two cells like the `^@` a NUL is drawn as -- and what a caller is handed back stays
--- its own string.

local kit = require("ui.kit")
local api = vim.api

local nul = string.char(0)

vim.o.showmode = false

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

--- Open `open()` and answer with the surface; the failure names where it was raised.
---@param what string
---@param open fun(): any
---@return any
local function opens(what, open)
  local ok, surf = pcall(open)
  assert.is_true(ok, what .. " opens instead of raising: " .. tostring(surf))
  assert.is_not_nil(surf, what .. " gives a surface")
  return surf
end

--- Width of the window `open()` makes.
---@param open fun(): any
---@return integer
local function width_of(open)
  local surf = open()
  local width = api.nvim_win_get_width(surf.winid)
  close_floats()
  return width
end

describe("a NUL byte in caller text", function()
  after_each(function()
    require("ui.kit.confirm").close()
    require("ui.kit.menu").close()
    require("ui.kit.chooser").close()
    pcall(kit.chip.unmount, "ui_kit_nul_spec")
    close_floats()
  end)

  describe("in a list or a panel (the width make_scratch takes)", function()
    it("keeps kit.select from failing on one item, and the item keeps its text", function()
      local surf = opens("a select list", function()
        return kit.select({
          selection = { { t = "a" }, { t = "b" .. nul .. "c" } },
          format_item = function(e)
            return e.t
          end,
          on_select = function() end,
        })
      end)
      local text = table.concat(lines_of(surf.bufnr), "\n")
      assert.is_truthy(text:find("b" .. nul .. "c", 1, true), "the row holds the caller's text")
    end)

    it("is two cells wide in a kit.viewer, as the ^@ it is drawn as", function()
      local function viewer(line)
        return function()
          return kit.viewer({ lines = { line }, relative = "editor" })
        end
      end
      opens("a viewer", viewer("a" .. nul .. "b"))
      assert.equals(
        width_of(viewer("axxb")),
        width_of(viewer("a" .. nul .. "b")),
        "as wide as four plain characters"
      )
    end)

    it("opens a kit.note", function()
      opens("a note", function()
        return kit.note({ message = "a" .. nul .. "b", title = "t" .. nul })
      end)
    end)
  end)

  describe("in kit.confirm", function()
    local confirm = require("ui.kit.confirm")

    it("opens with a NUL in the question, as wide as the same question with two letters", function()
      local function dialog(question)
        return function()
          return kit.confirm({ question = question, on_answer = function() end })
        end
      end
      opens("a confirm dialog", dialog("Delete case a" .. nul .. "b?"))
      assert.equals(
        width_of(dialog("Delete case axxb?")),
        width_of(dialog("Delete case a" .. nul .. "b?"))
      )
    end)

    it("draws a button label with a NUL, and answers with the caller's own string", function()
      local answered
      local surf = opens("a confirm dialog", function()
        return kit.confirm({
          question = "Sure?",
          choices = { "Go" .. nul, "No" },
          on_answer = function(v)
            answered = v
          end,
        })
      end)
      local row = lines_of(surf.bufnr)
      assert.is_truthy(row[#row]:find("[ Go\1 ]  [ No ]", 1, true), "drawn with the SOH")
      confirm.confirm()
      assert.equals("Go" .. nul, answered, "the answer is what was given")
    end)
  end)

  describe("in the prompts", function()
    it("measures a live_input's title: the box is as wide as the title is drawn", function()
      local surf = opens("a live_input", function()
        return kit.live_input({
          title = string.rep("a", 50) .. nul,
          relative = "editor",
          on_change = function() end,
        })
      end)
      assert.equals(52, api.nvim_win_get_width(surf.winid), "50 letters and the two cells of ^@")
    end)

    it("opens a kit.input whose button has a NUL in its label", function()
      local surf = opens("a prompt", function()
        return kit.input({
          relative = "editor",
          buttons = { { id = "submit", label = "Go" .. nul .. "x" } },
        })
      end)
      local row = lines_of(surf.bufnr)[2]
      assert.is_truthy(row:find("[ Go\1x ]", 1, true), "drawn with the SOH")
    end)
  end)

  describe("in kit.sheet", function()
    local function sheet(opts)
      return function()
        return kit.sheet(vim.tbl_extend("force", {
          fields = { { name = "x", label = "X" } },
          relative = "editor",
          on_submit = function() end,
        }, opts))
      end
    end

    it("opens with a NUL in the title", function()
      opens("a sheet", sheet({ title = "a" .. nul .. "b" }))
    end)

    it("draws a label with a NUL in the status column, where a v:lua call returns it", function()
      -- The label is not text of the buffer but the return value of `v:lua`, and a NUL in that is
      -- a Blob again: E976 on every redraw, even with the width measured safely. It is cleaned at
      -- the source.
      local surf =
        opens("a sheet", sheet({ fields = { { name = "x", label = "X" .. nul .. "Y" } } }))
      local drawn = api.nvim_eval_statusline("%!v:lua.require'ui.kit.sheet'.column()", {
        winid = surf.winid,
        use_statuscol_lnum = 1,
      })
      assert.is_truthy(
        drawn.str:find("X\1Y", 1, true),
        "the label is drawn: " .. vim.inspect(drawn.str)
      )
    end)

    it("draws the buttons and the message of a field with a NUL in them", function()
      local surf = opens(
        "a sheet",
        sheet({
          submit_label = "Go" .. nul,
          fields = {
            {
              name = "x",
              label = "X",
              validate = function()
                return false, "bad" .. nul .. string.rep("m", 80)
              end,
            },
          },
        })
      )
      local row = lines_of(surf.bufnr)
      assert.is_truthy(row[#row]:find("[ Go\1 ]", 1, true), "the button, with the SOH")
      local ok, err = pcall(surf.validate, surf)
      assert.is_true(ok, "the message is clipped instead of raising: " .. tostring(err))
    end)
  end)

  describe("in kit.menu", function()
    it("opens with a NUL in a label", function()
      opens("a menu", function()
        return kit.menu({
          relative = "editor",
          items = { { label = "a" .. nul .. "b", action = function() end } },
        })
      end)
    end)

    it("opens with a NUL in the title", function()
      opens("a menu", function()
        return kit.menu({
          relative = "editor",
          title = "a" .. nul .. "b",
          items = { { label = "ab", action = function() end } },
        })
      end)
    end)
  end)

  describe("in kit.toast", function()
    it("opens with a NUL in the message", function()
      opens("a toast", function()
        return kit.toast({ message = "a" .. nul .. "b" })
      end)
    end)

    it("wraps a long message that holds NULs", function()
      local surf = opens("a toast", function()
        return kit.toast({ message = string.rep("ab" .. nul, 60) })
      end)
      assert.is_true(#lines_of(surf.bufnr) > 1, "wrapped to the width of the toast")
    end)
  end)

  describe("in kit.chip", function()
    it("mounts a chip whose text has a NUL in it", function()
      local ok, err = pcall(kit.chip.mount, { id = "ui_kit_nul_spec", text = "a" .. nul .. "b" })
      assert.is_true(ok, "mount does not raise: " .. tostring(err))
      assert.same({ "ui_kit_nul_spec" }, kit.chip.active(), "and the chip is up")
    end)
  end)
end)
