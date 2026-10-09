-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.screenkey` -- the in-editor keystroke HUD. Drives real keys via
--- `nvim_feedkeys` (same approach TESTS/macro_counter_spec.lua uses for its
--- own `vim.on_key()`-based module) rather than mocking `vim.on_key`/
--- `keytrans`. Unlike that module's own hook, `ui.screenkey.on_key()`
--- defers its work behind `vim.schedule()` (see its own doc comment for
--- why), so every assertion below waits for the scheduled work to land
--- rather than reading state synchronously after `feed()`.

local screenkey = require("ui.screenkey")

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

--- One `nvim_feedkeys()` call per entry, not one batched string: fed
--- together, repeated identical normal-mode keys (e.g. "jjj") collapse into
--- a single `vim.on_key()` invocation under Nvim's own typeahead handling
--- when there is no real terminal between keystrokes -- a headless-feedkeys
--- artifact, not something a real keyboard ever produces (found live,
--- writing this test: `vim.on_key()` fired 3 times for three separate
--- `feed("j")` calls, but only once for one `feed("jjj")` call). Separate
--- calls are what makes each key its own genuine input event again.
---@param keys string[]
local function feed_each(keys)
  for _, k in ipairs(keys) do
    feed(k)
  end
end

---@return string
local function current_text()
  local surf = screenkey.surface()
  if not surf or not surf:is_valid() then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(surf.bufnr, 0, -1, false)
  return lines[1] or ""
end

describe("ui.screenkey", function()
  -- Every test enables/feeds/asserts against the same module-level
  -- singleton (there is only one screenkey HUD, same as `ui.contextmenu`'s
  -- `enabled` flag) -- disabling after each test is what keeps them
  -- independent instead of leaking the `vim.on_key()` hook and a stale
  -- float into the next one.
  after_each(function()
    screenkey.disable()
    screenkey.setup({ labels = {}, join_chars = false, width = 40 })
  end)

  it("is off by default -- no float, no hook", function()
    assert.is_false(screenkey.is_enabled())
    assert.is_nil(screenkey.surface())
  end)

  it("enable()/disable()/toggle() flip the on/off state", function()
    screenkey.enable()
    assert.is_true(screenkey.is_enabled())

    screenkey.disable()
    assert.is_false(screenkey.is_enabled())

    local now_on = screenkey.toggle()
    assert.is_true(now_on)
    assert.is_true(screenkey.is_enabled())

    local now_off = screenkey.toggle()
    assert.is_false(now_off)
    assert.is_false(screenkey.is_enabled())
  end)

  it("renders nothing while disabled, even as keys are fed", function()
    feed("j")
    vim.wait(50)
    assert.is_nil(screenkey.surface())
  end)

  it("shows a keytrans'd key in a float once enabled", function()
    screenkey.enable()
    feed("j")
    vim.wait(200, function()
      return screenkey.surface() ~= nil
    end)

    local surf = screenkey.surface()
    assert.is_not_nil(surf)
    assert.is_true(surf:is_valid())
    assert.equals("j", current_text())
  end)

  it("formats a non-printable key via keytrans(), not the raw byte sequence", function()
    screenkey.enable()
    feed("<Esc>")
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    assert.equals("<Esc>", current_text())
  end)

  it("shows a configured label instead of the keytrans() name", function()
    screenkey.setup({ labels = { ["<Esc>"] = "Esc" } })
    screenkey.enable()
    feed("<Esc>")
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    assert.equals("Esc", current_text())
  end)

  it("matches a label written in mapping spelling (<C-w>) against keytrans()'s <C-W>", function()
    -- keytrans() hands on_key() `<C-W>`, upper-case; a host writing the
    -- label the way it writes a mapping (`<C-w>`) used to never match.
    screenkey.setup({ labels = { ["<C-w>"] = "win", ["<"] = "lt" } })
    screenkey.enable()
    -- Both are incomplete Normal-mode commands, so feedkeys("x") appends an
    -- <Esc> after each; the assertion looks for the labels, not exact text.
    feed_each({ "<C-w>", "<" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    local text = current_text()
    assert.is_true(text:find("win", 1, true) ~= nil, text)
    assert.is_true(text:find("lt", 1, true) ~= nil, text)
    assert.is_nil(text:find("<C-W>", 1, true), text)
    assert.is_nil(text:find("<lt>", 1, true), text)
  end)

  -- Normal-mode motions rather than letters that would enter Insert mode:
  -- feedkeys() in "x" mode appends an <Esc> when a call leaves Insert mode,
  -- which would land in the HUD as a key nobody pressed.
  it("join_chars runs plain characters together, one chip per typed word", function()
    screenkey.setup({ join_chars = true })
    screenkey.enable()
    feed_each({ "h", "j", "k" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    assert.equals("hjk", current_text())
  end)

  it("join_chars spells a short repeat out, keeps a held key as key\xC3\x97N", function()
    screenkey.setup({ join_chars = true })
    screenkey.enable()
    feed_each({ "h", "j", "j", "k" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)
    assert.equals("hjjk", current_text())

    screenkey.disable()
    screenkey.enable()
    feed_each({ "h", "j", "j", "j", "j", "k" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)
    assert.equals("h j\xC3\x974 k", current_text())
  end)

  it("clips an overlong joined run by characters, never inside a multi-byte glyph", function()
    -- U+2423 as the Space label: three bytes, one column. Width 8 leaves 6
    -- columns inside the border; a byte clip of "hj<U+2423>hj..." could land
    -- between those three bytes.
    local space = "\xE2\x90\xA3"
    screenkey.setup({ join_chars = true, width = 8, labels = { ["<Space>"] = space } })
    screenkey.enable()
    feed_each({ "h", "j", "<Space>", "h", "j", "<Space>", "h", "j", "<Space>", "h" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    local text = current_text()
    assert.is_true(vim.fn.strdisplaywidth(text) <= 6, text)
    assert.equals(vim.fn.strchars(text), vim.fn.strchars(text, true), "valid UTF-8, no stray bytes")
    assert.is_true(text:sub(-1) == "h", text)
    -- Those three are properties, and a byte clip satisfies all of them: the
    -- last six bytes of the run are `hj`, the glyph and `h` -- four columns,
    -- ending in `h`, on a glyph boundary. Only the exact tail tells that from
    -- "the newest six characters, glyphs whole".
    assert.equals("j" .. space .. "hj" .. space .. "h", text)
  end)

  it("clips an overlong joined run to the longest tail that fits, not a shorter one", function()
    -- Width 8 leaves 6 columns; ten distinct motions form one ten-character
    -- run. The clip must keep exactly the newest six (a search that stops
    -- early or drops one too many would show five or fewer).
    screenkey.setup({ join_chars = true, width = 8 })
    screenkey.enable()
    feed_each({ "h", "j", "k", "l", "h", "j", "k", "l", "h", "j" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    assert.equals("hjklhj", current_text())
  end)

  it("join_chars keeps a keycode apart from the characters around it", function()
    screenkey.setup({ join_chars = true })
    screenkey.enable()
    feed_each({ "h", "j", "<Esc>", "k" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    assert.equals("hj <Esc> k", current_text())
  end)

  it("join_chars lets a labelled keycode join the run", function()
    screenkey.setup({ join_chars = true, labels = { ["<Esc>"] = "!" } })
    screenkey.enable()
    feed_each({ "h", "<Esc>", "j" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    assert.equals("h!j", current_text())
  end)

  it(
    "rejects a non-table labels and a non-boolean join_chars, keeping the current values",
    function()
      screenkey.setup({ labels = "nope", join_chars = "yes" })
      assert.equals(2, #screenkey.health_issues())
    end
  )

  it("leaves a raw terminal code (<t_..>) out of the HUD", function()
    screenkey.enable()
    -- K_SPECIAL KS_EXTRA + a byte no key name owns: keytrans() renders it as <t_..>.
    feed_each({ "j", "\128\253g", "k" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    local text = current_text()
    assert.is_nil(text:find("<t_", 1, true), text)
  end)

  it("rejects a label containing a newline instead of crashing render() on it", function()
    -- nvim_buf_set_lines errors on any line with an embedded "\n"; an
    -- unvalidated label used to reach it via surface.open()'s own initial
    -- set_lines, breaking the HUD on the very first keystroke that used it.
    screenkey.setup({ labels = { ["<Esc>"] = "a\nb" } })
    local issues = screenkey.health_issues()
    assert.equals(1, #issues)
    assert.is_true(issues[1]:find("<Esc>", 1, true) ~= nil, issues[1])

    screenkey.enable()
    feed("<Esc>")
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    assert.equals("<Esc>", current_text())
  end)

  it("collapses consecutive presses of the same key into key\xC3\x97N", function()
    screenkey.enable()
    feed_each({ "j", "j", "j" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    local text = current_text()
    assert.is_true(text:find("j", 1, true) ~= nil, text)
    assert.is_true(text:find("3", 1, true) ~= nil, text)
    -- One collapsed entry, not three separate "j" chips.
    assert.is_nil(text:find("j j j", 1, true), text)
  end)

  it("starts a new entry once a different key interrupts a repeat run", function()
    screenkey.enable()
    feed_each({ "j", "j", "k" })
    vim.wait(200, function()
      return current_text() ~= ""
    end)

    local text = current_text()
    assert.is_true(text:find("j", 1, true) ~= nil, text)
    assert.is_true(text:find("k", 1, true) ~= nil, text)
  end)

  it("closes the float and stops updating once disabled", function()
    screenkey.enable()
    feed("j")
    vim.wait(200, function()
      return screenkey.surface() ~= nil
    end)

    screenkey.disable()
    assert.is_nil(screenkey.surface())

    feed("k")
    vim.wait(50)
    assert.is_nil(screenkey.surface())
  end)

  it("auto-clears the float after fade_ms of inactivity", function()
    screenkey.setup({ fade_ms = 80 })
    screenkey.enable()
    feed("j")
    vim.wait(200, function()
      return screenkey.surface() ~= nil
    end)
    assert.is_not_nil(screenkey.surface())

    vim.wait(500, function()
      return screenkey.surface() == nil
    end)
    assert.is_nil(screenkey.surface())
  end)

  it("setup() rejects a wrongly-typed value and records it for :checkhealth", function()
    screenkey.setup({ width = true })
    local issues = screenkey.health_issues()
    assert.equals(1, #issues)
    assert.is_true(issues[1]:find("width", 1, true) ~= nil, issues[1])

    -- A subsequent valid call clears the rejected-value list.
    screenkey.setup({ width = 40 })
    assert.same({}, screenkey.health_issues())
  end)

  it("setup() rejects max_entries below its minimum", function()
    screenkey.setup({ max_entries = 0 })
    local issues = screenkey.health_issues()
    assert.equals(1, #issues)
    assert.is_true(issues[1]:find("max_entries", 1, true) ~= nil, issues[1])

    screenkey.setup({ max_entries = 30 })
  end)
end)

--- A keystroke HUD that shows what is typed into a password prompt is a leak, and it is on
--- exactly when somebody records a demo. The prompt (`kit.input` with `secret = true`) and a
--- sheet with a secret field mark their buffer (`ui.kit.surface.SECRET_VAR`); the HUD leaves the
--- keys typed into a marked buffer out. A sheet is marked as a whole: there is no telling which
--- row a key was meant for.
---
--- Real keys again. `A` starts an Insert run that the fed keys type into (this runner never
--- enters Insert mode on its own), and the run ends with the keys.
describe("ui.screenkey and a secret being typed", function()
  local kit = require("ui.kit")
  local showmode

  before_each(function()
    showmode = vim.o.showmode
    vim.o.showmode = false
    -- The HUD fades `fade_ms` after the last key, and an earlier test above leaves it at 80 ms:
    -- a leak would be gone again by the time it is looked for, and every test below would pass
    -- without the check it is about.
    screenkey.setup({ fade_ms = 60000 })
  end)

  after_each(function()
    screenkey.disable()
    screenkey.setup({ labels = {}, join_chars = false, width = 40, fade_ms = 2000 })
    vim.cmd("stopinsert")
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(w) and vim.api.nvim_win_get_config(w).relative ~= "" then
        pcall(vim.api.nvim_win_close, w, true)
      end
    end
    vim.o.showmode = showmode
  end)

  it("shows what is typed into a plain prompt (the control)", function()
    screenkey.enable()
    kit.input({ relative = "editor" })
    feed("Aok")
    vim.wait(300, function()
      return current_text():find("k", 1, true) ~= nil
    end)
    assert.is_true(current_text():find("o", 1, true) ~= nil, current_text())
    assert.is_true(current_text():find("k", 1, true) ~= nil, current_text())
  end)

  it("shows nothing of what is typed into a secret prompt", function()
    screenkey.enable()
    kit.input({ relative = "editor", secret = true })
    feed("Ahunter2")
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "no key reached the HUD: " .. current_text())
  end)

  it("shows nothing of a sheet with a secret field, whichever row is typed into", function()
    screenkey.enable()
    local sheet = kit.sheet({
      fields = { { name = "user" }, { name = "token", secret = true } },
      relative = "editor",
      on_submit = function() end,
    })
    feed("Aroot")
    sheet:focus_field("token")
    feed("Ahunter2")
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "no key reached the HUD: " .. current_text())
  end)

  it("shows what is typed into a sheet with no secret field (the control)", function()
    screenkey.enable()
    kit.sheet({
      fields = { { name = "user" }, { name = "city" } },
      relative = "editor",
      on_submit = function() end,
    })
    feed("Aroot")
    vim.wait(300, function()
      return current_text():find("t", 1, true) ~= nil
    end)
    assert.is_true(current_text():find("r", 1, true) ~= nil, current_text())
  end)

  it("leaves out the key that closes the prompt too, and shows the next one again", function()
    screenkey.enable()
    local secret = kit.input({ relative = "editor", secret = true })
    feed("Ahunter2")
    -- `c` of `<C-w>c` closes the window the prompt is in: the current buffer is another one
    -- by the time the HUD's scheduled work runs, so it must be asked when the key arrives.
    feed("<C-w>c")
    vim.wait(300)
    assert.is_false(secret:is_valid(), "the prompt is closed")
    assert.is_nil(screenkey.surface(), "not even the closing key: " .. current_text())

    feed("j")
    vim.wait(300, function()
      return screenkey.surface() ~= nil
    end)
    assert.equals("j", current_text(), "outside the prompt the HUD works again")
  end)

  it("shows nothing of the keys that wipe the secret out of the last Insert run", function()
    -- `scrub_insert_traces` types `i<Esc>` into a scratch buffer once the prompt is gone.
    screenkey.enable()
    local secret = kit.input({ relative = "editor", secret = true })
    feed("Ahunter2")
    secret:close()
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "nothing from the scrub either: " .. current_text())
  end)
end)

describe("ui.screenkey and a prompt that is not the kit's", function()
  local showmode

  before_each(function()
    showmode = vim.o.showmode
    vim.o.showmode = false
    screenkey.setup({ fade_ms = 60000 })
  end)

  after_each(function()
    screenkey.disable()
    screenkey.setup({
      labels = {},
      join_chars = false,
      width = 40,
      fade_ms = 2000,
      hide = { buftypes = {}, filetypes = {} },
    })
    vim.cmd("stopinsert")
    vim.o.showmode = showmode
  end)

  --- Types `keys` into `vim.fn.input()` / `vim.fn.inputsecret()` as if from the keyboard.
  ---@param fn_name "input"|"inputsecret"
  ---@param keys string
  ---@return string answer
  local function answer_prompt(fn_name, keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "t", false)
    -- (not `vim.fn[...]`: the test guard of testing.nvim intercepts that and refuses an unanswered prompt)
    return vim.api.nvim_call_function(fn_name, { "pw: " })
  end

  for _, fn_name in ipairs({ "inputsecret", "input" }) do
    it("shows nothing of what is typed into " .. fn_name .. "()", function()
      screenkey.enable()
      local answer = answer_prompt(fn_name, "hunter2<CR>")
      vim.wait(300)
      assert.equals("hunter2", answer)
      assert.is_nil(screenkey.surface(), "no key reached the HUD: " .. current_text())
      feed("j")
      vim.wait(300, function()
        return current_text() ~= ""
      end)
      assert.equals("j", current_text(), "outside the prompt the HUD works again")
    end)
  end

  it("shows nothing typed into a buftype=prompt buffer", function()
    screenkey.enable()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "prompt"
    vim.api.nvim_set_current_buf(buf)
    feed("ihunter2")
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "no key reached the HUD: " .. current_text())
    vim.cmd("stopinsert")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("hides the buftypes and filetypes of setup({ hide })", function()
    screenkey.setup({ hide = { buftypes = { "nofile" }, filetypes = { "secretft" } } })
    assert.same({}, screenkey.health_issues())
    screenkey.enable()
    local buf = vim.api.nvim_create_buf(false, true) -- buftype=nofile
    vim.api.nvim_set_current_buf(buf)
    feed("ia")
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "a hidden buftype shows nothing: " .. current_text())
    vim.cmd("stopinsert")

    vim.bo[buf].buftype = ""
    vim.bo[buf].filetype = "secretft"
    feed("ib")
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "a hidden filetype shows nothing: " .. current_text())
    vim.cmd("stopinsert")

    vim.bo[buf].filetype = "lua"
    feed("ic")
    vim.wait(300, function()
      return current_text():find("c", 1, true) ~= nil
    end)
    assert.is_true(
      current_text():find("c", 1, true) ~= nil,
      "the control shows: " .. current_text()
    )
    vim.cmd("stopinsert")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("hides a dotted filetype when any of its parts is listed", function()
    screenkey.setup({ hide = { filetypes = { "secretft" } } })
    screenkey.enable()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].buftype = ""
    for _, ft in ipairs({ "secretft.local", "other.secretft", "secretft" }) do
      vim.bo[buf].filetype = ft
      feed("ix")
      vim.wait(300)
      assert.is_nil(screenkey.surface(), ft .. " shows nothing: " .. current_text())
      vim.cmd("stopinsert")
    end
    -- a part that is not listed, and a name that merely contains a listed one, still show
    vim.bo[buf].filetype = "secretftx.local"
    feed("iy")
    vim.wait(300, function()
      return current_text():find("y", 1, true) ~= nil
    end)
    assert.is_true(current_text():find("y", 1, true) ~= nil, "unlisted parts show: " .. current_text())
    vim.cmd("stopinsert")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("a later setup({ hide }) replaces the list of that field and keeps the other", function()
    screenkey.setup({ hide = { filetypes = { "first" }, buftypes = { "nofile" } } })
    screenkey.setup({ hide = { filetypes = { "second" } } })
    screenkey.enable()
    local buf = vim.api.nvim_create_buf(false, true) -- buftype=nofile, still hidden
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].filetype = "first" -- no longer hidden, but the buftype is
    feed("ia")
    vim.wait(300)
    assert.is_nil(
      screenkey.surface(),
      "the untouched buftypes list still hides: " .. current_text()
    )
    vim.cmd("stopinsert")
    screenkey.setup({ hide = { buftypes = {} } }) -- `{}` empties the field
    feed("ib")
    vim.wait(300, function()
      return current_text():find("b", 1, true) ~= nil
    end)
    assert.is_true(
      current_text():find("b", 1, true) ~= nil,
      "an emptied list hides nothing: " .. current_text()
    )
    vim.cmd("stopinsert")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("a rejected hide list keeps the current one, a replacing one is in force", function()
    screenkey.setup({ hide = { filetypes = { "keepme" } } })
    screenkey.setup({ hide = { filetypes = { secret = true } } }) -- a dict is no list
    screenkey.setup({ hide = { filetypes = "oops" } })
    screenkey.setup({ hide = { filetypes = { "fine", 5 } } }) -- one bad entry rejects the list
    assert.is_truthy(
      table.concat(screenkey.health_issues(), "\n"):find("kept the current list", 1, true)
    )
    screenkey.enable()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)
    vim.bo[buf].buftype = "" -- only the filetype can hide this buffer
    vim.bo[buf].filetype = "keepme"
    feed("ia")
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "the rejected calls kept the list: " .. current_text())
    vim.cmd("stopinsert")
    screenkey.setup({ hide = { filetypes = { "second" } } })
    vim.bo[buf].filetype = "second"
    feed("ib")
    vim.wait(300)
    assert.is_nil(screenkey.surface(), "the replacing list hides: " .. current_text())
    vim.cmd("stopinsert")
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("setup() reports an option key it does not know", function()
    screenkey.setup({ hide_filetypes = { "x" } })
    assert.is_truthy(
      table
        .concat(screenkey.health_issues(), "\n")
        :find("hide_filetypes is not a known option", 1, true)
    )
    screenkey.setup({})
    assert.same({}, screenkey.health_issues())
  end)

  it("setup() rejects a malformed hide list and keeps the current one", function()
    screenkey.setup({ hide = { filetypes = { "keepme" } } })
    screenkey.setup({ hide = { filetypes = "oops", buftypes = { 5 } } })
    local issues = table.concat(screenkey.health_issues(), "\n")
    assert.is_truthy(issues:find("hide.filetypes", 1, true), issues)
    assert.is_truthy(issues:find("hide.buftypes", 1, true), issues)
    -- a dict-shaped table is no list; an unknown key is named
    screenkey.setup({ hide = { filetypes = { secret = true }, filetype = { "x" } } })
    issues = table.concat(screenkey.health_issues(), "\n")
    assert.is_truthy(issues:find("hide.filetypes must be a list", 1, true), issues)
    assert.is_truthy(issues:find("hide.filetype is not a known key", 1, true), issues)
    screenkey.setup({ hide = 3 })
    assert.is_truthy(
      table.concat(screenkey.health_issues(), "\n"):find("hide must be a table", 1, true)
    )
  end)
end)
