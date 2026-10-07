-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.slots.resolve` -- placeholder substitution.

local resolve = require("ui.slots.resolve")

describe("ui.slots.resolve", function()
  local ctx = {
    file = "/p/a.lua",
    dir = "/p",
    root = "/p",
    cwd = "/w",
    line = 12,
    col = 3,
    word = "foo",
    sel = "picked",
    clip = "clipped",
    count = 4,
  }

  it("knows the ten placeholders", function()
    assert.same(
      { "file", "dir", "root", "cwd", "line", "col", "word", "sel", "clip", "count" },
      resolve.NAMES
    )
  end)

  it("substitutes every one of them", function()
    for _, name in ipairs(resolve.NAMES) do
      local out, unknown = resolve.resolve("<{" .. name .. "}>", ctx)
      assert.equals("<" .. tostring(ctx[name]) .. ">", out)
      assert.same({}, unknown)
    end
  end)

  it("substitutes several in one text, repeated ones included", function()
    local out = resolve.resolve("{file}:{line}:{col} {file}", ctx)
    assert.equals("/p/a.lua:12:3 /p/a.lua", out)
  end)

  it("leaves unknown names in the text and reports each once", function()
    local out, unknown = resolve.resolve("{file} {nope} {nope} {other}", ctx)
    assert.equals("/p/a.lua {nope} {nope} {other}", out)
    assert.same({ "nope", "other" }, unknown)
  end)

  it("leaves text that only looks like a placeholder alone", function()
    local out, unknown = resolve.resolve("{ file } {} { {file}", ctx)
    assert.equals("{ file } {} { /p/a.lua", out)
    assert.same({}, unknown)
  end)

  it("reads a function value only when its placeholder is used", function()
    local calls = 0
    local lazy = {
      clip = function()
        calls = calls + 1
        return "x"
      end,
      file = "f",
    }
    resolve.resolve("{file}", lazy)
    assert.equals(0, calls)
    resolve.resolve("{clip}{clip}", lazy)
    assert.equals(2, calls)
  end)

  it("substitutes an empty string for a value that is missing or whose function raises", function()
    local out = resolve.resolve("[{file}][{word}]", {
      word = function()
        error("boom")
      end,
    })
    assert.equals("[][]", out)
  end)

  it("applies escape to every substituted value and only to those", function()
    local seen = {}
    local out = resolve.resolve("a|{word}|{line}", ctx, {
      escape = function(value, name)
        seen[#seen + 1] = name
        return (value:gsub("|", "\\|"))
      end,
    })
    assert.equals("a|foo|12", out)
    assert.same({ "word", "line" }, seen)

    local hostile = resolve.resolve("echo {word}", { word = "x | y" }, {
      escape = function(value)
        return (value:gsub("|", "\\|"))
      end,
    })
    assert.equals("echo x \\| y", hostile)
  end)

  it("keeps the plain value when escape raises or returns a non-string", function()
    assert.equals(
      "foo",
      resolve.resolve("{word}", ctx, {
        escape = function()
          error("boom")
        end,
      })
    )
    assert.equals(
      "foo",
      resolve.resolve("{word}", ctx, {
        escape = function()
          return 5
        end,
      })
    )
  end)

  it("reads {{ and }} as literal braces", function()
    assert.equals("{file}", (resolve.resolve("{{file}}", ctx)))
    assert.equals("{/p/a.lua}", (resolve.resolve("{{{file}}}", ctx)))
    assert.equals("a { b } c", (resolve.resolve("a {{ b }} c", ctx)))
    local out, unknown = resolve.resolve("{{nope}} {nope}", ctx)
    assert.equals("{nope} {nope}", out)
    assert.same({ "nope" }, unknown)
  end)

  it("has_placeholder() tells a placeholder from an escaped brace", function()
    assert.is_true(resolve.has_placeholder("a {file} b"))
    assert.is_true(resolve.has_placeholder("{nope}"))
    assert.is_false(resolve.has_placeholder("{{file}}"))
    assert.is_false(resolve.has_placeholder("plain"))
    assert.is_false(resolve.has_placeholder(nil))
    assert.is_true(resolve.has_placeholder("{{{file}}}"))
  end)

  it("unknown() does not count an escaped name", function()
    assert.same({}, resolve.unknown("{{nope}}"))
    assert.same({ "nope" }, resolve.unknown("{{a}} {nope}"))
  end)

  it("does not evaluate anything: braces around code stay text", function()
    local out, unknown = resolve.resolve("{os.execute('x')} {vim.fn.getcwd()}", ctx)
    assert.equals("{os.execute('x')} {vim.fn.getcwd()}", out)
    assert.same({}, unknown)
  end)

  it("returns an empty string for a non-string text", function()
    assert.equals("", (resolve.resolve(nil, ctx)))
    assert.equals("", (resolve.resolve(12, ctx)))
  end)

  it("unknown() lists the unknown names without resolving", function()
    assert.same({ "a", "b" }, resolve.unknown("{file} {a} {b} {a}"))
    assert.same({}, resolve.unknown("{file}"))
    assert.same({}, resolve.unknown(nil))
  end)

  describe("context()", function()
    local buf, win

    before_each(function()
      vim.cmd("enew")
      buf = vim.api.nvim_get_current_buf()
      win = vim.api.nvim_get_current_win()
      vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "_slots_ctx.txt")
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "hello world here" })
      vim.api.nvim_win_set_cursor(win, { 2, 6 })
    end)

    after_each(function()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("reads file, dir, line, col and word from the editor", function()
      local c = resolve.context()
      local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
      assert.equals(name, c.file())
      assert.equals(vim.fs.dirname(name), c.dir())
      assert.equals(2, c.line())
      assert.equals(7, c.col())
      assert.equals("world", c.word())
    end)

    it("uses the count it was given, else v:count", function()
      assert.equals(9, resolve.context(9).count())
      assert.equals(0, resolve.context().count())
    end)

    it("gives empty strings for an unnamed buffer", function()
      vim.cmd("enew")
      local c = resolve.context()
      assert.equals("", c.file())
      assert.equals("", c.dir())
    end)

    it("resolves through the real context", function()
      local out = resolve.resolve("{line}/{col}/{word}")
      assert.equals("2/7/world", out)
    end)

    it("returns the text of the last visual selection", function()
      vim.api.nvim_win_set_cursor(win, { 2, 0 })
      vim.cmd("normal! veey")
      assert.equals("hello world", resolve.context().sel())
    end)
  end)
end)
