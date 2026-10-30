-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.idle_git_log` -- the last commits of the buffer's
--- repo, shown only while idle, read once per idle phase. Built on
--- `ui.statusline.utils.idle` (covered on its own in TESTS/idle_spec.lua);
--- this file checks the payload: when it reads, what it caches, what it
--- renders. `lib.nvim.git` is replaced by a fake whose `log_async` records
--- every call and answers only when the test says so -- the real one would
--- make every assertion here depend on a git binary and its timing.

---@class IdleGitLogFakeCall
---@field range string|nil
---@field opts table
---@field on_done fun(entries: table[]|nil, err: string|nil)
---@field stopped boolean

---@type IdleGitLogFakeCall[]
local calls = {}
local real_git = package.loaded["lib.nvim.git"]

local fake_git = {
  log_async = function(range, opts, on_done)
    local call = { range = range, opts = opts, on_done = on_done, stopped = false }
    calls[#calls + 1] = call
    return {
      stop = function()
        call.stopped = true
      end,
    }
  end,
}

---@param sha string
---@param subject string
---@return table
local function commit(sha, subject)
  return { sha = sha .. string.rep("0", 40 - #sha), subject = subject }
end

---@return fun(opts?: table): string
local function fresh_module()
  package.loaded["ui.statusline.utils.idle"] = nil
  package.loaded["ui.statusline.modules.idle_git_log"] = nil
  package.loaded["lib.nvim.git"] = fake_git
  local mod = require("ui.statusline.modules.idle_git_log")
  -- First render registers the idle autocmds (see TESTS/idle_clock_spec.lua).
  mod()
  return mod
end

---@param event string
local function fire(event)
  vim.api.nvim_exec_autocmds(event, {})
end

--- A directory with a `.git` entry (all `repo_root` looks for) and a file
--- buffer inside it, made current.
---@param with_git boolean
---@return string dir
local function enter_buffer_in(with_git)
  local dir = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(dir, "p")
  if with_git then
    vim.fn.mkdir(dir .. "/.git", "p")
  end
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, dir .. "/file.lua")
  vim.api.nvim_set_current_buf(buf)
  vim.g.statusline_winid = vim.api.nvim_get_current_win()
  return dir
end

describe("ui.statusline.modules.idle_git_log", function()
  before_each(function()
    calls = {}
  end)

  after_each(function()
    package.loaded["lib.nvim.git"] = real_git
    package.loaded["ui.statusline.modules.idle_git_log"] = nil
    vim.g.statusline_winid = nil
  end)

  it("renders empty and reads nothing while active", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    assert.equals("", mod())
    assert.equals(0, #calls)
  end)

  it("reads git log once idle, via an argv-based async call, and renders the commits", function()
    local dir = enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")

    assert.equals("", mod(), "nothing to show before the read answers")
    assert.equals(1, #calls)
    assert.is_nil(calls[1].range) -- HEAD
    assert.equals(dir, vim.fs.normalize(calls[1].opts.dir))
    assert.equals(3, calls[1].opts.max_count)
    assert.is_number(calls[1].opts.timeout_ms)
    assert.is_number(calls[1].opts.max_output_bytes)
    -- A blobless/partial clone must never fetch over the network for this.
    assert.is_true(calls[1].opts.no_lazy_fetch)

    calls[1].on_done({ commit("a1b2c3d", "Fix the parser"), commit("9f8e7d6", "Add tests") })

    assert.equals(" a1b2c3d Fix the parser · 9f8e7d6 Add tests ", mod())
  end)

  it("reads only once per idle phase, however often it redraws", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    calls[1].on_done({ commit("a1b2c3d", "One") })
    for _ = 1, 5 do
      mod()
    end
    fire("CursorHold") -- still the same phase: already idle
    mod()

    assert.equals(1, #calls)
  end)

  it("does not start a second read while the first one is still running", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    mod()
    mod()
    assert.equals(1, #calls)
  end)

  it("reads again in the next idle phase, and drops the previous phase's result", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    calls[1].on_done({ commit("a1b2c3d", "Old") })
    assert.is_truthy(mod():find("Old", 1, true))

    fire("CursorMoved")
    assert.equals("", mod())
    fire("CursorHold")

    assert.equals("", mod(), "the new phase starts without the old phase's cache")
    assert.equals(2, #calls)
    calls[2].on_done({ commit("1234567", "New") })
    assert.equals(" 1234567 New ", mod())
  end)

  it("stops a read still running when its idle phase ends, and ignores its late answer", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    fire("CursorMoved")
    fire("CursorHold")
    mod()

    assert.is_true(calls[1].stopped)
    calls[1].on_done({ commit("deadbee", "Stale") })
    calls[2].on_done({ commit("1234567", "Fresh") })
    assert.equals(" 1234567 Fresh ", mod())
  end)

  it("renders empty outside a repo without starting git", function()
    enter_buffer_in(false)
    local mod = fresh_module()
    fire("CursorHold")
    assert.equals("", mod())
    assert.equals(0, #calls)
  end)

  it("renders empty when git fails (a repo without commits, a timeout)", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    calls[1].on_done(nil, "does not have any commits yet")
    assert.equals("", mod())
    assert.equals(1, #calls, "a failed read is cached for the phase too")
  end)

  it("repaints once when the read answers while still idle", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()

    local redraws = 0
    local orig_cmd = vim.cmd
    vim.cmd = function(c)
      if c == "redrawstatus!" then
        redraws = redraws + 1
      end
      return orig_cmd(c)
    end
    local ok, err = pcall(calls[1].on_done, { commit("a1b2c3d", "One") })
    vim.cmd = orig_cmd

    assert.is_true(ok, err)
    assert.equals(1, redraws)
  end)

  it("does not repaint for an idle phase that ended before the read answered", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    fire("CursorMoved")

    local redraws = 0
    local orig_cmd = vim.cmd
    vim.cmd = function(c)
      if c == "redrawstatus!" then
        redraws = redraws + 1
      end
      return orig_cmd(c)
    end
    local ok, err = pcall(calls[1].on_done, { commit("a1b2c3d", "One") })
    vim.cmd = orig_cmd

    assert.is_true(ok, err)
    assert.equals(0, redraws)
  end)

  it("honours opts.max_count (clamped to 1..3) and opts.subject_width", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    calls[1].on_done({
      commit("aaaaaaa", "First subject"),
      commit("bbbbbbb", "Second"),
      commit("ccccccc", "Third"),
    })

    assert.equals(" aaaaaaa First subject ", mod({ max_count = 1 }))
    assert.equals(" aaaaaaa First… ", mod({ max_count = 1, subject_width = 6 }))
    local all = mod({ max_count = 10 })
    assert.is_truthy(all:find("ccccccc", 1, true))
    assert.equals(" aaaaaaa First subject ", mod({ max_count = 0 }))
    assert.equals(1, #calls, "options do not cause extra reads")
  end)

  it("makes commit text safe for the statusline", function()
    enter_buffer_in(true)
    local mod = fresh_module()
    fire("CursorHold")
    mod()
    calls[1].on_done({ commit("a1b2c3d", "100% done\27[31m") })

    local out = mod()
    assert.is_nil(out:find("\27", 1, true), "escape sequence must not reach the statusline")
    assert.is_truthy(out:find("100%% done", 1, true), "a literal % must be escaped as %%")
  end)
end)
