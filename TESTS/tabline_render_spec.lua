-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.tabline.render` — the `vim.o.tabline` / `order`-`modules` walk this
--- plugin gained closing roadmap step 7's tabline gap, run WITHOUT NvChad.
--- Same shape as `TESTS/statusline_render_spec.lua`, one option later.

describe("ui.tabline.render.generate", function()
  local render = require("ui.tabline.render")

  it("walks order, resolving each key against its own modules table", function()
    local out = render.generate({
      order = { "a", "b" },
      modules = {
        a = function()
          return "A"
        end,
        b = "B", -- a string module is valid too, same as ui.statusline.render.generate()
      },
    })
    assert.equals("AB", out)
  end)

  it("renders a missing key as empty rather than throwing", function()
    assert.has_no.errors(function()
      local out = render.generate({ order = { "no_such_key" }, modules = {} })
      assert.equals("", out)
    end)
  end)

  it("catches a module that errors and renders that key as empty", function()
    assert.has_no.errors(function()
      local out = render.generate({
        order = { "ok", "bad" },
        modules = {
          ok = function()
            return "OK"
          end,
          bad = function()
            error("boom")
          end,
        },
      })
      assert.equals("OK", out)
    end)
  end)

  it("uses an empty order/modules table when omitted, without throwing", function()
    assert.has_no.errors(function()
      assert.equals("", render.generate({}))
    end)
  end)

  it("falls back to a built-in module for a key not in cfg.modules", function()
    -- "tabs" is not in `modules` here, so this only passes if the built-in
    -- ui.tabline.modules.tabs actually ran (empty with a single tab, which a
    -- headless test run always is -- see the module's own guard).
    local out = render.generate({ order = { "tabs" }, modules = {} })
    assert.equals("", out)
  end)
end)

describe("ui.tabline.render enable/render/disable", function()
  local render = require("ui.tabline.render")

  after_each(function()
    render.disable()
  end)

  it("current() is nil before enable()", function()
    render.disable()
    assert.is_nil(render.current())
  end)

  it("enable() sets vim.o.tabline to this module's own render() call", function()
    render.enable({ order = {}, modules = {} })
    assert.is_true(vim.o.tabline:find("ui.tabline.render", 1, true) ~= nil)
  end)

  it("enable() shows the tabline unconditionally (showtabline = 2)", function()
    render.enable({ order = {}, modules = {} })
    assert.equals(2, vim.o.showtabline)
  end)

  it("render() reads back the config enable() stored", function()
    render.enable({
      order = { "x" },
      modules = {
        x = function()
          return "hello"
        end,
      },
    })
    assert.equals("hello", render.render())
  end)

  it("render() is empty before any enable() call", function()
    render.disable()
    assert.equals("", render.render())
  end)

  it("disable() clears vim.o.tabline and current()", function()
    render.enable({ order = {}, modules = {} })
    render.disable()
    assert.equals("", vim.o.tabline)
    assert.is_nil(render.current())
  end)

  it("enable() is safe to call twice", function()
    assert.has_no.errors(function()
      render.enable({ order = {}, modules = {} })
      render.enable({ order = {}, modules = {} })
    end)
  end)
end)

describe("ui.tabline.render against the assembled config", function()
  -- The proof this step exists for: ui.config.setup()'s own `ui.tabline`
  -- half runs through generate() end to end, with NvChad nowhere on the
  -- runtimepath.
  local cfg = require("ui.config")
  local render = require("ui.tabline.render")

  it("renders end to end without throwing", function()
    local assembled = cfg.setup()
    local ok, out = pcall(render.generate, assembled.ui.tabline)
    assert.is_true(ok, tostring(out))
    assert.is_string(out)
  end)
end)

describe("ui.tabline.modules", function()
  local modules = require("ui.tabline.modules")
  local default_cfg = require("ui.config.tabline")

  it("tree_offset renders empty when no window has the configured filetype", function()
    assert.equals("", modules.tree_offset(default_cfg))
  end)

  it("tabs renders empty with only one tab open", function()
    assert.equals("", modules.tabs(default_cfg))
  end)

  it("btns renders the theme-toggle and close-all buttons without throwing", function()
    assert.has_no.errors(function()
      local out = modules.btns(default_cfg)
      assert.is_true(#out > 0)
    end)
  end)

  it("buffers renders without throwing when vim.t.bufs is empty", function()
    local saved = vim.t.bufs
    vim.t.bufs = {}
    assert.has_no.errors(function()
      modules.buffers(default_cfg)
    end)
    vim.t.bufs = saved
  end)

  it("computes available_space once per buffers() call, not once per buffer", function()
    -- Regression: available_space(cfg) used to be called from inside the
    -- overflow loop, once per buffer in vim.t.bufs -- pure waste, since
    -- nothing it measures (tree_offset/tabs/btns) depends on how many chips
    -- the loop has produced so far. Spying on nvim_eval_statusline (what
    -- available_space calls) proves it now runs at most once regardless of
    -- how many buffers are open.
    local calls = 0
    local original = vim.api.nvim_eval_statusline
    vim.api.nvim_eval_statusline = function(...)
      calls = calls + 1
      return original(...)
    end

    local saved = vim.t.bufs
    local bufs = {}
    for _ = 1, 5 do
      bufs[#bufs + 1] = vim.api.nvim_create_buf(true, false)
    end
    vim.t.bufs = bufs

    modules.buffers(default_cfg)

    vim.api.nvim_eval_statusline = original
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
    vim.t.bufs = saved

    assert.is_true(calls <= 1, ("expected at most 1 call, got %d"):format(calls))
  end)

  --- Regression for the "only ~7 of 10 open buffers ever show, with visible
  --- leftover space in the bar" report: a fixed 21-wide chip wastes whatever
  --- remainder doesn't divide evenly, even when every buffer would fit at a
  --- narrower width. `bufwidth` left unset now computes one from the
  --- available space instead (clamped to [12, 24]).
  describe("auto chip width (cfg.bufwidth unset)", function()
    local saved_cols

    before_each(function()
      saved_cols = vim.o.columns
    end)

    after_each(function()
      vim.o.columns = saved_cols
    end)

    ---@param n integer
    ---@return integer[]
    local function make_bufs(n)
      local bufs = {}
      for _ = 1, n do
        bufs[#bufs + 1] = vim.api.nvim_create_buf(true, false)
      end
      return bufs
    end

    ---@param bufs integer[]
    local function delete_bufs(bufs)
      for _, b in ipairs(bufs) do
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end

    ---@param out string
    ---@return integer
    local function chip_count(out)
      return select(2, out:gsub("UiTbGoToBuf", ""))
    end

    it(
      "fits every buffer when they fit at the minimum width, unlike a fixed 21-wide chip",
      function()
        vim.o.columns = 300 -- 15 * 21 = 315 would NOT fit; 15 * 12 = 180 does
        local saved = vim.t.bufs
        local bufs = make_bufs(15)
        vim.t.bufs = bufs

        local out = modules.buffers({ order = { "buffers" } })

        vim.t.bufs = saved
        delete_bufs(bufs)

        assert.equals(15, chip_count(out))
      end
    )

    it(
      "still overflows (drops chips from the front) once even the minimum width doesn't fit",
      function()
        vim.o.columns = 300 -- 100 * 12 = 1200, nowhere near 300
        local saved = vim.t.bufs
        local bufs = make_bufs(100)
        vim.t.bufs = bufs

        local out = modules.buffers({ order = { "buffers" } })

        vim.t.bufs = saved
        delete_bufs(bufs)

        assert.is_true(chip_count(out) < 100)
      end
    )

    it("an explicit cfg.bufwidth still pins an exact width, auto-computation off", function()
      vim.o.columns = 300
      local saved = vim.t.bufs
      local bufs = make_bufs(3)
      vim.t.bufs = bufs

      -- 3 buffers at a pinned width of 101 each (303 total) don't fit in 300
      -- columns -- at least one must be dropped, proving the pinned value
      -- (not the auto min/max clamp, which would fit all 3 at width 24) drove
      -- the overflow decision.
      local out = modules.buffers({ order = { "buffers" }, bufwidth = 101 })

      vim.t.bufs = saved
      delete_bufs(bufs)

      assert.is_true(chip_count(out) < 3)
    end)
  end)
end)

describe("ui.tabline.utils.style_buf", function()
  local utils = require("ui.tabline.utils")

  it("escapes a literal %% in the buffer name so it cannot break 'tabline' syntax", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "50%done.lua")
    local saved = vim.t.bufs
    vim.t.bufs = { buf }

    local ok, chip = pcall(utils.style_buf, buf, 1, 21)

    vim.t.bufs = saved
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(ok, tostring(chip))
    assert.is_true(chip:find("50%%done", 1, true) ~= nil, chip)
    assert.is_nil(chip:find("50%done", 1, true))
  end)

  --- Regression for "the icon sits flush against the edge once the chip
  --- narrows" -- pad-1 used to reach 0 at the narrowest allowed width.
  it("always leaves at least one space before the icon, even at MIN_BUFWIDTH", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, "x.md")
    local saved = vim.t.bufs
    vim.t.bufs = { buf }

    local chip = utils.style_buf(buf, 1, 12) -- 12 == MIN_BUFWIDTH

    vim.t.bufs = saved
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    -- At least one literal space directly before the icon's own highlight
    -- group opens -- independent of nvim-web-devicons being present, and of
    -- which glyph it picks.
    assert.is_true(chip:find("%s%%#UiTbIcon_") ~= nil, chip)
  end)
end)

describe("ui.tabline.modules.buffers rounded caps", function()
  local modules = require("ui.tabline.modules")
  local utils = require("ui.tabline.utils")

  ---@param n integer
  ---@return integer[]
  local function make_bufs(n)
    local bufs = {}
    for _ = 1, n do
      bufs[#bufs + 1] = vim.api.nvim_create_buf(true, false)
    end
    return bufs
  end

  ---@param bufs integer[]
  local function delete_bufs(bufs)
    for _, b in ipairs(bufs) do
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end

  ---@param s string
  ---@param cap string
  ---@return integer
  local function cap_count(s, cap)
    return select(2, s:gsub(cap, cap))
  end

  it("squares both edges of a single-chip run -- nothing to round against", function()
    local saved = vim.t.bufs
    local bufs = make_bufs(1)
    vim.t.bufs = bufs

    local out = modules.buffers({ order = { "buffers" } })

    vim.t.bufs = saved
    delete_bufs(bufs)

    assert.equals(0, cap_count(out, utils.LEFT_CAP))
    assert.equals(0, cap_count(out, utils.RIGHT_CAP))
  end)

  it("rounds every boundary between chips, square only at the run's two outer edges", function()
    local saved = vim.t.bufs
    local bufs = make_bufs(4)
    vim.t.bufs = bufs

    local out = modules.buffers({ order = { "buffers" } })

    vim.t.bufs = saved
    delete_bufs(bufs)

    -- 4 chips -> 3 internal boundaries, one LEFT_CAP + one RIGHT_CAP each;
    -- the first chip's left edge and the last chip's right edge stay square.
    assert.equals(3, cap_count(out, utils.LEFT_CAP))
    assert.equals(3, cap_count(out, utils.RIGHT_CAP))
  end)
end)

describe("ui.tabline.utils click-flash", function()
  local utils = require("ui.tabline.utils")

  it("is_flashing is false for a buffer that was never flashed", function()
    local buf = vim.api.nvim_create_buf(true, false)
    assert.is_false(utils.is_flashing(buf))
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("flash() marks a buffer as flashing, then clears it after its timeout", function()
    local buf = vim.api.nvim_create_buf(true, false)

    utils.flash(buf)
    assert.is_true(utils.is_flashing(buf))

    vim.wait(300, function()
      return not utils.is_flashing(buf)
    end)
    assert.is_false(utils.is_flashing(buf))

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("style_buf renders the flash group for a mid-flash buffer", function()
    local buf = vim.api.nvim_create_buf(true, false)
    local saved = vim.t.bufs
    vim.t.bufs = { buf }

    utils.flash(buf)
    local chip = utils.style_buf(buf, 1, 21)

    vim.wait(300, function()
      return not utils.is_flashing(buf)
    end)
    vim.t.bufs = saved
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(chip:find("BufFlash", 1, true) ~= nil, chip)
  end)

  it("goto_buf flashes the target and still switches to it", function()
    local original = vim.api.nvim_get_current_buf()
    local buf = vim.api.nvim_create_buf(true, false)
    local saved = vim.t.bufs
    vim.t.bufs = { original, buf }

    utils.goto_buf(buf)

    assert.equals(buf, vim.api.nvim_get_current_buf())
    assert.is_true(utils.is_flashing(buf))

    vim.wait(300, function()
      return not utils.is_flashing(buf)
    end)
    vim.t.bufs = saved
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)
end)
