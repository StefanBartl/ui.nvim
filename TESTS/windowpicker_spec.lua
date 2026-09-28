-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.windowpicker` -- pick a window by letter: filtering, autoselect,
--- the hint overlay, and picking/cancelling via a real (fed) keypress.

local windowpicker = require("ui.windowpicker")

---@param keys string
local function feed(keys)
  vim.api.nvim_feedkeys(keys, "n", false)
end

describe("ui.windowpicker", function()
  after_each(function()
    windowpicker.setup({
      chars = "FJDKSLA;CMRUEIWOQP",
      include_current_win = false,
      autoselect_one = true,
      include_unfocusable_windows = false,
      filetype = { "neo-tree", "neo-tree-popup", "notify", "replacer-progress" },
      buftype = { "terminal", "quickfix" },
      debug = false,
    })
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
  end)

  it("returns nil when nothing qualifies", function()
    vim.cmd("only")
    vim.bo.filetype = "neo-tree" -- the one window is also the current one, excluded twice over
    assert.is_nil(windowpicker.pick())
  end)

  it("autoselects the only qualifying window without reading a key", function()
    vim.cmd("only")
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.cmd("wincmd p") -- back to the origin, which is now excluded as "current"
    -- No feed() call at all: if this reached getchar() the test would hang.
    assert.equals(other, windowpicker.pick())
  end)

  it("shows a hint on each candidate and picks the one whose letter is pressed", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local second = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local third = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)

    windowpicker.setup({ include_current_win = true, autoselect_one = false })
    local wins_before = vim.api.nvim_tabpage_list_wins(0)

    -- Candidates are enumerated in `nvim_tabpage_list_wins` order, so the
    -- second candidate here is the second-listed window, not necessarily
    -- `second` -- assert against that order instead of assuming it.
    local target = wins_before[2]
    feed("J") -- second letter in the default "FJDKSLA;..." order
    local picked = windowpicker.pick()
    assert.equals(target, picked)
    assert.is_true(vim.api.nvim_win_is_valid(origin))
    assert.is_true(vim.api.nvim_win_is_valid(second))
    assert.is_true(vim.api.nvim_win_is_valid(third))
  end)

  it("cleans up every hint overlay after picking", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })

    local wins_before = vim.api.nvim_list_wins()
    feed("F")
    windowpicker.pick()
    local wins_after = vim.api.nvim_list_wins()
    assert.same(#wins_before, #wins_after)
  end)

  it("returns nil when the pressed key matches no hint", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })

    feed("Z") -- not in "FJDKSLA;CMRUEIWOQP"
    assert.is_nil(windowpicker.pick())
  end)

  it("excludes the current window by default", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)

    assert.equals(other, windowpicker.pick()) -- autoselects: origin excluded, one left
  end)

  it("excludes windows by filetype and buftype", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.bo.filetype = "neo-tree"
    vim.api.nvim_set_current_win(origin)

    -- The only other window is filtered out by filetype, so nothing qualifies.
    assert.is_nil(windowpicker.pick())
  end)

  it(
    "excludes unfocusable windows by default, offers them with include_unfocusable_windows",
    function()
      vim.cmd("only")
      local origin = vim.api.nvim_get_current_win()
      local unfocusable = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
        relative = "editor",
        row = 1,
        col = 1,
        width = 10,
        height = 3,
        focusable = false,
      })
      vim.api.nvim_set_current_win(origin)

      -- Excluded by default: the unfocusable float doesn't qualify, so nothing does.
      assert.is_nil(windowpicker.pick())

      windowpicker.setup({ include_unfocusable_windows = true })
      assert.equals(unfocusable, windowpicker.pick()) -- autoselects: the only candidate now

      vim.api.nvim_win_close(unfocusable, true)
    end
  )

  it("returns nil instead of a stale id when the target window closes during the wait", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local target = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })

    -- getchar() yields to the event loop while it blocks, so a deferred
    -- callback really does get to run mid-pick -- close the window the
    -- letter was assigned to, then only feed the keystroke that unblocks
    -- getchar() once it is already gone.
    vim.defer_fn(function()
      pcall(vim.api.nvim_win_close, target, true)
      vim.api.nvim_feedkeys("J", "n", false)
    end, 10)

    assert.is_nil(windowpicker.pick())
  end)

  it("draws each hint three cells wide, not make_scratch's 60-cell empty-size fallback", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })

    local widths = {}
    vim.defer_fn(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= "" then
          widths[#widths + 1] = vim.api.nvim_win_get_width(win)
        end
      end
      vim.api.nvim_feedkeys("F", "n", false)
    end, 10)
    windowpicker.pick()

    assert.is_true(#widths >= 1)
    for _, w in ipairs(widths) do
      assert.equals(3, w)
    end
  end)

  it("records the last call, including whether it prompted and what it picked", function()
    vim.cmd("only")
    assert.is_nil(windowpicker.pick()) -- one window, excluded as current: nothing to pick
    local call = windowpicker.last_call()
    assert.is_not_nil(call)
    assert.equals(0, call.candidates)
    assert.is_false(call.prompted)
    assert.is_nil(call.picked)
    assert.is_truthy(call.traceback:find("stack traceback", 1, true))

    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })
    feed("F")
    local picked = windowpicker.pick()
    call = windowpicker.last_call()
    assert.equals(1, call.candidates) -- origin is excluded as "current"
    assert.is_true(call.prompted)
    assert.equals(picked, call.picked)
  end)

  it(
    "records the call before counting windows, so a raising pick still leaves it behind",
    function()
      vim.cmd("only")
      windowpicker.pick() -- leaves a record with 0 candidates
      local before = windowpicker.last_call()
      local real = vim.api.nvim_tabpage_list_wins
      vim.api.nvim_tabpage_list_wins = function()
        error("boom")
      end
      local ok = pcall(windowpicker.pick)
      vim.api.nvim_tabpage_list_wins = real
      assert.is_false(ok)
      assert.are_not.equal(before, windowpicker.last_call()) -- a fresh record, not the stale one
    end
  )

  describe("debug", function()
    local real_notify, messages, floats_at_report

    before_each(function()
      messages, floats_at_report = {}, nil
      real_notify = vim.notify
      vim.notify = function(msg)
        messages[#messages + 1] = msg
        if msg:find("pick():", 1, true) then
          local n = 0
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_get_config(win).relative ~= "" then
              n = n + 1
            end
          end
          floats_at_report = n
        end
      end
    end)

    after_each(function()
      vim.notify = real_notify
    end)

    it("stays silent unless enabled", function()
      vim.cmd("only")
      windowpicker.pick()
      for _, msg in ipairs(messages) do
        assert.is_nil(msg:find("pick():", 1, true))
      end
    end)

    it("reports the traceback only after the hints are gone", function()
      vim.cmd("only")
      local origin = vim.api.nvim_get_current_win()
      vim.cmd("vsplit")
      vim.api.nvim_set_current_win(origin)
      windowpicker.setup({ autoselect_one = false, debug = true })

      feed("F")
      windowpicker.pick()

      local report
      for _, msg in ipairs(messages) do
        if msg:find("pick():", 1, true) then
          report = msg
        end
      end
      assert.is_not_nil(report)
      assert.is_truthy(report:find("prompted=true", 1, true))
      assert.is_truthy(report:find("stack traceback", 1, true))
      assert.equals(0, floats_at_report) -- no hint overlay left while the report is emitted
    end)
  end)

  describe("focus taken while the hints are up", function()
    ---@return integer origin, integer other
    local function two_windows()
      vim.cmd("only")
      local origin = vim.api.nvim_get_current_win()
      vim.cmd("vsplit")
      local other = vim.api.nvim_get_current_win()
      vim.api.nvim_set_current_win(origin)
      windowpicker.setup({ autoselect_one = false, include_current_win = false })
      return origin, other
    end

    ---A focused float, like a dashboard whose scan just finished.
    ---@return integer win
    local function open_intruder()
      return vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
        relative = "editor",
        row = 1,
        col = 1,
        width = 10,
        height = 3,
      })
    end

    ---Safety net so a broken cancel fails an assertion instead of hanging the
    ---suite in getchar(). The flag keeps it from feeding a stray key later,
    ---after the pick already returned.
    ---@return fun() disarm
    local function arm_safety_net()
      local done = false
      vim.defer_fn(function()
        if not done then
          vim.api.nvim_feedkeys("Z", "n", false)
        end
      end, 400)
      return function()
        done = true
      end
    end

    it("cancels the pick when another window takes focus", function()
      two_windows()
      local intruder
      vim.defer_fn(function()
        -- No key is fed: getchar() only returns because the picker cancels itself.
        intruder = open_intruder()
      end, 10)
      local disarm = arm_safety_net()

      assert.is_nil(windowpicker.pick())
      disarm()

      assert.is_true(windowpicker.last_call().focus_lost)
      assert.is_true(windowpicker.last_call().prompted)
      assert.equals(intruder, vim.api.nvim_get_current_win()) -- focus stays where it went
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(win).relative ~= "" then
          assert.equals(intruder, win) -- every hint overlay is gone, only the intruder floats
        end
      end
      assert.equals(0, vim.fn.getchar(1)) -- the cancelling <Esc> was consumed, nothing leaked
      vim.api.nvim_win_close(intruder, true)
    end)

    it("queues the cancelling <Esc> only once when focus moves twice", function()
      local _, other = two_windows()
      local intruder
      vim.defer_fn(function()
        intruder = open_intruder() -- first WinEnter
        -- Second WinEnter before getchar() got to run. It must land in a window
        -- other than the one the pick started in, or the hook's own "did focus
        -- actually move" check would swallow it and the test proves nothing.
        vim.api.nvim_set_current_win(other)
      end, 10)
      local disarm = arm_safety_net()

      assert.is_nil(windowpicker.pick())
      disarm()

      assert.is_true(windowpicker.last_call().focus_lost)
      assert.equals(0, vim.fn.getchar(1)) -- a second queued <Esc> would show up here
      vim.api.nvim_win_close(intruder, true)
    end)

    it("stays cancelled and drains the <Esc> when the user's key wins the race", function()
      two_windows()
      local intruder
      vim.defer_fn(function()
        -- The user's letter is queued first, so getchar() returns it; the
        -- <Esc> queued by the WinEnter hook right after is still pending.
        vim.api.nvim_input("F")
        intruder = open_intruder()
      end, 10)
      local disarm = arm_safety_net()

      local picked = windowpicker.pick()
      disarm()

      assert.is_nil(picked) -- not `other`: the layout the letter referred to is stale
      assert.is_true(windowpicker.last_call().focus_lost)
      assert.equals(0, vim.fn.getchar(1)) -- the leftover <Esc> was swallowed, not leaked
      vim.api.nvim_win_close(intruder, true)
    end)

    it(
      "drains the leftover <Esc> when the user's own key winning the race is <Esc> itself",
      function()
        local _, other = two_windows()
        local intruder
        vim.defer_fn(function()
          -- The user's own <Esc> is queued first, so getchar() returns 27 for
          -- it -- indistinguishable by code alone from the hook's own <Esc>,
          -- queued right after, which is still pending.
          vim.api.nvim_input("<Esc>")
          intruder = open_intruder()
        end, 10)
        local disarm = arm_safety_net()

        local picked = windowpicker.pick()
        disarm()

        assert.is_nil(picked)
        assert.are_not.equal(other, picked)
        assert.is_true(windowpicker.last_call().focus_lost)
        assert.equals(0, vim.fn.getchar(1)) -- the hook's own <Esc> was drained too, not leaked
        vim.api.nvim_win_close(intruder, true)
      end
    )
  end)

  it("never offers lib.nvim's progress float as a target", function()
    -- The shipped defaults, not whatever earlier tests' after_each left in
    -- `cfg`: reload the module so this asserts the defaults themselves.
    package.loaded["ui.windowpicker"] = nil
    local fresh = require("ui.windowpicker")
    package.loaded["ui.windowpicker"] = windowpicker

    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local other = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(origin)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "replacer-progress"
    local progress = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 20,
      height = 1,
      focusable = true, -- the kit/float progress styles are focusable on purpose
    })

    -- With the float excluded exactly one candidate (`other`) is left, so
    -- autoselect returns it without prompting. If the float were offered, this
    -- would reach getchar(); the timer turns that hang into a failure.
    local done = false
    vim.defer_fn(function()
      if not done then
        vim.api.nvim_feedkeys("Z", "n", false)
      end
    end, 400)
    local picked = fresh.pick()
    done = true

    assert.equals(other, picked)
    assert.equals(1, fresh.last_call().candidates)
    assert.is_false(fresh.last_call().prompted)
    vim.api.nvim_win_close(progress, true)
  end)

  it("leaves focus_lost false for a normal pick", function()
    vim.cmd("only")
    local origin = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    vim.api.nvim_set_current_win(origin)
    windowpicker.setup({ autoselect_one = false })
    feed("F")
    windowpicker.pick()
    assert.is_false(windowpicker.last_call().focus_lost)
  end)

  it("setup() overrides the shipped defaults", function()
    windowpicker.setup({ chars = "AB" })
    assert.equals("AB", windowpicker.config().chars)
  end)
end)
