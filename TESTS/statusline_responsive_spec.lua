-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.render`'s `responsive`/`responsive_width` -- drop every
--- catalog key not tagged `essential` while the statusline's own window
--- (`vim.g.statusline_winid`) is narrower than the threshold, from
--- IDEEN-statusline.md's "Adaptive Segmentauswahl nach Fensterbreite". The
--- mechanism is a generic `essential` tag on `ui.statusline.catalog`
--- entries rather than a parallel "compact" `order` list per preset (the
--- design this idea explicitly rejects) -- these tests exercise it against
--- the REAL catalog (mode/cursor essential, git not), not a fake one.

local render = require("ui.statusline.render")

---@param width integer
---@return integer winid, fun(): nil restore
local function narrow_window(width)
  local original_win = vim.api.nvim_get_current_win()
  -- Headless Neovim defaults to 80 columns total -- too narrow to ever prove
  -- a "wide" case (a `width` above ~78 could not fit in a vsplit at all, and
  -- `nvim_win_set_width` would silently clamp instead of erroring). Widened
  -- generously and restored below so this file's own window-width fixture
  -- can never collide with a later test that assumes the 80-column default.
  local original_columns = vim.o.columns
  vim.o.columns = math.max(width * 2 + 10, 200)

  vim.cmd("vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_width(win, width)

  local original_statusline_winid = vim.g.statusline_winid
  vim.g.statusline_winid = win

  return win,
    function()
      vim.g.statusline_winid = original_statusline_winid
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_set_current_win, original_win)
      vim.o.columns = original_columns
    end
end

---@type table<string, fun(): string>
local FAKE_MODULES = {
  mode = function()
    return "M"
  end, -- catalog: essential = true
  git = function()
    return "G"
  end, -- catalog: essential unset (false)
  cursor = function()
    return "C"
  end, -- catalog: essential = true
}

describe("ui.statusline.render responsive mode", function()
  it("keeps every key when responsive is not set, regardless of window width", function()
    local _, restore = narrow_window(20)

    local out = render.generate({ order = { "mode", "git", "cursor" }, modules = FAKE_MODULES })

    restore()
    assert.equals("MGC", out)
  end)

  it("drops non-essential keys in a window narrower than responsive_width", function()
    local _, restore = narrow_window(20)

    local out = render.generate({
      order = { "mode", "git", "cursor" },
      modules = FAKE_MODULES,
      responsive = true,
      responsive_width = 80,
    })

    restore()
    assert.equals("MC", out)
  end)

  it("keeps every key when the window is wide enough", function()
    local _, restore = narrow_window(120)

    local out = render.generate({
      order = { "mode", "git", "cursor" },
      modules = FAKE_MODULES,
      responsive = true,
      responsive_width = 80,
    })

    restore()
    assert.equals("MGC", out)
  end)

  it("always keeps the '%=' alignment break even in compact mode", function()
    local _, restore = narrow_window(20)

    local out = render.generate({
      order = { "mode", "%=", "git" },
      modules = FAKE_MODULES,
      responsive = true,
      responsive_width = 80,
    })

    restore()
    assert.equals("M%=", out)
  end)

  it("keeps a key the catalog does not know about (a host's own custom module)", function()
    local _, restore = narrow_window(20)

    local out = render.generate({
      order = { "mode", "totally_custom_host_key" },
      modules = {
        mode = FAKE_MODULES.mode,
        totally_custom_host_key = function()
          return "X"
        end,
      },
      responsive = true,
      responsive_width = 80,
    })

    restore()
    assert.equals("MX", out)
  end)

  it("respects a custom responsive_width threshold", function()
    local _, restore = narrow_window(50)

    local out = render.generate({
      order = { "mode", "git" },
      modules = FAKE_MODULES,
      responsive = true,
      responsive_width = 40, -- 50 columns is NOT narrower than 40 -> stays wide
    })

    restore()
    assert.equals("MG", out)
  end)

  it(
    "degrades to the documented default (80) instead of crashing on a wrong-type responsive_width (ERR-22)",
    function()
      -- `should_go_compact()` used to read `cfg.responsive_width or 80`,
      -- which only caught an ABSENT value -- a wrong type reached the `<`
      -- comparison unguarded, and `M.render()` (the zero-argument
      -- entrypoint Neovim's own `'%!'` statusline option calls) has no
      -- pcall of its own around that call, unlike every per-module call
      -- inside `M.generate`'s `order` walk.
      local _, restore = narrow_window(50)

      local ok, out = pcall(render.generate, {
        order = { "mode", "git" },
        modules = FAKE_MODULES,
        responsive = true,
        responsive_width = "not-a-number", -- wrong type: documented as an integer
      })

      restore()
      assert.is_true(ok, tostring(out))
      -- 50 < the degraded default (80) -> compact mode, same as an absent
      -- responsive_width would produce -- not "never go compact", and not
      -- a thrown error either.
      assert.equals("M", out)
    end
  )
end)
