-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- The buffer a secret is typed into: what shuts the doors the mask does not cover.
---
--- The mask hides the secret on screen, but the buffer holds the real text, and three things
--- read a buffer without looking at the mask:
---
---   * Insert-mode completion. `<C-n>`/`<C-p>` (and `<C-x><C-n>`, `<C-x><C-p>`) complete from the
---     words of the buffer -- which is the secret -- list them in a popup in clear text and insert
---     the pick unmasked; with 'autocomplete' (Neovim 0.12) the popup opens by itself as one types.
---   * The re-mask itself: a candidate inserted from a popup is a change that fires
---     `TextChangedP`, which the hook did not listen for.
---   * A keystroke HUD (`ui.screenkey`) that shows what is typed: it looks for the buffer
---     variable `ui.kit.surface.SECRET_VAR`, which the prompt and a sheet with a secret field set.
---
--- This runner has no UI and never enters Insert mode by itself, so the keys are fed with
--- `nvim_feedkeys(..., "x")` -- an `A` starts a real Insert run, and the run ends when the keys do.
--- What a popup looks like on screen is `ui_kit_input_ui_spec.lua`'s (a child Neovim with a UI).

local kit = require("ui.kit")
local surface = require("ui.kit.surface")
local autocmd = require("lib.nvim.bindings.autocmd")
local api = vim.api

--- What the control prompt takes from the buffer, and the secret one must not.
local TYPED = "hunter2 hunter3 hun"

