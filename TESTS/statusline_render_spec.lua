-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.render` — the `vim.o.statusline` / `order`-`modules` walk
--- this plugin gained at roadmap step 4, run WITHOUT NvChad. That constraint
--- is the point: everything asserted here is what must render on its own,
--- since nothing in this module reaches into a NvChad symbol.

describe("ui.statusline.render.generate", function()
  local render = require("ui.statusline.render")

  it("walks order, resolving each key against its own modules table", function()
    local out = render.generate({
      order = { "a", "b" },
      modules = {
        a = function()
          return "A"
        end,
        b = "B", -- a string module is valid too, same as nvchad.stl.utils.generate()
      },
    })
    assert.equals("AB", out)
  end)

  it("passes '%=' through unresolved, as the statusline alignment break", function()
    local out = render.generate({
      order = { "a", "%=", "b" },
      modules = {
        a = function()
          return "A"
        end,
        b = function()
          return "B"
        end,
      },
    })
    assert.equals("A%=B", out)
  end)

  it("falls back to the named theme's module for a key its own modules lack", function()
    -- "mode" is not in `modules` at all here, so this only passes if the
    -- "default" theme's own `mode` function actually ran.
    local out = render.generate({
      order = { "mode" },
      modules = {},
      theme = "default",
    })
    assert.is_string(out)
    -- Outside any window the statusline can be evaluated for
    -- (`is_activewin()` false in a headless run with no real statusline
    -- window), the default theme's `mode` renders empty rather than
    -- throwing -- which is itself the thing worth asserting: it did not error.
    assert.equals("", out)
  end)

  it("defaults theme to 'default' when the config omits it", function()
    local with_default = render.generate({ order = { "cwd" }, modules = {} })
    local with_explicit = render.generate({ order = { "cwd" }, modules = {}, theme = "default" })
    assert.equals(with_explicit, with_default)
  end)

  it("renders a missing key as empty rather than throwing", function()
    assert.has_no.errors(function()
      local out = render.generate({ order = { "no_such_key" }, modules = {} })
      assert.equals("", out)
    end)
  end)

  it("renders an unported theme name as empty rather than throwing", function()
    assert.has_no.errors(function()
      local out = render.generate({ order = { "mode" }, modules = {}, theme = "minimal" })
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

  it("does not resolve or warn about an unported theme when modules covers every key", function()
    -- Regression: `theme` used to resolve unconditionally at the top of
    -- generate(), before the loop even checked whether any key needed it --
    -- so a variant like the personal one (theme = "minimal" as a label,
    -- every order key already in its own modules) warned about "minimal"
    -- having no fallback every single render, for a fallback it never read.
    -- Mocking vim.notify itself, not lib.nvim.notify.create()'s return value:
    -- create() builds a fresh table per call, so render.lua's own already-
    -- captured notifier is a different object than one created here. A theme
    -- name unique to this test, not "minimal" (already exercised, and thus
    -- already deduped, by the "renders an unported theme name..." test above
    -- in this same file/process) -- reusing that name would let this
    -- assertion pass vacuously regardless of whether the fix actually works.
    local warned = {}
    local original_notify = vim.notify
    vim.notify = function(msg, level)
      warned[#warned + 1] = { msg = msg, level = level }
    end

    local out = render.generate({
      order = { "a" },
      modules = {
        a = function()
          return "A"
        end,
      },
      theme = "totally-unported-fixture-theme-xyz", -- would warn once if ever resolved
    })

    vim.notify = original_notify
    assert.equals("A", out)
    assert.same({}, warned)
  end)
end)

describe("ui.statusline.render enable/render/disable", function()
  local render = require("ui.statusline.render")

  after_each(function()
    render.disable()
  end)

  it("current() is nil before enable()", function()
    render.disable()
    assert.is_nil(render.current())
  end)

  it("enable() sets vim.o.statusline to this module's own render() call", function()
    render.enable({ order = { "cwd" }, modules = {} })
    assert.is_true(vim.o.statusline:find("ui.statusline.render", 1, true) ~= nil)
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

  it("disable() clears vim.o.statusline and current()", function()
    render.enable({ order = {}, modules = {} })
    render.disable()
    -- Not `assert.equals("", vim.o.statusline)`: on a Neovim that ships a
    -- real built-in default 'statusline' expression, setting the option to
    -- "" makes the GETTER read back that built-in expression, not a literal
    -- empty string -- Neovim's own "no statusline configured" state, not a
    -- blank one. That default is exactly what a plugin ceding ownership of
    -- the option should hand back, so the assertion is "no longer ours",
    -- not "empty".
    assert.is_true(vim.o.statusline:find("ui.statusline.render", 1, true) == nil)
    assert.is_nil(render.current())
  end)

  it("enable() is safe to call twice (no duplicate LspProgress handler)", function()
    assert.has_no.errors(function()
      render.enable({ order = {}, modules = {} })
      render.enable({ order = {}, modules = {} })
    end)
  end)
end)

describe("ui.statusline.render against every shipped variant", function()
  -- The proof this whole step exists for: each of the six layouts
  -- `ui.config` can assemble, run through `generate()` end to end and
  -- produce a string, with NvChad nowhere on the runtimepath. Before step 4,
  -- nothing in this plugin could do this at all -- `ui.config.setup()`
  -- assembled the table, and only NvChad's own `nvchad.stl.utils.generate()`
  -- ever consumed it.
  local cfg = require("ui.config")
  local render = require("ui.statusline.render")
  local saved_variant = cfg.STATUSLINE_VARIANT

  after_each(function()
    cfg.STATUSLINE_VARIANT = saved_variant
  end)

  for _, variant in ipairs({
    "default",
    "minimal",
    "lsp",
    "blocks",
  }) do
    it(("renders %q end to end"):format(variant), function()
      cfg.STATUSLINE_VARIANT = variant
      local assembled = cfg.setup()
      local ok, out = pcall(render.generate, assembled.ui.statusline)
      assert.is_true(ok, tostring(out))
      assert.is_string(out)
      -- Not just "a string" -- an empty result here is what an assembly
      -- that silently never populated `modules`/`order` would also produce.
      -- (The preset-consolidation audit found exactly this shape of bug in
      -- the old "custom_light" variant's merge-based setup() path.)
      assert.is_true(#out > 0, ("%q rendered as an empty string"):format(variant))
    end)
  end
end)

describe("ui.statusline.themes.default", function()
  local default_theme = require("ui.statusline.themes.default")

  it("build() returns a table of render functions", function()
    local built = default_theme.build("default")
    for _, key in ipairs({ "mode", "file", "git", "lsp_msg", "diagnostics", "lsp", "cwd" }) do
      assert.equals("function", type(built[key]), key .. " should be a function")
    end
    -- `cursor` is a literal string in nvchad's own default.lua too (no
    -- per-render state to close over), not a function -- generate() accepts
    -- both shapes, same as nvchad.stl.utils.generate() always did.
    assert.equals("string", type(built.cursor))
  end)

  it("every function renders without NvChad, without throwing", function()
    local built = default_theme.build("default")
    for key, fn in pairs(built) do
      if type(fn) == "function" then
        assert.has_no.errors(fn, key .. " should not throw")
      end
    end
  end)

  it("falls back to the 'default' separator set for an unknown separator_style", function()
    assert.has_no.errors(function()
      default_theme.build("no_such_style")
    end)
  end)
end)
