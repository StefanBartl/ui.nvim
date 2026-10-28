-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.vim_ui` -- `vim.ui.select` / `vim.ui.input` through the kit: buttons for a short list, the chooser for a
--- medium one, the fallback for a long one; the contract of both functions; switching it off again.
--- The dialogs are answered through the kit's dialog hook, so no window opens.

local vim_ui = require("ui.vim_ui")
local kit = require("ui.kit")

describe("ui.vim_ui", function()
  local original_select, original_input
  local seen, answers

  --- Answer every kit dialog from `answers[kind]` (a function of `opts`, or a plain value).
  local function install_hook()
    kit.set_dialog_hook(function(kind, opts)
      seen[#seen + 1] = { kind = kind, opts = opts }
      local a = answers[kind]
      if a == nil then
        return false
      end
      if type(a) == "function" then
        return true, a(opts)
      end
      return true, a
    end)
  end

  --- Wait until `box.done`.
  local function settle(box)
    vim.wait(500, function()
      return box.done
    end, 5)
  end

  before_each(function()
    original_select, original_input = vim.ui.select, vim.ui.input
    seen, answers = {}, {}
    install_hook()
  end)

  after_each(function()
    vim_ui.disable()
    kit.set_dialog_hook(nil)
    vim.ui.select, vim.ui.input = original_select, original_input
  end)

  describe("enable / disable", function()
    it("is off by default and swaps both functions in and out", function()
      assert.is_false(vim_ui.is_enabled())
      vim_ui.enable()
      assert.is_true(vim_ui.is_enabled())
      assert.equals(vim_ui.select, vim.ui.select)
      assert.equals(vim_ui.input, vim.ui.input)
      vim_ui.disable()
      assert.is_false(vim_ui.is_enabled())
      assert.equals(original_select, vim.ui.select)
      assert.equals(original_input, vim.ui.input)
    end)

    it("takes over only what is asked for", function()
      vim_ui.enable({ input = false })
      assert.equals(vim_ui.select, vim.ui.select)
      assert.equals(original_input, vim.ui.input)
      vim_ui.enable({ select = false, input = true })
      assert.equals(original_select, vim.ui.select)
      assert.equals(vim_ui.input, vim.ui.input)
    end)

    it("enabling twice does not lose the function that was there first", function()
      vim_ui.enable()
      vim_ui.enable({ buttons_max = 2 })
      vim_ui.disable()
      assert.equals(original_select, vim.ui.select)
      assert.equals(original_input, vim.ui.input)
    end)

    it("leaves a function that somebody wrapped on top of ours", function()
      vim_ui.enable()
      local theirs = function() end
      vim.ui.select = theirs
      vim_ui.disable()
      assert.equals(theirs, vim.ui.select)
      assert.equals(original_input, vim.ui.input)
    end)

    it("ignores options of the wrong type and says so", function()
      local warned = {}
      local real_notify = vim.notify
      vim.notify = function(msg)
        warned[#warned + 1] = msg
      end
      vim_ui.enable({
        buttons_max = "many",
        fallback_select = 5,
        passthrough_kinds = "x",
        select = "yes",
      })
      vim.notify = real_notify
      assert.equals(4, #warned)
      local cfg = vim_ui.config()
      assert.equals(4, cfg.buttons_max)
      assert.is_nil(cfg.fallback_select)
      assert.same({}, cfg.passthrough_kinds)
      assert.is_true(cfg.select)
    end)
  end)

  describe("select", function()
    local function pick(items, opts)
      local box = {}
      vim.ui.select(items, opts, function(item, idx)
        box.done, box.item, box.idx = true, item, idx
      end)
      return box
    end

    it("asks a short list as buttons and hands back the original entry", function()
      vim_ui.enable()
      answers.confirm = 2
      local items = { { name = "a" }, { name = "b" }, { name = "c" } }
      local box = pick(items, {
        prompt = "Pick one:",
        format_item = function(item)
          return "Item " .. item.name
        end,
      })
      assert.is_nil(box.done, "the answer does not come before the call has returned")
      settle(box)
      assert.equals("confirm", seen[1].kind)
      assert.same({ "Item a", "Item b", "Item c" }, seen[1].opts.choices)
      assert.equals("Pick one", seen[1].opts.question, "the habitual trailing colon is dropped")
      assert.equals(1, seen[1].opts.default, "the first button is focused")
      assert.equals(items[2], box.item, "the entry itself, not its label")
      assert.equals(2, box.idx)
    end)

    it("answers (nil, nil) when the buttons are dismissed", function()
      vim_ui.enable()
      answers.confirm = function()
        return nil
      end
      local box = pick({ "a", "b" })
      settle(box)
      assert.is_true(box.done)
      assert.is_nil(box.item)
      assert.is_nil(box.idx)
    end)

    it("uses the chooser above buttons_max", function()
      vim_ui.enable()
      answers.select = 4
      local items = { "a", "b", "c", "d", "e", "f" }
      local box = pick(items, { prompt = "Which?" })
      settle(box)
      assert.equals("select", seen[1].kind)
      assert.equals("Which?", seen[1].opts.title)
      assert.equals("d", box.item)
      assert.equals(4, box.idx)
    end)

    it("dismissing the chooser answers (nil, nil)", function()
      vim_ui.enable()
      answers.select = function()
        return nil
      end
      local box = pick({ "a", "b", "c", "d", "e" })
      settle(box)
      assert.is_true(box.done)
      assert.is_nil(box.item)
      assert.is_nil(box.idx)
    end)

    it("takes a chooser instead of buttons when the button row does not fit", function()
      vim_ui.enable()
      answers.select = 1
      local wide = string.rep("w", vim.o.columns)
      local box = pick({ wide, "b" })
      settle(box)
      assert.equals("select", seen[1].kind)
      assert.equals(wide, box.item)
    end)

    it("hands a list longer than chooser_max to fallback_select, untouched", function()
      local got
      vim_ui.enable({
        chooser_max = 6,
        fallback_select = function(items, opts, on_choice)
          got = { items = items, opts = opts }
          on_choice(items[7], 7)
        end,
      })
      local items = { "a", "b", "c", "d", "e", "f", "g", "h" }
      local opts = { prompt = "Long" }
      local box = pick(items, opts)
      assert.is_true(box.done, "the fallback answers in its own time")
      assert.equals(items, got.items)
      assert.equals(opts, got.opts)
      assert.same({}, seen, "no kit dialog was opened")
      assert.equals("g", box.item)
    end)

    it("without fallback_select the function that was there goes on", function()
      local called
      vim.ui.select = function(items, _, on_choice)
        called = true
        on_choice(items[1], 1)
      end
      vim_ui.enable({ buttons_max = 0, chooser_max = 0 })
      local box = pick({ "a", "b" })
      assert.is_true(called)
      assert.equals("a", box.item)
    end)

    it("sends a passthrough kind to the fallback however short the list", function()
      local got
      vim_ui.enable({
        passthrough_kinds = { "codeaction" },
        fallback_select = function(items, _, on_choice)
          got = true
          on_choice(items[1], 1)
        end,
      })
      pick({ "a", "b" }, { kind = "codeaction" })
      assert.is_true(got)
      assert.same({}, seen)
    end)

    it("passes an empty list and a missing callback on", function()
      local calls = 0
      vim_ui.enable({
        fallback_select = function()
          calls = calls + 1
        end,
      })
      vim.ui.select({}, {}, function() end)
      vim.ui.select({ "a" }, {}, nil)
      assert.equals(2, calls)
      assert.same({}, seen)
    end)

    it(
      "hands the call to the fallback when the float cannot open, instead of answering cancelled",
      function()
        kit.set_dialog_hook(nil)
        local real_confirm = kit.confirm
        kit.confirm = function(opts)
          -- what the kit does when the float fails: cancel inside the call, return nil
          opts.on_answer(nil)
          return nil
        end
        local got
        vim_ui.enable({
          fallback_select = function(items, _, on_choice)
            got = true
            on_choice(items[2], 2)
          end,
        })
        local calls = {}
        vim.ui.select({ "a", "b" }, {}, function(item, idx)
          calls[#calls + 1] = { item, idx }
        end)
        vim.wait(50)
        kit.confirm = real_confirm
        assert.is_true(got, "the fallback took it")
        assert.same(
          { { "b", 2 } },
          calls,
          "answered once, with the fallback's answer, not with a cancel"
        )
      end
    )

    it("kit.select with respect_override does not loop through the provider", function()
      local calls = 0
      local inner = vim_ui.select
      vim_ui.enable()
      local counted = function(...)
        calls = calls + 1
        return inner(...)
      end
      vim.ui.select = counted
      answers.select = 1
      local box = {}
      kit.select({
        items = { "a", "b", "c", "d", "e" },
        respect_override = true,
        on_select = function(item, idx)
          box.done, box.item, box.idx = true, item, idx
        end,
      })
      settle(box)
      assert.equals(1, calls, "the provider was reached once")
      assert.equals("a", box.item)
    end)
  end)

  describe("input", function()
    local function ask(opts)
      local box = {}
      vim.ui.input(opts, function(value)
        box.done, box.value = true, value
      end)
      return box
    end

    it("asks through kit.input with prompt, default and completion", function()
      vim_ui.enable()
      answers.input = "typed"
      local box = ask({ prompt = "Name: ", default = "untitled", completion = "file" })
      assert.is_nil(box.done)
      settle(box)
      assert.equals("input", seen[1].kind)
      assert.equals("Name", seen[1].opts.prompt)
      assert.equals("untitled", seen[1].opts.default)
      assert.equals("file", seen[1].opts.completion)
      assert.equals("typed", box.value)
    end)

    it("answers nil when cancelled", function()
      vim_ui.enable()
      answers.input = function()
        return nil
      end
      local box = ask({ prompt = "Name" })
      settle(box)
      assert.is_true(box.done)
      assert.is_nil(box.value)
    end)

    it("hands the call to the previous vim.ui.input when the float cannot open", function()
      kit.set_dialog_hook(nil)
      local real_input = kit.input
      kit.input = function()
        return nil
      end
      local called
      vim.ui.input = function(_, on_confirm)
        called = true
        on_confirm("from the old one")
      end
      vim_ui.enable()
      local box = ask({ prompt = "x" })
      kit.input = real_input
      assert.is_true(called)
      assert.equals("from the old one", box.value)
    end)
  end)
end)
