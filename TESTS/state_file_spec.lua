-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.util.state_file` -- the persistence `ui.context.state` and
--- `ui.statusline.state` share. Checked on a file of its own, so what is pinned
--- here is the shared behaviour, not either module's keys.

local state_file = require("ui.util.state_file")

describe("ui.util.state_file", function()
  local dir, default, file

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    default = dir .. "/default.json"
    file = state_file.new({
      default_path = function()
        return default
      end,
      own_keys = { a = true },
      max_bytes = 64,
      label = "demo",
      hint = " (hint)",
    })
  end)

  after_each(function()
    vim.fn.delete(dir, "rf")
  end)

  it("round-trips a table and removes it again", function()
    local path = dir .. "/mine.json"
    assert.is_true(file.write(path, { a = 1 }))
    assert.same({ a = 1 }, file.read(path))
    assert.is_true(file.remove(path))
    assert.is_nil(file.read(path))
    assert.is_true(file.remove(path), "a missing file is not an error")
  end)

  it("reads nothing from an absent, empty, corrupt or oversized file", function()
    local path = dir .. "/x.json"
    assert.is_nil(file.read(path))
    vim.fn.writefile({ "" }, path)
    assert.is_nil(file.read(path))
    vim.fn.writefile({ "{ half a json" }, path)
    assert.is_nil(file.read(path))
    vim.fn.writefile({ vim.json.encode({ a = string.rep("x", 100) }) }, path)
    assert.is_nil(file.read(path))
  end)

  it("refuses to replace or delete a foreign file, and says how to avoid it", function()
    local path = dir .. "/foreign.json"
    vim.fn.writefile({ vim.json.encode({ other = 1 }) }, path)
    local ok, err = file.write(path, { a = 1 })
    assert.is_false(ok)
    assert.is_truthy(
      err:find("not a ui.nvim demo state file, so it is not overwritten (hint)", 1, true)
    )
    ok, err = file.remove(path)
    assert.is_false(ok)
    assert.is_truthy(err:find("so it is not deleted (hint)", 1, true))
    assert.same({ other = 1 }, vim.json.decode(table.concat(vim.fn.readfile(path), "\n")))
  end)

  it("never touches a directory", function()
    local path = dir .. "/subdir"
    vim.fn.mkdir(path, "p")
    assert.is_false(file.write(path, { a = 1 }))
    assert.is_false(file.remove(path))
  end)

  it("owns its default location whatever it holds", function()
    vim.fn.writefile({ "-- anything at all" }, default)
    assert.is_true(file.write(default, { a = 2 }))
    assert.same({ a = 2 }, file.read(default))
  end)

  it("is the one implementation behind both state modules", function()
    for _, rel in ipairs({ "lua/ui/context/state.lua", "lua/ui/statusline/state.lua" }) do
      local path = vim.api.nvim_get_runtime_file(rel, false)[1]
      local src = table.concat(vim.fn.readfile(path), "\n")
      assert.is_truthy(src:find("ui.util.state_file", 1, true), rel .. " uses the shared helper")
      assert.is_nil(
        src:find("local function may_touch", 1, true),
        rel .. " keeps no copy of may_touch"
      )
    end
  end)
end)
