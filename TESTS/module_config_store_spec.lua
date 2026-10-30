-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- The modules whose `setup()` goes through `ui.util.config` (`lib.lua.config.new`):
--- every call starts from the shipped defaults, an unknown key or a value of the
--- wrong type is reported and left out, and the user's own tables are copied.

local util_config = require("ui.util.config")

--- Run `fn` with `vim.notify` captured; returns the messages.
---@param fn fun()
---@return string[]
local function notified(fn)
  local seen = {}
  local saved = vim.notify
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.notify = function(msg)
    seen[#seen + 1] = tostring(msg)
  end
  local ok, err = pcall(fn)
  vim.notify = saved
  assert(ok, err)
  return seen
end

--- Whether one of `lines` contains `needle`.
---@param lines string[]
---@param needle string
---@return boolean
local function any(lines, needle)
  for _, line in ipairs(lines) do
    if line:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe("ui.util.config", function()
  it("lists only modules that expose issues()", function()
    for _, name in ipairs(util_config.MODULES) do
      assert.is_function(require(name).issues, name)
    end
  end)

  it("fills in name and a notify that warns with the module prefix", function()
    local store = util_config.new("ui.test", { a = 1 })
    local seen = notified(function()
      store.setup({ b = 2 })
    end)
    assert.is_true(any(seen, "[ui.test]"))
    assert.is_true(any(store.issues(), "'b'"))
  end)
end)

describe("ui.colorpicker setup()", function()
  local picker = require("ui.colorpicker")
  after_each(function()
    notified(function()
      picker.setup()
    end)
  end)

  it("starts from the defaults on every call", function()
    picker.setup({ hues = 12, rows = 5 })
    picker.setup({ rows = 3 })
    assert.equals(24, picker.config().hues)
    assert.equals(3, picker.config().rows)
  end)

  it("reports an unknown key and a wrong type, and keeps the default", function()
    local seen = notified(function()
      picker.setup({ huse = 12, rows = "7", cols = 0 })
    end)
    assert.equals(7, picker.config().rows)
    assert.equals(12, picker.config().cols)
    assert.is_true(any(picker.issues(), "did you mean 'hues'"))
    assert.is_true(any(picker.issues(), "rows"))
    assert.is_true(any(picker.issues(), "cols"))
    assert.is_true(any(seen, "[ui.colorpicker]"))
  end)
end)

describe("ui.keys setup()", function()
  local keys = require("ui.keys")
  after_each(function()
    keys.setup()
  end)

  it("does not keep groups or options of an earlier call", function()
    keys.setup({ mode = "x", groups = { ["<leader>a"] = "Alpha" } })
    keys.setup({ groups = { ["<leader>b"] = "Beta" } })
    assert.equals("n", keys.config().mode)
    assert.is_nil(keys.config().groups["<leader>a"])
    assert.equals("Beta", keys.config().groups["<leader>b"])
  end)

  it("copies the groups table instead of holding the caller's", function()
    local groups = { ["<leader>a"] = "Alpha" }
    keys.setup({ groups = groups })
    groups["<leader>a"] = "changed"
    assert.equals("Alpha", keys.config().groups["<leader>a"])
  end)

  it("reports a label that is not a string and an unknown key", function()
    notified(function()
      keys.setup({ groups = { ["<leader>a"] = 1 }, default_prefx = "," })
    end)
    assert.same({}, keys.config().groups)
    assert.equals("<leader>", keys.config().default_prefix)
    assert.is_true(any(keys.issues(), "groups"))
    assert.is_true(any(keys.issues(), "did you mean 'default_prefix'"))
  end)
end)

describe("ui.notify setup()", function()
  local notify = require("ui.notify")
  local levels = vim.log.levels
  after_each(function()
    notify.setup()
  end)

  it("starts from the defaults on every call", function()
    notify.setup({ history_size = 3, min_level = levels.ERROR })
    notify.setup({ history_size = 5 })
    assert.equals(5, notify.config().history_size)
    assert.equals(levels.INFO, notify.config().min_level)
  end)

  it("merges timeouts and titles per level and drops an earlier call's", function()
    notify.setup({ timeouts = { [levels.WARN] = 1 }, titles = { [levels.ERROR] = "Boom" } })
    notify.setup({ timeouts = { [levels.ERROR] = 2 } })
    local c = notify.config()
    assert.equals(5000, c.timeouts[levels.WARN])
    assert.equals(2, c.timeouts[levels.ERROR])
    assert.equals(3000, c.timeouts[levels.INFO])
    assert.equals("Error", c.titles[levels.ERROR])
  end)

  it("takes a timeouts table whose only key is level 1 as one level, not a list", function()
    notify.setup({ timeouts = { [levels.DEBUG] = 10 } })
    assert.equals(10, notify.config().timeouts[levels.DEBUG])
    assert.equals(3000, notify.config().timeouts[levels.INFO])
  end)

  it("takes level names for min_level and as table keys", function()
    notify.setup({ min_level = "warn", timeouts = { error = 1 }, titles = { Info = "FYI" } })
    local c = notify.config()
    assert.equals(levels.WARN, c.min_level)
    assert.equals(1, c.timeouts[levels.ERROR])
    assert.equals("FYI", c.titles[levels.INFO])
  end)

  it("reports a name that is no level, an unknown key and a wrong type", function()
    notified(function()
      notify.setup({
        min_level = "loud",
        timeouts = { nope = 1 },
        histroy_size = 3,
        history_size = "x",
      })
    end)
    local c = notify.config()
    assert.equals(levels.INFO, c.min_level)
    assert.equals(200, c.history_size)
    local issues = notify.issues()
    assert.is_true(any(issues, "loud"))
    assert.is_true(any(issues, '"nope"'))
    assert.is_true(any(issues, "did you mean 'history_size'"))
    assert.is_true(any(issues, "history_size"))
  end)

  it("rounds history_size down and rejects one below 1", function()
    notify.setup({ history_size = 3.7 })
    assert.equals(3, notify.config().history_size)
    notified(function()
      notify.setup({ history_size = 0 })
    end)
    assert.equals(200, notify.config().history_size)
  end)
end)

describe("ui.menu setup()", function()
  local menu = require("ui.menu")
  after_each(function()
    menu.setup({ mouse = false, key = false, prewarm = false })
  end)

  it("reports a misspelt entry name and a wrong type, and keeps the defaults", function()
    notified(function()
      menu.setup({
        mouse = false,
        key = 1,
        prewarm = false,
        entries = { delete_al = true },
        renderer = "fancy",
      })
    end)
    local c = menu.config()
    assert.is_false(c.key)
    assert.equals("kit", c.renderer)
    assert.is_false(c.entries.delete_all)
    local issues = menu.issues()
    assert.is_true(any(issues, "did you mean 'entries.delete_all'"))
    assert.is_true(any(issues, "key"))
    assert.is_true(any(issues, "renderer"))
  end)

  it("copies the user's tables instead of holding them", function()
    local hints = { save = "<C-s>" }
    menu.setup({ mouse = false, key = false, prewarm = false, hints = hints })
    hints.save = "changed"
    assert.equals("<C-s>", menu.config().hints.save)
  end)

  it("takes integrations as a boolean or a per-name table", function()
    menu.setup({ mouse = false, key = false, prewarm = false, integrations = { lsp = false } })
    assert.same({ lsp = false }, menu.config().integrations)
    assert.same({}, menu.issues())
  end)
end)

describe("ui.windowpicker setup()", function()
  local windowpicker = require("ui.windowpicker")
  after_each(function()
    windowpicker.setup()
  end)

  it("reports an unknown key and a wrong type, and keeps the default", function()
    notified(function()
      windowpicker.setup({ autoselect_on = false, chars = 5 })
    end)
    assert.is_nil(windowpicker.config().autoselect_on)
    assert.equals("FJDKSLA;CMRUEIWOQP", windowpicker.config().chars)
    assert.is_true(any(windowpicker.issues(), "did you mean 'autoselect_one'"))
    assert.is_true(any(windowpicker.issues(), "chars"))
  end)

  it("copies a filetype list instead of holding the caller's", function()
    local fts = { "a" }
    windowpicker.setup({ filetype = fts })
    fts[2] = "b"
    assert.same({ "a" }, windowpicker.config().filetype)
  end)
end)

describe("ui.zen setup()", function()
  local zen = require("ui.zen")
  after_each(function()
    zen.setup()
  end)

  it("reports an unknown key and an out-of-range value", function()
    notified(function()
      zen.setup({ widht = 80, backdrop = 2 })
    end)
    assert.equals(120, zen.config().width)
    assert.equals(0.6, zen.config().backdrop)
    assert.is_true(any(zen.issues(), "did you mean 'width'"))
    assert.is_true(any(zen.issues(), "backdrop"))
  end)

  it("merges wo into the default window options and takes any window option", function()
    zen.setup({ wo = { number = true, spell = true } })
    local wo = zen.config().wo
    assert.is_true(wo.number)
    assert.is_true(wo.spell)
    assert.equals("no", wo.signcolumn)
    assert.same({}, zen.issues())
  end)

  it("takes on_open/on_close as functions only", function()
    notified(function()
      zen.setup({ on_open = "nope" })
    end)
    assert.is_nil(zen.config().on_open)
    assert.is_true(any(zen.issues(), "on_open"))
  end)
end)

describe(":checkhealth ui module options", function()
  it("reports what a loaded module's last setup() ignored", function()
    local zen = require("ui.zen")
    notified(function()
      zen.setup({ widht = 80 })
    end)
    local calls = {}
    local saved = vim.health
    local function rec(level)
      return function(msg)
        calls[#calls + 1] = { level = level, msg = tostring(msg) }
      end
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.health = {
      start = rec("start"),
      ok = rec("ok"),
      info = rec("info"),
      warn = rec("warn"),
      error = rec("error"),
    }
    pcall(require("ui.health").check)
    vim.health = saved
    zen.setup()
    local found = false
    for _, c in ipairs(calls) do
      if c.level == "warn" and c.msg:find("ui.zen: ", 1, true) and c.msg:find("widht", 1, true) then
        found = true
      end
    end
    assert.is_true(found)
  end)
end)
