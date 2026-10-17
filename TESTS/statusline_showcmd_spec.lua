-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.showcmd` (the `%S` segment) and
--- `ui.statusline.modules.showcmd.loc` (who owns `'showcmdloc'` while it is
--- shown). The first half runs in this process: taking and handing back the
--- option. The second half starts a child Neovim with `--embed` and an
--- attached UI and types a real `2d` into it -- `showcmd`'s buffer is only
--- ever filled by real typed input, and an RPC request is still answered
--- while the operator waits for its motion, so `nvim_eval_statusline` there
--- shows exactly what the statusline row holds at that moment.

local showcmd = require("ui.statusline.modules.showcmd")
local loc = require("ui.statusline.modules.showcmd.loc")
local render = require("ui.statusline.render")

describe("ui.statusline.modules.showcmd", function()
  it("renders the %S item inside an empty-collapsing group", function()
    local out = showcmd()
    assert.is_truthy(out:find("%S", 1, true), out)
    assert.is_truthy(out:find("%(", 1, true), out)
    assert.is_truthy(out:find("%)", 1, true), out)
  end)

  -- While the key is in `order`, 'showcmdloc' is "statusline": a responsive
  -- statusline dropping the segment in a narrow window would leave the
  -- pending keys drawn nowhere.
  it("is kept by responsive mode in a narrow window", function()
    local columns = vim.o.columns
    vim.o.columns = 200
    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_width(win, 20)
    local saved_winid = vim.g.statusline_winid
    vim.g.statusline_winid = win
    local ok, out = pcall(render.generate, {
      order = { "git", "showcmd" },
      modules = { git = "G", showcmd = showcmd },
      responsive = true,
      responsive_width = 80,
    })
    vim.g.statusline_winid = saved_winid
    pcall(vim.api.nvim_win_close, win, true)
    vim.o.columns = columns
    assert.is_true(ok, out)
    assert.is_falsy(out:find("G", 1, true), "the non-essential git segment is dropped: " .. out)
    assert.is_truthy(out:find("%S", 1, true), "the showcmd segment stays: " .. out)
  end)
end)

describe("ui.statusline.modules.showcmd.loc", function()
  local original

  before_each(function()
    loc.apply(false)
    original = vim.o.showcmdloc
    vim.o.showcmdloc = "last"
  end)

  after_each(function()
    loc.apply(false)
    render.disable()
    vim.o.showcmdloc = original
  end)

  it("knows whether an order holds the key", function()
    assert.is_true(loc.wanted({ "mode", "showcmd" }))
    assert.is_false(loc.wanted({ "mode", "%=" }))
    assert.is_false(loc.wanted(nil))
  end)

  it("takes the option and hands the earlier value back", function()
    loc.apply(true)
    assert.equals("statusline", vim.o.showcmdloc)
    assert.equals("last", select(2, loc.status()))
    loc.apply(false)
    assert.equals("last", vim.o.showcmdloc)
    assert.is_false((loc.status()))
  end)

  it("keeps the value from before the first take when applied twice", function()
    vim.o.showcmdloc = "tabline"
    loc.apply(true)
    loc.apply(true)
    loc.apply(false)
    assert.equals("tabline", vim.o.showcmdloc)
  end)

  it("leaves a value somebody else set in the meantime alone", function()
    loc.apply(true)
    vim.o.showcmdloc = "tabline"
    loc.apply(false)
    assert.equals("tabline", vim.o.showcmdloc)
  end)

  it("sync() changes nothing synchronously and applies on the next tick", function()
    loc.sync({ "showcmd" })
    assert.equals("last", vim.o.showcmdloc, "never set mid-redraw")
    assert.is_true(vim.wait(1000, function()
      return vim.o.showcmdloc == "statusline"
    end, 10))
    loc.sync({ "mode" })
    assert.is_true(vim.wait(1000, function()
      return vim.o.showcmdloc == "last"
    end, 10))
  end)

  it("follows render.enable() across a variant switch and render.disable()", function()
    render.enable({ order = { "showcmd" }, modules = { showcmd = showcmd } })
    assert.equals("statusline", vim.o.showcmdloc, "a variant with the segment takes it")
    render.enable({ order = { "mode" }, modules = { mode = "M" } })
    assert.equals("last", vim.o.showcmdloc, "a variant without it hands it back")
    render.enable({ order = { "showcmd" }, modules = { showcmd = showcmd } })
    render.disable()
    assert.equals("last", vim.o.showcmdloc, "disable() hands it back")
  end)

  it("follows an order edited in place on the next statusline redraw", function()
    local cfg = { order = { "mode" }, modules = { mode = "M", showcmd = showcmd } }
    render.enable(cfg)
    assert.equals("last", vim.o.showcmdloc)
    cfg.order[#cfg.order + 1] = "showcmd" -- what the menu's "Add module" does
    render.render()
    assert.is_true(vim.wait(1000, function()
      return vim.o.showcmdloc == "statusline"
    end, 10))
    table.remove(cfg.order) -- the menu's "Remove"
    render.render()
    assert.is_true(vim.wait(1000, function()
      return vim.o.showcmdloc == "last"
    end, 10))
  end)
end)

describe("the showcmd segment in a real Neovim", function()
  ---@type integer|nil
  local chan

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

  --- The current window's statusline as drawn, highlights stripped.
  ---@return string
  local function statusline()
    return lua([[return vim.api.nvim_eval_statusline(vim.o.statusline, { winid = 0 }).str]])
  end

  ---@param cond fun(): boolean
  ---@param what string
  local function expect(cond, what)
    assert.is_true(vim.wait(3000, cond, 20), what)
  end

  ---@param laststatus integer
  local function start(laststatus)
    local env = vim.fn.environ()
    if vim.fn.has("win32") == 1 then
      env.SHELL = nil
    end
    chan = vim.fn.jobstart(
      { vim.v.progpath, "--embed", "-n", "-i", "NONE", "-u", "NONE" },
      { rpc = true, env = env, clear_env = true }
    )
    assert.is_true(chan > 0, "the child Neovim did not start")
    vim.rpcrequest(chan, "nvim_ui_attach", 80, 24, { rgb = true })
    vim.rpcrequest(
      chan,
      "nvim_exec_lua",
      [[
        local lib, ui, laststatus = ...
        vim.opt.rtp:prepend(lib)
        vim.opt.rtp:prepend(ui)
        vim.o.laststatus = laststatus
        require("ui.statusline.render").enable({
          order = { "showcmd", "END" },
          modules = { showcmd = require("ui.statusline.modules.showcmd"), END = "END" },
        })
      ]],
      { root_of("lua/lib/nvim/init.lua"), root_of("lua/ui/statusline/render.lua"), laststatus }
    )
  end

  after_each(function()
    if chan then
      pcall(vim.fn.jobstop, chan)
      chan = nil
    end
  end)

  for _, laststatus in ipairs({ 2, 3 }) do
    it("shows a pending 2d in the statusline, laststatus=" .. laststatus, function()
      start(laststatus)
      if laststatus == 3 then
        lua([[vim.cmd("vsplit")]])
      end
      assert.equals("statusline", lua([[return vim.o.showcmdloc]]))
      assert.equals("END", statusline(), "idle: the group takes no columns")

      vim.rpcrequest(chan, "nvim_input", "2d")
      expect(function()
        return statusline() == " 2d END"
      end, "the pending keys are drawn: " .. statusline())

      vim.rpcrequest(chan, "nvim_input", "<Esc>")
      expect(function()
        return statusline() == "END"
      end, "and gone once the operator is cancelled: " .. statusline())
    end)
  end

  it("shows nothing under :UI zen and comes back once zen closes", function()
    start(2)
    lua([[require("ui.zen").open()]])
    assert.same(
      { laststatus = 0, showcmd = false, showcmdloc = "statusline" },
      lua([[return {
        laststatus = vim.o.laststatus, showcmd = vim.o.showcmd, showcmdloc = vim.o.showcmdloc,
      }]]),
      "zen hides the statusline and turns showcmd off; the segment's option stays"
    )
    vim.rpcrequest(chan, "nvim_input", "2d")
    expect(function()
      return lua([[return vim.api.nvim_get_mode().mode]]) == "no"
    end, "the operator waits")
    assert.equals("END", statusline(), "showcmd off: %S is empty even with keys pending")
    vim.rpcrequest(chan, "nvim_input", "<Esc>")

    lua([[require("ui.zen").close()]])
    expect(function()
      return lua([[return vim.o.showcmd and vim.o.laststatus == 2]])
    end, "zen gives showcmd and the statusline back")
    vim.rpcrequest(chan, "nvim_input", "2d")
    expect(function()
      return statusline() == " 2d END"
    end, "and the segment shows keys again: " .. statusline())
  end)
end)
