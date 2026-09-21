-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.utils.clickable` (the generic click layer) and the three
--- modules built on it: `diagnostics_clickable`, `git_clickable`, `variant`.
--- No NvChad on the runtimepath -- same constraint as every other spec here.

local clickable = require("ui.statusline.utils.clickable")

describe("ui.statusline.utils.clickable", function()
  it("wraps non-empty output in the %id@UiSlClick@...%X protocol", function()
    local render, id = clickable.wrap(function()
      return "hello"
    end, {})

    assert.equals("%" .. id .. "@UiSlClick@hello%X", render())
  end)

  it("returns empty output unwrapped -- nothing to click on", function()
    local render = clickable.wrap(function()
      return ""
    end, { l = function() end })

    assert.equals("", render())
  end)

  it("hands out distinct, increasing ids across separate wrap() calls", function()
    local _, id1 = clickable.wrap(function()
      return "a"
    end, {})
    local _, id2 = clickable.wrap(function()
      return "b"
    end, {})

    assert.is_true(id2 > id1)
  end)

  it("registers the UiSlClick global Vimscript function", function()
    assert.equals(1, vim.fn.exists("*UiSlClick"))
  end)

  it("_dispatch calls the handler for the clicked button", function()
    local called_with = nil
    local id = clickable.register({
      l = function()
        called_with = "l"
      end,
      r = function()
        called_with = "r"
      end,
    })

    clickable._dispatch(id, "r")
    assert.equals("r", called_with)
  end)

  it("_dispatch is a no-op for an unregistered id", function()
    assert.has_no.errors(function()
      clickable._dispatch(999999, "l")
    end)
  end)

  it("_dispatch is a no-op for a button the handler table does not cover", function()
    local id = clickable.register({
      l = function()
        error("should not run")
      end,
    })

    assert.has_no.errors(function()
      clickable._dispatch(id, "r")
    end)
  end)

  it("_dispatch swallows a handler error rather than propagating it", function()
    local id = clickable.register({
      l = function()
        error("boom")
      end,
    })

    assert.has_no.errors(function()
      clickable._dispatch(id, "l")
    end)
  end)

  it("_dispatch treats a missing clicks argument as a single click", function()
    local called_with = nil
    local id = clickable.register({
      l = function()
        called_with = "l"
      end,
      dbl = function()
        called_with = "dbl"
      end,
    })

    clickable._dispatch(id, "l")
    assert.equals("l", called_with)
  end)

  it("_dispatch prefers 'dbl' over 'l' when clicks is 2 or more", function()
    local called_with = nil
    local id = clickable.register({
      l = function()
        called_with = "l"
      end,
      dbl = function()
        called_with = "dbl"
      end,
    })

    clickable._dispatch(id, "l", 2)
    assert.equals("dbl", called_with)
  end)

  it("_dispatch falls back to 'l' on a double click when no 'dbl' handler exists", function()
    local called_with = nil
    local id = clickable.register({
      l = function()
        called_with = "l"
      end,
    })

    clickable._dispatch(id, "l", 2)
    assert.equals("l", called_with)
  end)

  it("_dispatch never treats 'dbl' as a fallback for a double right click", function()
    -- `dbl` is specifically the double-LEFT-click convention (Neovim's own
    -- `<2-LeftMouse>`) -- a double right click has no native equivalent this
    -- protocol carries, so it must keep resolving against `r`, never `dbl`.
    local called_with = nil
    local id = clickable.register({
      r = function()
        called_with = "r"
      end,
      dbl = function()
        called_with = "dbl"
      end,
    })

    clickable._dispatch(id, "r", 2)
    assert.equals("r", called_with)
  end)
end)

describe("ui.statusline.modules.diagnostics_clickable", function()
  local diagnostics_clickable = require("ui.statusline.modules.diagnostics_clickable")

  it("renders empty on a buffer with no diagnostics", function()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    assert.equals("", diagnostics_clickable())

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("wraps the diagnostics text in the click protocol once there is one", function()
    -- primitives.diagnostics() gates on `rawget(vim, "lsp")` -- ported
    -- verbatim from nvchad/stl/utils.lua, whose own author used it as a
    -- cheap "has anything in this session touched vim.lsp" proxy. `vim.lsp`
    -- is lazy-loaded via a metatable, so a bare headless run that never
    -- referenced it sees `rawget` come back nil -- touching it once here is
    -- what a normal editing session already does by the time a diagnostic
    -- exists at all.
    local _ = vim.lsp

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    vim.g.statusline_winid = vim.api.nvim_get_current_win()

    local ns = vim.api.nvim_create_namespace("statusline_clickable_spec")
    vim.diagnostic.set(ns, buf, {
      { lnum = 0, col = 0, message = "boom", severity = vim.diagnostic.severity.ERROR },
    })

    local out = diagnostics_clickable()

    vim.diagnostic.reset(ns, buf)
    vim.g.statusline_winid = nil
    pcall(vim.api.nvim_buf_delete, buf, { force = true })

    assert.is_true(out:find("@UiSlClick@", 1, true) ~= nil, out)
  end)

  it("left click runs vim.diagnostic.goto_next()", function()
    local original = vim.diagnostic.goto_next
    local called = false
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.diagnostic.goto_next = function()
      called = true
    end

    local _, id = clickable.wrap(require("ui.statusline.utils.primitives").diagnostics, {
      l = function()
        vim.diagnostic.goto_next()
      end,
    })
    clickable._dispatch(id, "l")

    vim.diagnostic.goto_next = original
    assert.is_true(called)
  end)

  it(
    "right click and double click both open ui.statusline.menu for 'diagnostics_clickable'",
    function()
      -- Neither button is claimed for this module's own purposes (only `l`
      -- is), so both fall to the generic "manage this module" menu -- wired
      -- directly in the module rather than through render.lua's generic wrap,
      -- since this module already carries its own click protocol.
      local _ = vim.lsp

      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      vim.g.statusline_winid = vim.api.nvim_get_current_win()

      local ns = vim.api.nvim_create_namespace("statusline_clickable_spec_rdbl")
      vim.diagnostic.set(ns, buf, {
        { lnum = 0, col = 0, message = "boom", severity = vim.diagnostic.severity.ERROR },
      })

      local out = diagnostics_clickable()
      local id = tonumber(out:match("^%%(%d+)@UiSlClick@"))

      vim.diagnostic.reset(ns, buf)
      vim.g.statusline_winid = nil
      pcall(vim.api.nvim_buf_delete, buf, { force = true })

      assert.is_not_nil(id, out)

      local menu = require("ui.statusline.menu")
      local original_open = menu.open
      local opened_with = {}
      ---@diagnostic disable-next-line: duplicate-set-field
      menu.open = function(key)
        opened_with[#opened_with + 1] = key
      end

      clickable._dispatch(id, "r")
      clickable._dispatch(id, "l", 2)
      menu.open = original_open

      assert.same({ "diagnostics_clickable", "diagnostics_clickable" }, opened_with)
    end
  )
end)

describe("ui.statusline.modules.git_clickable", function()
  -- Required once: `clickable.wrap` registers its handlers at require time,
  -- and the id that registration hands out never changes for this loaded
  -- module instance -- only what the handlers *do* depends on the mocks
  -- below. `require()` itself only ever returns one value regardless of how
  -- many its module chunk returns (Lua adjusts a require's result to one
  -- value -- see the reference manual's §6.3), so the id cannot come from a
  -- second return value the way `clickable.wrap` itself is tested above; it
  -- is parsed out of the rendered `%<id>@UiSlClick@...%X` text instead.
  local git_clickable = require("ui.statusline.modules.git_clickable")
  local saved_systemlist
  local click_id

  before_each(function()
    saved_systemlist = vim.fn.systemlist

    -- Fake gitsigns state so primitives.git() -- and therefore this
    -- module's wrapped render -- produces non-empty text. An empty render
    -- carries no click wrapper at all (see clickable.wrap's own doc
    -- comment on why), so there would be no id to parse.
    local buf = vim.api.nvim_get_current_buf()
    vim.b[buf].gitsigns_head = true
    vim.b[buf].gitsigns_status_dict = { head = "main" }
    vim.g.statusline_winid = vim.api.nvim_get_current_win()

    local out = git_clickable()
    click_id = tonumber(out:match("^%%(%d+)@UiSlClick@"))
    assert.is_not_nil(click_id, out)
  end)

  after_each(function()
    vim.fn.systemlist = saved_systemlist
    local buf = vim.api.nvim_get_current_buf()
    vim.b[buf].gitsigns_head = nil
    vim.b[buf].gitsigns_status_dict = nil
    vim.g.statusline_winid = nil
  end)

  it("left click opens vim.ui.select over the branch list when git succeeds", function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function(cmd)
      if vim.tbl_contains(cmd, "--show-current") then
        return { "main" }
      end
      return { "main", "feature/x" }
    end

    local original_select = vim.ui.select
    local seen_items, seen_opts
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(items, opts, _on_choice)
      seen_items, seen_opts = items, opts
    end

    clickable._dispatch(click_id, "l")
    vim.ui.select = original_select

    assert.same({ "main", "feature/x" }, seen_items)
    assert.is_true(seen_opts.prompt:find("main", 1, true) ~= nil)
  end)

  it("left click warns instead of opening a picker when there are no branches", function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function()
      return {}
    end

    local original_select = vim.ui.select
    local select_called = false
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function()
      select_called = true
    end

    assert.has_no.errors(function()
      clickable._dispatch(click_id, "l")
    end)
    vim.ui.select = original_select

    assert.is_false(select_called)
  end)

  -- `ui.contextmenu`, not `lib.nvim.contextmenu`. This module was the last
  -- caller of the pre-migration copy anywhere in the fleet, which mattered
  -- for more than tidiness: the lib copy has no `set_enabled`, so
  -- `ui.setup({ menu = false })` did not reach this menu. The last
  -- assertion is the regression guard for that.
  it("right click opens a ui.contextmenu", function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function()
      return { "main" }
    end

    local contextmenu = require("ui.contextmenu")
    local original_open = contextmenu.open
    local opened_with = nil
    ---@diagnostic disable-next-line: duplicate-set-field
    contextmenu.open = function(items)
      opened_with = items
    end

    clickable._dispatch(click_id, "r")
    contextmenu.open = original_open

    assert.equals("table", type(opened_with))
    assert.is_true(#opened_with > 0)
  end)

  it("right click honours ui.setup({ menu = false })", function()
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.systemlist = function()
      return { "main" }
    end

    local contextmenu = require("ui.contextmenu")
    local rendered = false
    local original_menu = require("ui.kit.menu").open
    ---@diagnostic disable-next-line: duplicate-set-field
    require("ui.kit.menu").open = function(...)
      rendered = true
      return original_menu(...)
    end

    contextmenu.set_enabled(false)
    clickable._dispatch(click_id, "r")
    contextmenu.set_enabled(true)
    require("ui.kit.menu").open = original_menu

    assert.is_false(rendered)
  end)

  it(
    "double click opens ui.statusline.menu for 'git_clickable' -- right click already owns the branch menu",
    function()
      local menu = require("ui.statusline.menu")
      local original_open = menu.open
      local opened_with = nil
      ---@diagnostic disable-next-line: duplicate-set-field
      menu.open = function(key)
        opened_with = key
      end

      clickable._dispatch(click_id, "l", 2)
      menu.open = original_open

      assert.equals("git_clickable", opened_with)
    end
  )

  -- ERR-11: "git succeeded but the repo is genuinely empty" and "git itself
  -- failed" used to collapse into the same warning. `vim.v.shell_error` is
  -- read-only from Lua, so a real `git` call in a real temp directory (not
  -- a systemlist stub) is what actually distinguishes the two cases here.
  describe("the two distinct 'no branches' cases (ERR-11)", function()
    ---@param dir string
    local function goto_dir(dir)
      local saved_cwd = vim.fn.getcwd()
      vim.cmd("lcd " .. vim.fn.fnameescape(dir))
      return saved_cwd
    end

    ---@return string
    local function capture_warning()
      local warned
      local original_notify = vim.notify
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.notify = function(msg)
        warned = tostring(msg)
      end
      clickable._dispatch(click_id, "l")
      vim.notify = original_notify
      assert.is_not_nil(warned, "expected switch_branch() to warn")
      return warned
    end

    it("warns 'no commits yet' when git succeeds on a genuinely empty repo", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      vim.fn.system({ "git", "init", dir })

      local saved_cwd = goto_dir(dir)
      local warned = capture_warning()
      vim.cmd("lcd " .. vim.fn.fnameescape(saved_cwd))
      vim.fn.delete(dir, "rf")

      assert.is_true(warned:find("no commits yet", 1, true) ~= nil, warned)
    end)

    it("warns with the underlying git error text when the git command itself fails", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p") -- a real directory, deliberately not a git repo

      local saved_cwd = goto_dir(dir)
      local warned = capture_warning()
      vim.cmd("lcd " .. vim.fn.fnameescape(saved_cwd))
      vim.fn.delete(dir, "rf")

      assert.is_true(warned:find("not a git repo", 1, true) ~= nil, warned)
      -- The real defect this closes: the two "empty" cases used to be
      -- indistinguishable from one another.
      assert.is_nil(warned:find("no commits yet", 1, true), warned)
    end)
  end)
end)

describe("ui.statusline.modules.variant", function()
  -- Same one-require, parse-the-id-from-render() reasoning as
  -- ui.statusline.modules.git_clickable above -- `render()` here is never
  -- empty (it always has at least "?" to show), so every test can rely on
  -- the id being present without first faking any state.
  local variant_module = require("ui.statusline.modules.variant")
  local click_id = tonumber((variant_module()):match("^%%(%d+)@UiSlClick@"))

  before_each(function()
    require("ui").setup({ all = true })
  end)

  it("has parsed a real click id out of its own render", function()
    assert.is_not_nil(click_id)
  end)

  it("renders the active variant's name", function()
    vim.cmd("UI variant minimal")
    assert.is_true(variant_module():find("minimal", 1, true) ~= nil)
  end)

  it("left click opens vim.ui.select over the registered variants", function()
    local original_select = vim.ui.select
    local seen_items
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(items, _opts, _on_choice)
      seen_items = items
    end

    clickable._dispatch(click_id, "l")
    vim.ui.select = original_select

    for _, expected in ipairs({ "default", "minimal", "lsp", "blocks" }) do
      assert.is_true(vim.tbl_contains(seen_items, expected), ("missing %q"):format(expected))
    end
  end)

  it("choosing a variant from the quick-switch runs :UI variant <name>", function()
    vim.cmd("UI variant default")

    local original_select = vim.ui.select
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.ui.select = function(_items, _opts, on_choice)
      on_choice("minimal")
    end

    clickable._dispatch(click_id, "l")
    vim.ui.select = original_select

    assert.equals("minimal", require("ui.config").get_variant())
  end)

  it("right click and double click both open ui.statusline.menu for 'variant'", function()
    local menu = require("ui.statusline.menu")
    local original_open = menu.open
    local opened_with = {}
    ---@diagnostic disable-next-line: duplicate-set-field
    menu.open = function(key)
      opened_with[#opened_with + 1] = key
    end

    clickable._dispatch(click_id, "r")
    clickable._dispatch(click_id, "l", 2)
    menu.open = original_open

    assert.same({ "variant", "variant" }, opened_with)
  end)
end)