---@param keys string
local function feed(keys)
  api.nvim_feedkeys(api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

---@param surf table
---@return string
local function line_of(surf)
  return api.nvim_buf_get_lines(surf.bufnr, 0, 1, false)[1]
end

---@param surf table
---@return integer
local function mark_count(surf)
  local ns = api.nvim_create_namespace("lib_kit_input_secret_" .. surf.bufnr)
  return #api.nvim_buf_get_extmarks(surf.bufnr, ns, 0, -1, {})
end

local function close_floats()
  vim.cmd("stopinsert")
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
      pcall(api.nvim_win_close, w, true)
    end
  end
end

describe("a buffer a secret is typed into", function()
  -- The fed `A` would print `-- (insert) --` into the test output for every key, and a
  -- completion `match 1 of 2`.
  local showmode, shortmess
  before_each(function()
    showmode, shortmess = vim.o.showmode, vim.o.shortmess
    vim.o.showmode = false
    vim.opt.shortmess:append("c")
  end)
  after_each(function()
    close_floats()
    vim.o.showmode, vim.o.shortmess = showmode, shortmess
  end)

  describe("is marked (surface.SECRET_VAR)", function()
    it("for a secret prompt, and only for a secret one", function()
      local secret = kit.input({ secret = true, relative = "editor" })
      assert.is_true(surface.is_secret(secret.bufnr))
      assert.is_true(surface.is_secret(), "the prompt is the current buffer")
      assert.equals(true, vim.b[secret.bufnr][surface.SECRET_VAR], "the variable itself")
      local plain = kit.input({ relative = "editor" })
      assert.is_false(surface.is_secret(plain.bufnr))
      assert.is_false(surface.is_secret(), "the plain prompt is the current buffer now")
    end)

    it("for a sheet with a secret field, and not for one without", function()
      local noted = kit.sheet({
        fields = { { name = "user" }, { name = "token", secret = true } },
        relative = "editor",
        on_submit = function() end,
      })
      assert.is_true(surface.is_secret(noted.bufnr), "one secret row marks the whole sheet")
      noted:cancel()
      local open = kit.sheet({
        fields = { { name = "user" }, { name = "city" } },
        relative = "editor",
        on_submit = function() end,
      })
      assert.is_false(surface.is_secret(open.bufnr))
      open:cancel()
    end)

    it("and the question never raises", function()
      assert.is_false(surface.is_secret(999999), "no such buffer")
      assert.is_false(surface.is_secret(nil), "a normal buffer")
      assert.is_false(surface.is_secret(0))
      assert.is_nil(surface.mark_secret(999999), "marking one that is gone is a no-op")
    end)

    it("is a name the other copy of the kit uses too", function()
      -- `ui.screenkey` is one HUD for both: lib.nvim's frozen copy of the kit marks its
      -- secret prompts with this very name (the drift check keeps the two files alike).
      assert.equals("ui_kit_secret", surface.SECRET_VAR)
    end)
  end)

  describe("offers no completion", function()
    -- The keys that complete from the words of the buffer. `<C-x><C-n>` and `<C-x><C-p>` do it
    -- whatever 'complete' says.
    local KEYS = { "<C-n>", "<C-p>", "<C-x><C-n>", "<C-x><C-p>" }

    for _, keys in ipairs(KEYS) do
      it(
        ("on %s: a plain prompt takes a word out of the buffer, a secret one does not"):format(keys),
        function()
          -- The control first: without it a changed runner that makes `A` do nothing would pass.
          local plain = kit.input({ default = TYPED, relative = "editor" })
          feed("A" .. keys)
          assert.is_true(line_of(plain) ~= TYPED, "the plain prompt completed: " .. line_of(plain))
          plain:close()

          local secret = kit.input({ secret = true, default = TYPED, relative = "editor" })
          feed("A" .. keys)
          assert.equals(TYPED, line_of(secret), "nothing was inserted into the secret")
          secret:close()
        end
      )
    end

    it("in a sheet with a secret field either, whichever row it is in", function()
      local sheet = kit.sheet({
        fields = {
          { name = "token", secret = true, default = TYPED },
          { name = "note", default = TYPED },
        },
        relative = "editor",
        on_submit = function() end,
      })
      for focus = 1, 2 do
        sheet:focus_field(focus)
        feed("A<C-n>")
        feed("A<C-x><C-n>")
        assert.equals(
          TYPED,
          api.nvim_buf_get_lines(sheet.bufnr, focus - 1, focus, false)[1],
          ("row %d took no word of the sheet"):format(focus)
        )
      end
      sheet:cancel()
    end)

    it("in a sheet without a secret field, the words are still offered", function()
      -- The control for the one above: only a secret one is closed.
      local sheet = kit.sheet({
        fields = { { name = "note", default = TYPED } },
        relative = "editor",
        on_submit = function() end,
      })
      feed("A<C-n>")
      assert.is_true(api.nvim_buf_get_lines(sheet.bufnr, 0, 1, false)[1] ~= TYPED)
      sheet:cancel()
    end)

    describe("except in the popup the prompt opened itself", function()
      -- A popup of `opts.completion` (`<Tab>`) is cycled with <C-n>/<C-p>. This runner shows no
      -- popup, so `pumvisible()` and the feed are stubbed; the real popup is in the UI spec.
      ---@param pum integer
      ---@param key string
      ---@return string[]  # the keys fed to Neovim
      local function press(pum, key)
        local fed = {}
        local pumvisible, feedkeys = vim.fn.pumvisible, api.nvim_feedkeys
        vim.fn.pumvisible = function()
          return pum
        end
        api.nvim_feedkeys = function(keys)
          fed[#fed + 1] = keys
        end
        local ok, err = pcall(function()
          vim.fn.maparg(key, "i", false, true).callback()
        end)
        vim.fn.pumvisible, api.nvim_feedkeys = pumvisible, feedkeys
        assert(ok, err)
        return fed
      end

      it(
        "passes <C-n> and <C-p> to it while it is open, and swallows them when it is not",
        function()
          kit.input({ secret = true, completion = "file", relative = "editor" })
          assert.same({ "\14" }, press(1, "<C-n>"))
          assert.same({ "\16" }, press(1, "<C-p>"))
          assert.same({}, press(0, "<C-n>"))
          assert.same({}, press(0, "<C-p>"))
        end
      )

      it("keeps <C-p> that goes back, and passes it on while the popup is open", function()
        local went_back = 0
        kit.input({
          secret = true,
          relative = "editor",
          on_back = function()
            went_back = went_back + 1
          end,
        })
        assert.same({ "\16" }, press(1, "<C-p>"))
        assert.equals(0, went_back)
        press(0, "<C-p>")
        assert.equals(1, went_back, "with no popup <C-p> still steps back")
      end)
    end)

    it("and <C-x> is a key that does nothing at all", function()
      local secret = kit.input({ secret = true, default = TYPED, relative = "editor" })
      assert.equals("<Nop>", vim.fn.maparg("<C-x>", "i", false, true).rhs)
      secret:close()
      local plain = kit.input({ default = TYPED, relative = "editor" })
      assert.equals("", vim.fn.maparg("<C-x>", "i"), "a plain prompt leaves it to Neovim")
      plain:close()
    end)

    if vim.fn.exists("&autocomplete") == 1 then
      --- The value the buffer really has: its own, else the global one (`vim.bo` and
      --- `nvim_get_option_value` say nil for a global-local option that is not set locally).
      ---@param surf table
      ---@return boolean
      local function autocomplete_of(surf)
        return api.nvim_buf_call(surf.bufnr, function()
          return vim.o.autocomplete
        end)
      end

      it("and 'autocomplete' is off for the buffer, whatever the global value is", function()
        local was = vim.go.autocomplete
        vim.go.autocomplete = true
        local ok, err = pcall(function()
          local plain = kit.input({ relative = "editor" })
          assert.is_true(autocomplete_of(plain), "a plain prompt follows the global one")
          plain:close()
          local secret = kit.input({ secret = true, relative = "editor" })
          assert.is_false(autocomplete_of(secret))
          secret:close()
        end)
        vim.go.autocomplete = was
        assert(ok, err)
      end)
    end
  end)

  describe("is masked again after", function()
    it("a change made while a popup is open (TextChangedP)", function()
      local secret = kit.input({ secret = true, relative = "editor" })
      assert.equals(0, mark_count(secret))
      api.nvim_buf_set_lines(secret.bufnr, 0, -1, false, { "hunter22" })
      api.nvim_exec_autocmds("TextChangedP", { buffer = secret.bufnr })
      assert.equals(8, mark_count(secret), "a candidate put in by the popup is masked too")
    end)

    it("each kind of change in turn", function()
      local secret = kit.input({ secret = true, relative = "editor" })
      for i, event in ipairs({ "TextChangedI", "TextChanged", "TextChangedP" }) do
        api.nvim_buf_set_lines(secret.bufnr, 0, -1, false, { ("x"):rep(i + 2) })
        api.nvim_exec_autocmds(event, { buffer = secret.bufnr })
        assert.equals(i + 2, mark_count(secret), event)
      end
    end)
  end)

  describe("keeps its re-mask hook to itself", function()
    -- The hook was in a group named after the buffer: a group and a record per prompt, none of
    -- them ever removed (lib.nvim's `groups`/`group_names` caches and its record list grew with
    -- every secret prompt that was ever opened, and `forget_group` rescanned the list).
    -- A buffer-local autocmd needs no group and goes with its buffer.
    it("buffer-local, in no group", function()
      local secret = kit.input({ secret = true, relative = "editor" })
      local found = {}
      for _, a in ipairs(api.nvim_get_autocmds({ buffer = secret.bufnr })) do
        if a.desc == "ui.kit.input: re-mask secret input" then
          found[#found + 1] = a.event
          assert.is_nil(a.group_name, a.event .. " is in no group")
        end
      end
      table.sort(found)
      assert.same({ "TextChanged", "TextChangedI", "TextChangedP" }, found)
    end)

    it("and leaves no group and no record behind when it closes", function()
      local before = #autocmd.registered()
      local bufnrs = {}
      for i = 1, 5 do
        local secret = kit.input({ secret = true, relative = "editor" })
        bufnrs[i] = secret.bufnr
        secret:close()
      end
      assert.equals(before, #autocmd.registered(), "no record for a throwaway hook")
      for _, b in ipairs(bufnrs) do
        assert.is_false(api.nvim_buf_is_valid(b), "the buffer is wiped, and the hook with it")
        assert.is_false(
          (pcall(api.nvim_get_autocmds, { group = "lib_kit_input_" .. b })),
          ("no augroup lib_kit_input_%d is left"):format(b)
        )
      end
    end)
  end)
end)
