-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.slots.kinds.expand` -- the slot that folds a float of look-up text out and in.

local config = require("ui.slots.config")
local registry = require("ui.slots.kinds.registry")
local store = require("ui.slots.store")

describe("ui.slots.kinds.expand", function()
  local dir
  local expand

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    registry.reset()
    store.reset()
    config.setup({ data_dir = dir .. "/data", save_delay_ms = 0 })
    store.reload()
    expand = require("ui.slots.kinds.expand")
  end)

  after_each(function()
    for n = 1, 9 do
      expand.close(n)
    end
    registry.reset()
    store.reset()
    config.reset()
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  ---@return integer[] floating windows
  local function floats()
    return vim.tbl_filter(function(w)
      return vim.api.nvim_win_get_config(w).relative ~= ""
    end, vim.api.nvim_list_wins())
  end

  ---@param name string
  ---@param lines string[]
  ---@return string
  local function make_file(name, lines)
    local path = dir .. "/" .. name
    vim.fn.writefile(lines, path)
    return path
  end

  describe("validate", function()
    it("needs a path or a fn, not both and not none", function()
      assert.is_truthy(registry.validate({ kind = "expand" }))
      assert.is_truthy(registry.validate({ kind = "expand", path = "a", fn = function() end }))
      assert.is_nil(registry.validate({ kind = "expand", path = "a" }))
      assert.is_nil(registry.validate({ kind = "expand", fn = function() end }))
    end)

    it("refuses a string fn and wrong field types", function()
      assert.is_truthy(registry.validate({ kind = "expand", fn = "os.exit()" }))
      assert.is_truthy(registry.validate({ kind = "expand", path = "" }))
      assert.is_truthy(registry.validate({ kind = "expand", path = "a", title = 1 }))
      assert.is_truthy(registry.validate({ kind = "expand", path = "a", ft = {} }))
    end)

    it("takes a network path only from setup()", function()
      assert.is_truthy(registry.validate({ kind = "expand", path = "\\\\host\\share\\a.md" }))
      assert.is_nil(
        registry.validate({ kind = "expand", path = "\\\\host\\share\\a.md", fixed = true })
      )
    end)

    it("is not a kind a data file may hold", function()
      assert.is_false(registry.persists("expand"))
      assert.is_false(vim.tbl_contains(config.get().persistable_kinds, "expand"))
    end)
  end)

  describe("apply", function()
    it(
      "opens a read-only float with the text of a file and closes it on the second apply",
      function()
        local path =
          make_file("acr.md", { "API  application programming interface", "CPU  central" })
        local slot = { kind = "expand", path = path, n = 3 }
        assert.is_true((registry.apply(slot)))
        local wins = floats()
        assert.equals(1, #wins)
        local buf = vim.api.nvim_win_get_buf(wins[1])
        assert.same(
          { "API  application programming interface", "CPU  central" },
          vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        )
        assert.is_false(vim.bo[buf].modifiable)
        assert.is_true((registry.apply(slot)))
        assert.equals(0, #floats())
      end
    )

    it("closes with q", function()
      local path = make_file("acr.md", { "one" })
      assert.is_true((registry.apply({ kind = "expand", path = path, n = 1 })))
      assert.equals(1, #floats())
      vim.api.nvim_feedkeys("q", "x", false)
      assert.equals(0, #floats())
      -- a new apply opens it again
      assert.is_true((registry.apply({ kind = "expand", path = path, n = 1 })))
      assert.equals(1, #floats())
    end)

    it("shows what fn returns, a list or a string, and hands it the slot number", function()
      local seen
      local slot = {
        kind = "expand",
        n = 2,
        fn = function(ctx)
          seen = ctx.n
          return "a\nb\r\nc"
        end,
      }
      assert.is_true((registry.apply(slot)))
      local buf = vim.api.nvim_win_get_buf(floats()[1])
      assert.equals(2, seen)
      assert.same({ "a", "b", "c" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    end)

    it("says why when the source is missing", function()
      local ok, err = registry.apply({ kind = "expand", path = dir .. "/none.md", n = 1 })
      assert.is_false(ok)
      assert.matches("does not exist", err)
      assert.equals(0, #floats())
    end)

    it("fails clearly when fn raises or returns nothing usable", function()
      local ok, err = registry.apply({
        kind = "expand",
        n = 1,
        fn = function()
          error("boom")
        end,
      })
      assert.is_false(ok)
      assert.matches("boom", err)
      ok, err = registry.apply({ kind = "expand", n = 1, fn = function() end })
      assert.is_false(ok)
      assert.matches("no text", err)
      ok, err = registry.apply({
        kind = "expand",
        n = 1,
        fn = function()
          return {}
        end,
      })
      assert.is_false(ok)
      assert.matches("nothing to show", err)
      assert.equals(0, #floats())
    end)

    it("shows a NUL byte as ^@ and cuts at preview.max_lines", function()
      config.setup({ data_dir = dir .. "/data", preview = { max_lines = 3 } })
      local path = dir .. "/n.txt"
      local fd = io.open(path, "wb")
      fd:write("a\0b\nl2\nl3\nl4\nl5\n")
      fd:close()
      assert.is_true((registry.apply({ kind = "expand", path = path, n = 1 })))
      local buf = vim.api.nvim_win_get_buf(floats()[1])
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals("a^@b", lines[1])
      assert.equals(4, #lines)
      assert.matches("cut here", lines[4])
    end)
  end)

  describe("render", function()
    it(
      "names the file, dims a missing one, and does not touch the file system when cheap",
      function()
        local path = make_file("acr.md", { "x" })
        local r = registry.render({ kind = "expand", path = path })
        assert.equals("acr.md", r.label)
        assert.is_false(r.missing)
        r = registry.render({ kind = "expand", path = dir .. "/gone.md" })
        assert.is_true(r.missing)
        r = registry.render({ kind = "expand", path = dir .. "/gone.md" }, { cheap = true })
        assert.is_false(r.missing)
        assert.equals("expand", registry.render({ kind = "expand", fn = function() end }).label)
        assert.equals(
          "Acronyms",
          registry.render({ kind = "expand", fn = print, title = "Acronyms" }).label
        )
      end
    )
  end)

  describe("data file", function()
    it("does not keep an expand slot in the data file", function()
      local path = make_file("acr.md", { "x" })
      store.add({ kind = "expand", path = path }, 1)
      store.add({ kind = "file", path = path }, 2)
      assert.is_true(store.flush())
      local text = table.concat(vim.fn.readfile(store.path(), "b"), " ")
      assert.is_truthy(text:find("file", 1, true))
      assert.is_nil(text:find("expand", 1, true))
    end)
  end)
end)
