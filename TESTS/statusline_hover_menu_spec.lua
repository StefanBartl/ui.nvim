-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.layout` (column -> key hit-testing), `ui.statusline.hover`
--- (the `<MouseMove>` tooltip + fg recolor) and `ui.statusline.menu` (the
--- right/double-click "manage this module" menu) -- the three new pieces
--- behind the statusline hover popup and add/remove menu. `render.lua`'s own
--- side of the wiring (generic click wrap, hover recolor at redraw time) is
--- covered in `statusline_render_spec.lua`/`statusline_clickable_spec.lua`;
--- this file is the three modules on their own.

describe("ui.statusline.layout", function()
  local layout = require("ui.statusline.layout")

  it("returns nil before anything has been recorded for a winid", function()
    assert.is_nil(layout.key_at(999999, 1))
  end)

  it("finds the key at a column with no '%=' involved", function()
    local winid = vim.api.nvim_get_current_win()
    layout.record(winid, { "a", "b" }, { a = "AA", b = "BBB" })

    -- "AA" occupies columns 1-2, "BBB" columns 3-5.
    assert.equals("a", layout.key_at(winid, 1, 10))
    assert.equals("a", layout.key_at(winid, 2, 10))
    assert.equals("b", layout.key_at(winid, 3, 10))
    assert.equals("b", layout.key_at(winid, 5, 10))
  end)

  it("returns nil for a column past the end of the row", function()
    local winid = vim.api.nvim_get_current_win()
    layout.record(winid, { "a" }, { a = "AA" })

    assert.is_nil(layout.key_at(winid, 3, 10))
  end)

  it("resolves columns on both sides of a '%=' gap, and nil inside the gap", function()
    local winid = vim.api.nvim_get_current_win()
    -- Evaluated against a fixed maxwidth of 20: "left" (4 cols) then padding
    -- then "right" (5 cols) flush to column 20.
    layout.record(winid, { "left", "%=", "right" }, { left = "left", right = "right" })

    assert.equals("left", layout.key_at(winid, 1, 20))
    assert.equals("left", layout.key_at(winid, 4, 20))
    assert.is_nil(layout.key_at(winid, 10, 20)) -- inside the expanded gap
    assert.equals("right", layout.key_at(winid, 16, 20))
    assert.equals("right", layout.key_at(winid, 20, 20))
  end)

  it("skips a key that rendered empty -- no screen cells belong to it", function()
    local winid = vim.api.nvim_get_current_win()
    layout.record(winid, { "a", "empty", "b" }, { a = "A", empty = "", b = "B" })

    -- "A" at column 1, "B" at column 2 -- "empty" contributes nothing between them.
    assert.equals("a", layout.key_at(winid, 1, 10))
    assert.equals("b", layout.key_at(winid, 2, 10))
  end)

  it("keeps separate windows' layouts independent", function()
    -- `nvim_eval_statusline` needs a real window for context, so this uses
    -- an actual split rather than two made-up winids.
    local win_a = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local win_b = vim.api.nvim_get_current_win()

    layout.record(win_a, { "a" }, { a = "A" })
    layout.record(win_b, { "b" }, { b = "B" })

    local found_a = layout.key_at(win_a, 1, 10)
    local found_b = layout.key_at(win_b, 1, 10)

    pcall(vim.api.nvim_win_close, win_b, true)

    assert.equals("a", found_a)
    assert.equals("b", found_b)
  end)

  it(
    "survives a click-region-wrapped rendered string -- markers ignore it, widths stay right",
    function()
      local winid = vim.api.nvim_get_current_win()
      layout.record(winid, { "a", "b" }, {
        a = "%12@UiSlClick@AA%X",
        b = "%13@UiSlClick@BB%X",
      })

      assert.equals("a", layout.key_at(winid, 1, 10))
      assert.equals("a", layout.key_at(winid, 2, 10))
      assert.equals("b", layout.key_at(winid, 3, 10))
      assert.equals("b", layout.key_at(winid, 4, 10))
    end
  )

  it(
    "makes exactly one nvim_eval_statusline call per key_at(), regardless of order length or hit column",
    function()
      -- Regression guard: an earlier version re-evaluated each candidate
      -- key's own text in a SEPARATE `nvim_eval_statusline` call, which
      -- meant up to one extra call per module at or before the hovered
      -- column -- on every single `<MouseMove>` tick. `<MouseMove>` fires
      -- on every screen cell the pointer crosses, so this is real,
      -- continuously-paid cost, not a one-off.
      local winid = vim.api.nvim_get_current_win()
      local order, rendered = {}, {}
      for i = 1, 8 do
        local key = "k" .. i
        order[#order + 1] = key
        rendered[key] = "text" .. i
      end
      layout.record(winid, order, rendered)

      local calls = 0
      local original = vim.api.nvim_eval_statusline
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.api.nvim_eval_statusline = function(...)
        calls = calls + 1
        return original(...)
      end

      -- The rightmost key ("k8", "text8" at columns 36-40 -- 7 * len("textN")
      -- before it): the worst case for an implementation that walks
      -- candidates left to right and re-evaluates each one it passes.
      local found = layout.key_at(winid, 38, 50)

      vim.api.nvim_eval_statusline = original
      assert.equals("k8", found)
      assert.equals(1, calls)
    end
  )
end)

describe("ui.statusline.hover", function()
  local hover = require("ui.statusline.hover")

  after_each(function()
    hover.disable()
  end)

  it("current_key() is nil before anything is hovered", function()
    assert.is_nil(hover.current_key())
  end)

  it("enable() is idempotent and degrades silently without throwing", function()
    assert.has_no.errors(function()
      hover.enable()
      hover.enable()
    end)
  end)

  it("disable() is safe to call before enable()", function()
    assert.has_no.errors(function()
      hover.disable()
    end)
  end)

  it("pointer_target() returns nil when getmousepos() is not over a statusline row", function()
    local original = vim.fn.getmousepos
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.getmousepos = function()
      return {
        winid = vim.api.nvim_get_current_win(),
        line = 5,
        wincol = 3,
        winrow = 2,
        screenrow = 5,
        screencol = 3,
      }
    end

    local target = hover.pointer_target()

    vim.fn.getmousepos = original
    assert.is_nil(target)
  end)

  it(
    "pointer_target() resolves a per-window statusline row (line == 0, winrow == height + 1)",
    function()
      local winid = vim.api.nvim_get_current_win()
      local height = vim.api.nvim_win_get_height(winid)

      local original = vim.fn.getmousepos
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.fn.getmousepos = function()
        return {
          winid = winid,
          line = 0,
          wincol = 7,
          winrow = height + 1,
          screenrow = 99,
          screencol = 12,
        }
      end

      local target = hover.pointer_target()

      vim.fn.getmousepos = original
      assert.is_not_nil(target)
      assert.equals(winid, target.winid)
      assert.equals(7, target.col)
      assert.is_nil(target.maxwidth)
    end
  )
end)

describe("ui.statusline.menu", function()
  local menu = require("ui.statusline.menu")
  local render = require("ui.statusline.render")
  local catalog = require("ui.statusline.catalog")

  -- Same reasoning as `statusline_render_spec.lua`'s "enable/render/disable"
  -- describe: `render.enable()` restores a saved layout if one exists on
  -- disk, which would make these fixed-`order` assumptions
  -- (`{ "mode" }`, `in_order(cfg, "mode")`, ...) depend on whatever is
  -- actually saved on the machine running the suite. Stubbed to "nothing
  -- saved" here too; individual tests below still install their own
  -- narrower stub for `state.read`/`write`/`remove` where they actually
  -- exercise the save/load feature, which simply shadows this one for their
  -- own duration.
  local state_module = require("ui.statusline.state")
  local original_state_read = state_module.read

  ---@type string
  local extra_key
  before_each(function()
    ---@diagnostic disable-next-line: duplicate-set-field
    state_module.read = function()
      return nil
    end

    -- A catalog key that is not in any shipped preset's default `order`, so
    -- add/remove has something to actually toggle without disturbing a real
    -- module's state.
    for _, entry in ipairs(catalog) do
      if #entry.used_by == 0 then
        extra_key = entry.key
        break
      end
    end
    assert.is_not_nil(
      extra_key,
      "fixture assumption: at least one opt-in-only catalog entry exists"
    )

    render.enable({ order = { "mode" }, modules = {} })
  end)

  after_each(function()
    render.disable()
    state_module.read = original_state_read
  end)

  it("items() offers 'Remove' only for a key currently in order", function()
    local items = menu.items("mode")
    local labels = {}
    for _, item in ipairs(items) do
      labels[#labels + 1] = item.name
    end
    assert.is_true(vim.tbl_contains(labels, "Remove mode"))
  end)

  it("items() does not offer 'Remove' for a key not in order", function()
    local items = menu.items(extra_key)
    local labels = {}
    for _, item in ipairs(items) do
      labels[#labels + 1] = item.name
    end
    assert.is_false(vim.tbl_contains(labels, "Remove " .. extra_key))
  end)

  it("truncates a long, multi-byte summary on a character boundary, not a byte one", function()
    -- Regression guard: the "Add module" row used to measure/cut with
    -- `#`/`:sub` (byte count, byte index). A catalog summary containing a
    -- multi-byte glyph straddling the cut point -- several real ones do,
    -- e.g. the traffic-light emoji -- would have a lead byte sliced off its
    -- trailing continuation bytes, corrupting the label (same defect class
    -- `ui.statusline.modules.formatters`'s `ellipsize_middle` was fixed for;
    -- see TESTS/README.md). A fixture entry is used rather than relying on
    -- today's real catalog text landing exactly on the boundary by luck.
    local fixture_key = "zzz_test_multibyte_fixture"
    local summary = ("a"):rep(40) .. "🟢" .. ("b"):rep(10)
    table.insert(catalog, { key = fixture_key, summary = summary, builtin = false, used_by = {} })

    -- `catalog` is a shared module-level singleton (every spec in this
    -- process `require()`s the same table) -- a `pcall` here, cleaning the
    -- fixture up regardless of whether the body under test errors, is what
    -- keeps a failure in this one test from permanently polluting it for
    -- every test that runs afterward.
    local ok, label = pcall(function()
      local found
      for _, item in ipairs(menu.items("mode")) do
        if item.name == "Add module" then
          for _, sub in ipairs(item.items) do
            if sub.name:find(fixture_key, 1, true) == 1 then
              found = sub.name
            end
          end
        end
      end
      return found
    end)

    for i, entry in ipairs(catalog) do
      if entry.key == fixture_key then
        table.remove(catalog, i)
        break
      end
    end

    assert.is_true(ok, tostring(label))
    assert.equals(fixture_key .. " — " .. ("a"):rep(40) .. "🟢" .. "…", label)
  end)

  it("add_module (via the 'Add module' submenu) appends the key to the live order", function()
    local items = menu.items("mode")
    local add_submenu = nil
    for _, item in ipairs(items) do
      if item.name == "Add module" then
        add_submenu = item
      end
    end
    assert.is_not_nil(add_submenu)

    local entry = nil
    for _, sub in ipairs(add_submenu.items) do
      if sub.name:find(extra_key, 1, true) == 1 then
        entry = sub
      end
    end
    assert.is_not_nil(entry, ("no 'Add module' entry for %q"):format(extra_key))

    entry.cmd()

    assert.is_true(vim.tbl_contains(render.current().order, extra_key))
  end)

  it("remove (via 'Remove <key>') drops the key from the live order", function()
    local cfg = render.current()
    cfg.order[#cfg.order + 1] = extra_key
    -- A standalone catalog entry needs a real module or generate() warns;
    -- irrelevant to this test (only `order` membership is asserted), so a
    -- trivial stub is enough.
    cfg.modules[extra_key] = function()
      return ""
    end

    local items = menu.items(extra_key)
    local remove_entry = nil
    for _, item in ipairs(items) do
      if item.name == "Remove " .. extra_key then
        remove_entry = item
      end
    end
    assert.is_not_nil(remove_entry)

    remove_entry.cmd()

    assert.is_false(vim.tbl_contains(render.current().order, extra_key))
  end)

  it("open() draws through ui.contextmenu", function()
    local contextmenu = require("ui.contextmenu")
    local original_open = contextmenu.open
    local opened_with = nil
    ---@diagnostic disable-next-line: duplicate-set-field
    contextmenu.open = function(items)
      opened_with = items
    end

    menu.open("mode")
    contextmenu.open = original_open

    assert.equals("table", type(opened_with))
    assert.is_true(#opened_with > 0)
  end)

  it("pointer_on_statusline() is true when the pointer sits on an actual module", function()
    local hover = require("ui.statusline.hover")
    local layout = require("ui.statusline.layout")
    local original_target, original_key_at = hover.pointer_target, layout.key_at
    ---@diagnostic disable-next-line: duplicate-set-field
    hover.pointer_target = function()
      return { winid = 1, col = 1, maxwidth = nil, screenrow = 1, screencol = 1 }
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    layout.key_at = function()
      return "mode"
    end

    local result = menu.pointer_on_statusline()

    hover.pointer_target, layout.key_at = original_target, original_key_at
    assert.is_true(result)
  end)

  it(
    "pointer_on_statusline() is false on the statusline row but off any module -- "
      .. "e.g. the padding a '%=' expanded into, which has no click region for a "
      .. "host's replayed click to land on",
    function()
      local hover = require("ui.statusline.hover")
      local layout = require("ui.statusline.layout")
      local original_target, original_key_at = hover.pointer_target, layout.key_at
      ---@diagnostic disable-next-line: duplicate-set-field
      hover.pointer_target = function()
        return { winid = 1, col = 40, maxwidth = 80, screenrow = 1, screencol = 40 }
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      layout.key_at = function()
        return nil
      end

      local result = menu.pointer_on_statusline()

      hover.pointer_target, layout.key_at = original_target, original_key_at
      assert.is_false(result)
    end
  )

  it("pointer_on_statusline() is false when the pointer is not on the statusline at all", function()
    local hover = require("ui.statusline.hover")
    local original_target = hover.pointer_target
    ---@diagnostic disable-next-line: duplicate-set-field
    hover.pointer_target = function()
      return nil
    end

    local result = menu.pointer_on_statusline()

    hover.pointer_target = original_target
    assert.is_false(result)
  end)

  it("'Save current layout' is only offered when order is non-empty", function()
    render.current().order = {}
    assert.is_false(vim.tbl_contains(
      vim.tbl_map(function(i)
        return i.name
      end, menu.items("mode")),
      "Save current layout"
    ))
  end)

  it("'Clear saved layout' is only offered once something is actually saved", function()
    local state = require("ui.statusline.state")
    local original_read = state.read
    ---@diagnostic disable-next-line: duplicate-set-field
    state.read = function()
      return nil
    end

    local function has(items, name)
      return vim.tbl_contains(
        vim.tbl_map(function(i)
          return i.name
        end, items),
        name
      )
    end

    assert.is_false(has(menu.items("mode"), "Clear saved layout"))

    ---@diagnostic disable-next-line: duplicate-set-field
    state.read = function()
      return { order = { "mode" } }
    end
    assert.is_true(has(menu.items("mode"), "Clear saved layout"))

    state.read = original_read
  end)

  it("'Save current layout' writes ui.statusline.state, 'Clear saved layout' removes it", function()
    local state = require("ui.statusline.state")
    local written, removed = nil, false
    local original_write, original_remove, original_read = state.write, state.remove, state.read
    ---@diagnostic disable-next-line: duplicate-set-field
    state.write = function(order)
      written = order
      return true
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    state.remove = function()
      removed = true
      return true
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    state.read = function()
      return written and { order = written } or nil
    end

    local function find(items, name)
      for _, item in ipairs(items) do
        if item.name == name then
          return item
        end
      end
    end

    find(menu.items("mode"), "Save current layout").cmd()
    assert.same(render.current().order, written)

    find(menu.items("mode"), "Clear saved layout").cmd()
    assert.is_true(removed)

    state.write, state.remove, state.read = original_write, original_remove, original_read
  end)
end)

describe("ui.statusline.state", function()
  local state = require("ui.statusline.state")

  ---@return string, fun(): nil cleanup
  local function tmp_path()
    local path = vim.fn.tempname() .. ".json"
    return path, function()
      pcall(vim.fn.delete, path)
    end
  end

  it("read() returns nil when nothing is there", function()
    local path = tmp_path()
    assert.is_nil(state.read(path))
  end)

  it("round-trips an order through write() and read()", function()
    local path, cleanup = tmp_path()
    local ok = state.write({ "mode", "%=", "cwd" }, path)
    assert.is_true(ok)

    local saved = state.read(path)
    cleanup()

    assert.is_not_nil(saved)
    assert.same({ "mode", "%=", "cwd" }, saved.order)
  end)

  it("remove() deletes a file this module wrote", function()
    local path = tmp_path()
    state.write({ "mode" }, path)
    local ok = state.remove(path)
    assert.is_true(ok)
    assert.is_nil(state.read(path))
  end)

  it("remove() is not an error when nothing is there", function()
    local path = tmp_path()
    local ok = state.remove(path)
    assert.is_true(ok)
  end)

  it("read() ignores a file that is not JSON", function()
    local path, cleanup = tmp_path()
    vim.fn.writefile({ "not json at all" }, path)
    local saved = state.read(path)
    cleanup()
    assert.is_nil(saved)
  end)

  it("read() ignores non-string entries in a saved order", function()
    local path, cleanup = tmp_path()
    vim.fn.writefile({ vim.json.encode({ order = { "mode", 5, "cwd", vim.NIL } }) }, path)
    local saved = state.read(path)
    cleanup()
    assert.same({ "mode", "cwd" }, saved.order)
  end)

  it("write()/remove() refuse a path that holds a foreign JSON file", function()
    local path, cleanup = tmp_path()
    vim.fn.writefile({ vim.json.encode({ something_else = true }) }, path)

    local write_ok = state.write({ "mode" }, path)
    local remove_ok = state.remove(path)
    local survived = vim.uv.fs_stat(path) ~= nil
    cleanup()

    assert.is_false(write_ok)
    assert.is_false(remove_ok)
    assert.is_true(survived)
  end)

  it("read() treats an oversized file as corrupt rather than trusting it", function()
    local path, cleanup = tmp_path()
    local huge_order = {}
    for i = 1, 2000 do
      huge_order[i] = ("padding_%d_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"):format(i)
    end
    vim.fn.writefile({ vim.json.encode({ order = huge_order }) }, path)
    local saved = state.read(path)
    cleanup()
    assert.is_nil(saved)
  end)

  it("default_path() sits under stdpath('state')/ui.nvim", function()
    -- Compared normalized-to-normalized: `vim.fs.normalize` may rewrite
    -- separators (e.g. backslashes on Windows), so the raw `stdpath('state')`
    -- value is not always a literal substring of the normalized result.
    local normalized_state_dir = vim.fs.normalize(vim.fn.stdpath("state"))
    assert.is_true(state.default_path():find(normalized_state_dir, 1, true) ~= nil)
    assert.is_true(state.default_path():find("ui.nvim", 1, true) ~= nil)
  end)
end)

describe("ui.statusline.render's saved-layout restore", function()
  local render = require("ui.statusline.render")
  local state = require("ui.statusline.state")

  after_each(function()
    render.disable()
  end)

  it("enable() applies a saved order over the config's own one", function()
    local original_read = state.read
    ---@diagnostic disable-next-line: duplicate-set-field
    state.read = function()
      return { order = { "cwd", "mode" } }
    end

    render.enable({
      order = { "mode", "cwd" },
      modules = {
        mode = function()
          return "M"
        end,
        cwd = function()
          return "C"
        end,
      },
    })

    state.read = original_read
    assert.same({ "cwd", "mode" }, render.current().order)
  end)

  it("enable() leaves order alone when nothing was saved", function()
    local original_read = state.read
    ---@diagnostic disable-next-line: duplicate-set-field
    state.read = function()
      return nil
    end

    render.enable({ order = { "mode" }, modules = {} })

    state.read = original_read
    assert.same({ "mode" }, render.current().order)
  end)

  it(
    "enable() requires a standalone catalog module the saved order names but modules lacks",
    function()
      local original_read = state.read
      ---@diagnostic disable-next-line: duplicate-set-field
      state.read = function()
        return { order = { "undo_depth" } } -- a real, standalone catalog entry
      end

      render.enable({ order = { "mode" }, modules = {} })

      state.read = original_read
      assert.same({ "undo_depth" }, render.current().order)
      assert.equals("function", type(render.current().modules.undo_depth))
    end
  )

  it(
    "does NOT reapply the saved order on a second enable() within the same session -- "
      .. "regression: this used to make :UI variant (and menu add/remove) do nothing forever "
      .. "once any layout had ever been saved",
    function()
      local original_read = state.read
      ---@diagnostic disable-next-line: duplicate-set-field
      state.read = function()
        return { order = { "cwd" } }
      end

      -- First enable(): a real start, the save applies.
      render.enable({ order = { "mode" }, modules = {} })
      assert.same({ "cwd" }, render.current().order)

      -- A second enable() with a DIFFERENT order (":UI variant lsp", say) --
      -- must win, not be stomped back to the saved one.
      render.enable({ order = { "lsp" }, modules = {} })
      state.read = original_read

      assert.same({ "lsp" }, render.current().order)
    end
  )

  it(
    "re-applies the saved order after a disable()/enable() cycle -- that IS a new start",
    function()
      local original_read = state.read
      ---@diagnostic disable-next-line: duplicate-set-field
      state.read = function()
        return { order = { "cwd" } }
      end

      render.enable({ order = { "mode" }, modules = {} })
      render.disable()
      render.enable({ order = { "mode" }, modules = {} })

      state.read = original_read
      assert.same({ "cwd" }, render.current().order)
    end
  )
end)
