-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, duplicate-set-field

--- `ui.tabline.scroll` -- the auto-scroll window override a tabline drag
--- arms by holding the pointer at either edge of the chip run -- and its
--- read side in `ui.tabline.modules.buffers()`. `ui.tabline.layout`'s own
--- `chip_run_bounds` and the drag/edge-arming behaviour itself are covered
--- in TESTS/tabline_layout_drag_spec.lua; this file is the offset/nudge
--- mechanics and what `modules.buffers()` does with them.

local scroll = require("ui.tabline.scroll")
local layout = require("ui.tabline.layout")
local state = require("ui.bindings.keymaps.tabufline.state")
local modules = require("ui.tabline.modules")

---@param n integer
---@return integer[]
local function make_bufs(n)
  local bufs = {}
  for i = 1, n do
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(b, ("scroll-spec-%d.txt"):format(i))
    bufs[#bufs + 1] = b
  end
  return bufs
end

---@param bufs integer[]
local function delete_bufs(bufs)
  for _, b in ipairs(bufs) do
    pcall(vim.api.nvim_buf_delete, b, { force = true })
  end
end

describe("ui.tabline.scroll", function()
  after_each(function()
    scroll.reset()
  end)

  it("offset() is nil until something nudges it", function()
    assert.is_nil(scroll.offset())
  end)

  it("reset() clears the offset and stops the timer", function()
    layout.record("", { 10, 11, 12 }, { "aaaa", "aaaa", "aaaa" }) -- 12 columns wide
    state.setup()
    vim.cmd("tabnew")
    local bufs = make_bufs(5)
    vim.t.bufs = bufs

    scroll.on_drag(1) -- left edge -- arms the timer
    assert.is_true(scroll.is_active())

    scroll.reset()
    assert.is_false(scroll.is_active())
    assert.is_nil(scroll.offset())

    delete_bufs(bufs)
    pcall(vim.cmd, "tabclose")
  end)

  it("on_drag disarms when chip_run_bounds has nothing rendered", function()
    layout.record("", {}, {})
    assert.has_no.errors(function()
      scroll.on_drag(5)
    end)
    assert.is_false(scroll.is_active())
  end)

  it("nudges the offset forward while held at the right edge, then clamps", function()
    state.setup()
    vim.cmd("tabnew")
    local bufs = make_bufs(5) -- total_unpinned() == 5, offset clamps to [0, 4]
    vim.t.bufs = bufs
    layout.record("", { bufs[1] }, { ("a"):rep(20) }) -- right edge at column 20

    scroll.on_drag(20) -- at the right edge -- arms a rightward nudge
    assert.is_true(scroll.is_active())

    vim.wait(2000, function()
      return (scroll.offset() or 0) >= 4
    end)
    assert.equals(4, scroll.offset()) -- clamped to total - 1, never past it

    scroll.reset()
    delete_bufs(bufs)
    pcall(vim.cmd, "tabclose")
  end)

  it("a pinned buffer does not count toward the unpinned offset's range", function()
    state.setup()
    vim.cmd("tabnew")
    local bufs = make_bufs(3)
    vim.t.bufs = bufs
    state.set_pinned(bufs[1], true) -- 2 unpinned left: offset clamps to [0, 1]
    layout.record("", { bufs[1] }, { ("a"):rep(20) })

    scroll.on_drag(20)
    vim.wait(2000, function()
      return (scroll.offset() or 0) >= 1
    end)
    assert.equals(1, scroll.offset())

    scroll.reset()
    delete_bufs(bufs)
    pcall(vim.cmd, "tabclose")
  end)
end)

describe("ui.tabline.modules.buffers with scroll.offset()", function()
  after_each(function()
    scroll.reset()
  end)

  it(
    "renders the unpinned window starting at the offset instead of following the current buffer",
    function()
      state.setup()
      vim.cmd("tabnew")
      local bufs = make_bufs(5)
      vim.t.bufs = bufs
      vim.api.nvim_set_current_buf(bufs[1]) -- current is the FIRST buffer

      -- A wide-enough offset that "keep current visible" would show buf 1,
      -- but the scroll override should show only what starts at bufs[4].
      local offset = 3
      -- `M.on_drag`/nudge is timer-driven and not what this test wants to
      -- exercise -- it goes through the SAME state `M.offset()` reads, so
      -- reaching in via `on_drag` + `vim.wait` (as the spec above does) would
      -- just be a slower way to set the same thing. This test is about
      -- `modules.buffers()`'s own read side, so it drives the offset directly
      -- through the one real entry point that ever sets it (`on_drag`, via a
      -- pointer held at the edge for long enough to reach it).
      layout.record("", { bufs[1] }, { ("a"):rep(20) })
      scroll.on_drag(20)
      vim.wait(2000, function()
        return (scroll.offset() or 0) >= offset
      end)

      modules.buffers({ order = { "buffers" }, bufwidth = 10 })
      local rendered = layout.current()

      assert.equals(bufs[4], rendered.bufs[1])

      scroll.reset()
      delete_bufs(bufs)
      pcall(vim.cmd, "tabclose")
    end
  )

  it("falls back to keeping the current buffer visible once the offset is reset", function()
    state.setup()
    vim.cmd("tabnew")
    local bufs = make_bufs(5)
    vim.t.bufs = bufs
    vim.api.nvim_set_current_buf(bufs[5])

    scroll.reset()
    assert.is_nil(scroll.offset())

    modules.buffers({ order = { "buffers" }, bufwidth = 10, bufwidth_min = 10, bufwidth_max = 10 })
    local rendered = layout.current()

    assert.is_true(vim.tbl_contains(rendered.bufs, bufs[5]))

    delete_bufs(bufs)
    pcall(vim.cmd, "tabclose")
  end)
end)
