-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.chooser` takes `lib.nvim.window.printable_title` softly: `ui.kit` requires the
--- chooser eagerly, so a lib.nvim older than 863952e (no such module) must not make
--- `require("ui.kit")` fail outright; the title is then drawn as given.

describe("ui.kit.chooser without lib.nvim.window.printable_title", function()
  local saved = {}

  before_each(function()
    -- Everything else is loaded (and cached) first: only the chooser may meet the missing module.
    require("ui.kit")
    for _, name in ipairs({
      "lib.nvim.window.printable_title",
      "ui.kit.chooser",
      "ui.kit",
    }) do
      saved[name] = package.loaded[name]
      package.loaded[name] = nil
    end
    -- A loader that fails like a missing module does.
    saved.preload = package.preload["lib.nvim.window.printable_title"]
    package.preload["lib.nvim.window.printable_title"] = function()
      error("module 'lib.nvim.window.printable_title' not found")
    end
  end)

  after_each(function()
    package.preload["lib.nvim.window.printable_title"] = saved.preload
    for _, name in ipairs({
      "lib.nvim.window.printable_title",
      "ui.kit.chooser",
      "ui.kit",
    }) do
      package.loaded[name] = saved[name]
    end
  end)

  it("still loads ui.kit and the chooser", function()
    local ok, err = pcall(require, "ui.kit")
    assert.is_true(ok, tostring(err))
    local ok2, chooser = pcall(require, "ui.kit.chooser")
    assert.is_true(ok2, tostring(chooser))
    assert.is_table(chooser)
  end)
end)
