-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Pins, rendered: `ui.tabline.modules.buffers()` never dropping a pinned
--- chip under overflow, and `ui.tabline.utils`' click guard refusing to
--- close one by middle-click/"x". `ui.bindings.keymaps.tabufline.state`'s
--- own spec covers the `vim.t.bufs` invariant/list mechanics; this file is
--- what the tabline actually draws and does with a pin.

local state = require("ui.bindings.keymaps.tabufline.state")
local utils = require("ui.tabline.utils")
local modules = require("ui.tabline.modules")
local layout = require("ui.tabline.layout")

---@param n integer
---@return integer[]
local function make_bufs(n)
  local bufs = {}
  for i = 1, n do
    local b = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(b, ("pins-spec-%d.txt"):format(i))
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

describe("ui.tabline.modules.buffers with pins", function()
  local bufs

  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    bufs = make_bufs(8)
    vim.t.bufs = bufs
  end)

  after_each(function()
    delete_bufs(bufs)
    pcall(vim.cmd, "tabclose")
  end)

  it("a pinned chip renders even when it would otherwise overflow off the front", function()
    state.set_pinned(bufs[1], true)
    vim.api.nvim_set_current_buf(bufs[8]) -- forces the window toward the end

    -- Narrow the bar enough that not all 8 chips fit: bufwidth 20 * 8 far
    -- exceeds a typical column count, so the unpinned sliding window has to
    -- drop some -- the pinned one must not be among them.
    modules.buffers({ order = { "buffers" }, bufwidth = 20 })

    local rendered = layout.current()
    assert.is_true(
      vim.tbl_contains(rendered.bufs, bufs[1]),
      "pinned buffer missing from the render"
    )
    assert.equals(bufs[1], rendered.bufs[1]) -- pinned chips render first
  end)

  it("several pinned chips all stay visible, in pin order, ahead of the unpinned window", function()
    state.set_pinned(bufs[1], true)
    state.set_pinned(bufs[2], true)
    vim.api.nvim_set_current_buf(bufs[8])

    modules.buffers({ order = { "buffers" }, bufwidth = 20 })

    local rendered = layout.current()
    assert.equals(bufs[1], rendered.bufs[1])
    assert.equals(bufs[2], rendered.bufs[2])
  end)

  it("still keeps the current buffer visible among the unpinned ones", function()
    state.set_pinned(bufs[1], true)
    vim.api.nvim_set_current_buf(bufs[8])

    modules.buffers({ order = { "buffers" }, bufwidth = 20 })

    local rendered = layout.current()
    assert.is_true(vim.tbl_contains(rendered.bufs, bufs[8]))
  end)

  it("an unpinned tab renders normally when nothing is pinned", function()
    modules.buffers({ order = { "buffers" }, bufwidth = 10, bufwidth_min = 10, bufwidth_max = 10 })
    local rendered = layout.current()
    assert.is_true(#rendered.bufs > 0)
  end)
end)

describe("ui.tabline.utils pinned-chip click guard", function()
  local a
  local render = require("ui.tabline.render")

  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    a = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(a, "pins-click-spec.txt")
    vim.t.bufs = { a }
    render.enable({ order = {}, modules = {} })
    state.set_pinned(a, true)
  end)

  after_each(function()
    render.disable()
    pcall(vim.api.nvim_buf_delete, a, { force = true })
    pcall(vim.cmd, "tabclose")
  end)

  it("middle-click on a pinned chip does not close it", function()
    utils.on_chip_click(a, "m")
    vim.wait(200)
    assert.is_true(vim.api.nvim_buf_is_loaded(a))
  end)

  it("left-click on a pinned chip's close button does not close it", function()
    utils.on_close_click(a, "l")
    vim.wait(200)
    assert.is_true(vim.api.nvim_buf_is_loaded(a))
  end)

  it("on_pin_click unpins the chip", function()
    assert.is_true(state.is_pinned(a))
    utils.on_pin_click(a)
    assert.is_false(state.is_pinned(a))
  end)

  it("unpinning re-enables middle-click close", function()
    state.set_pinned(a, false)
    utils.on_chip_click(a, "m")
    vim.wait(1000, function()
      return not vim.api.nvim_buf_is_loaded(a)
    end)
    assert.is_false(vim.api.nvim_buf_is_loaded(a))
  end)
end)

describe("ui.tabline.utils.style_buf with a pinned buffer", function()
  local a

  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    a = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(a, "pins-style-spec.txt")
    vim.t.bufs = { a }
    state.set_pinned(a, true)
  end)

  after_each(function()
    pcall(vim.api.nvim_buf_delete, a, { force = true })
    pcall(vim.cmd, "tabclose")
  end)

  it("renders a UiTb*Pinned highlight group instead of Close/Modified", function()
    local chip = utils.style_buf(a, 1, 20)
    assert.is_not_nil(chip:find("Pinned", 1, true))
    assert.is_nil(chip:find("KillBuf", 1, true)) -- no close-click target on a pinned chip
    assert.is_not_nil(chip:find("TogglePin", 1, true))
  end)

  it("clicking that target through the click protocol unpins, not closes", function()
    utils.on_pin_click(a)
    assert.is_false(state.is_pinned(a))
    assert.is_true(vim.api.nvim_buf_is_loaded(a))
  end)
end)
