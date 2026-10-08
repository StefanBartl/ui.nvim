-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.chooser` takes `lib.nvim.window.printable_title` softly: `ui.kit` requires the
--- chooser eagerly, so a lib.nvim older than 863952e (no such module) must not make
--- `require("ui.kit")` fail outright; the title is then drawn as given.

local api = vim.api

---@return string|nil
local function frame_title()
  for _, w in ipairs(api.nvim_list_wins()) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == "lib-kit-chooser" then
      local cfg = api.nvim_win_get_config(w)
      return cfg.title and cfg.title[1] and cfg.title[1][1] or nil
    end
  end
end

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

  it("draws the title as given, without a warning, when the module is simply missing", function()
    local warned = {}
    local real_notify = vim.notify
    vim.notify = function(msg)
      warned[#warned + 1] = msg
    end
    local chooser = require("ui.kit.chooser")
    vim.notify = real_notify
    assert.same({}, warned, "a missing module is the supported older-lib.nvim case: silent")

    local raw = "my\tfile"
    chooser.open({ items = { "a", "b" }, title = "top", on_select = function() end })
    assert.is_true(chooser.set_items({ items = { "c" }, title = raw }))
    assert.equals(raw, frame_title(), "the title reaches the frame unchanged")
    chooser.close()
  end)

  it("warns once and falls back when the module is present but fails to load", function()
    package.preload["lib.nvim.window.printable_title"] = function()
      error("boom in printable_title")
    end
    local warned = {}
    local real_notify = vim.notify
    vim.notify = function(msg)
      warned[#warned + 1] = msg
    end
    local ok, chooser = pcall(require, "ui.kit.chooser")
    vim.notify = real_notify
    assert.is_true(ok, tostring(chooser))
    assert.equals(1, #warned, "exactly one warning")
    assert.is_truthy(warned[1]:find("boom in printable_title", 1, true), "it names the cause")

    local raw = "my\tfile"
    chooser.open({ items = { "a", "b" }, title = "top", on_select = function() end })
    assert.is_true(chooser.set_items({ items = { "c" }, title = raw }))
    assert.equals(raw, frame_title(), "the title still reaches the frame, as given")
    chooser.close()
  end)

  it("treats a nested missing module as a load error, not as 'not installed'", function()
    package.preload["lib.nvim.window.printable_title"] = function()
      error("module 'some.other.dep' not found")
    end
    local warned = {}
    local real_notify = vim.notify
    vim.notify = function(msg)
      warned[#warned + 1] = msg
    end
    local ok = pcall(require, "ui.kit.chooser")
    vim.notify = real_notify
    assert.is_true(ok)
    assert.equals(1, #warned)
  end)
end)
