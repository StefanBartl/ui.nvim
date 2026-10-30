---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `:UI` and `:Theme` are lib.nvim composer verbs: every subcommand is a route with a text for the help float,
--- `<Tab>` completes what the hand-built `complete()` used to complete, and the handlers still get the words
--- as typed. A lib.nvim older than `help.undocumented` (the argument texts) fails the suite by name
--- instead of skipping it (NEW-43).

local composer = require("lib.nvim.bindings.usercmd.composer")

local supported = type(composer.help) == "table" and type(composer.help.undocumented) == "function"

---@param line string
---@return string[]
local function complete(line)
  return vim.fn.getcompletion(line, "cmdline")
end

---@param list string[]
---@param word string
---@return boolean
local function has(list, word)
  return vim.tbl_contains(list, word)
end

describe(":UI and :Theme as composer verbs", function()
  if not supported then
    it("needs a lib.nvim with argument texts", function()
      error("lib.nvim lacks composer.help.undocumented: update lib.nvim")
    end)
    return
  end

  pcall(function()
    require("ui.bindings.usrcmds").setup()
  end)

  it("registers both verbs with the help float on", function()
    local registry = composer.registry()
    assert.is_truthy(registry.UI, ":UI is a composer verb")
    assert.is_truthy(registry.Theme, ":Theme is a composer verb")
    assert.is_true(registry.UI:spec().help)
    assert.is_true(registry.Theme:spec().help)
  end)

  it("leaves no route, flag or argument without a text", function()
    local missing = {}
    for _, verb in ipairs({ "UI", "Theme" }) do
      for _, m in ipairs(composer.help.undocumented(verb, { args = true })) do
        missing[#missing + 1] = ("%s %s %s %s"):format(verb, m.route, m.kind, m.name)
      end
    end
    assert.are.equal("", table.concat(missing, ", "))
  end)

  it("gives every subcommand a route (the old registry's 24 names, plus kit-playground)", function()
    local names = {}
    for _, route in ipairs(composer.registry().UI:spec().routes) do
      names[#names + 1] = route.path[1]
    end
    table.sort(names)
    local expected = {
      "color",
      "context",
      "help",
      "keys",
      "kit-playground",
      "kit-preset",
      "kit-presets",
      "modules",
      "notify",
      "picker",
      "progress",
      "screenkey",
      "slots",
      "status",
      "sticky",
      "tabline-style",
      "tabline-styles",
      "theme",
      "themes",
      "toggle",
      "transparency",
      "variant",
      "variants",
      "winpick",
      "zen",
    }
    -- A failure names the route that is new or gone, not just "tables differ".
    local missing = vim.tbl_filter(function(name)
      return not vim.tbl_contains(names, name)
    end, expected)
    local unexpected = vim.tbl_filter(function(name)
      return not vim.tbl_contains(expected, name)
    end, names)
    assert.is_true(
      #missing == 0 and #unexpected == 0,
      ("missing routes: [%s]; routes not in this list: [%s]"):format(
        table.concat(missing, ", "),
        table.concat(unexpected, ", ")
      )
    )
    assert.are.same(expected, names)
  end)

  it("builds the args of every route fresh (no table shared between routes)", function()
    local seen, shared = {}, {}
    local function walk(label, value)
      if type(value) ~= "table" then
        return
      end
      if seen[value] then
        shared[#shared + 1] = ("%s = %s"):format(label, seen[value])
        return
      end
      seen[value] = label
      for k, v in pairs(value) do
        walk(label .. "." .. tostring(k), v)
      end
    end
    for _, route in ipairs(composer.registry().UI:spec().routes) do
      walk(route.path[1], route.args)
    end
    assert.are.equal("", table.concat(shared, "; "))
  end)

  describe(":UI help is generated from the routes", function()
    local text = require("ui.bindings.usrcmds").help_text()

    it("names every route with its text", function()
      local missing = {}
      for _, route in ipairs(composer.registry().UI:spec().routes) do
        if
          not text:find(":UI " .. route.path[1], 1, true) or not text:find(route.desc, 1, true)
        then
          missing[#missing + 1] = route.path[1]
        end
      end
      assert.are.equal("", table.concat(missing, ", "))
    end)

    it("lists the documented values of an argument", function()
      assert.is_truthy(text:find(":UI transparency on", 1, true))
      assert.is_truthy(text:find(":UI sticky depth", 1, true))
      assert.is_truthy(text:find(":UI notify history", 1, true))
    end)

    it(":UI help prints it", function()
      local seen = {}
      local original = vim.notify
      vim.notify = function(msg)
        seen[#seen + 1] = tostring(msg)
      end
      local ok, err = pcall(vim.cmd, "UI help")
      vim.notify = original
      assert.is_true(ok, tostring(err))
      assert.are.equal(1, #seen)
      assert.is_truthy(seen[1]:find(text, 1, true), "the printed text is not the generated one")
    end)
  end)

  describe("<Tab> completion keeps what complete() offered", function()
    it("subcommands", function()
      local out = complete("UI th")
      assert.is_true(has(out, "theme") and has(out, "themes"))
      assert.is_true(has(complete("UI "), "kit-preset"))
    end)

    it("on/off for the toggles, and the notify actions", function()
      assert.are.same({ "off", "on" }, vim.fn.sort(complete("UI transparency ")))
      assert.are.same({ "off", "on" }, vim.fn.sort(complete("UI zen ")))
      assert.is_true(has(complete("UI notify "), "history"))
    end)

    it("the sticky actions and their third word", function()
      assert.is_true(has(complete("UI sticky "), "depth"))
      assert.is_true(has(complete("UI context "), "reset"))
      assert.is_true(has(complete("UI sticky depth "), "all"))
      assert.is_true(has(complete("UI sticky lines "), "lua"))
    end)

    it("the slots words", function()
      assert.is_true(has(complete("UI slots "), "toggle"))
    end)

    it("colorschemes for :UI theme and :Theme, the registries for variant and styles", function()
      local themes = require("ui.bindings.usrcmds.themes").list_themes()
      assert.is_true(#themes > 0)
      assert.is_true(has(complete("UI theme "), themes[1]))
      assert.is_true(has(complete("Theme "), themes[1]))
      assert.is_true(has(complete("UI variant "), require("ui.config.variants").list()[1]))
      assert.is_true(has(complete("UI tabline-style "), require("ui.tabline.styles").list()[1]))
      assert.is_true(has(complete("UI kit-preset "), require("ui.kit.theme").presets()[1]))
    end)
  end)

  describe("the handlers still read the words as typed", function()
    it(":UI transparency on / off set the state", function()
      local theme = require("ui.bindings.usrcmds.themes")
      vim.cmd("UI transparency on")
      assert.is_true(theme.get_transparency())
      vim.cmd("UI transparency off")
      assert.is_false(theme.get_transparency())
    end)

    it(":Theme <name> switches like :UI theme <name>", function()
      local original = vim.g.colors_name
      local target = "habamax"
      pcall(vim.cmd, "Theme " .. target)
      local switched = vim.g.colors_name
      -- Put things back before asserting, also when no colorscheme was set before.
      if original and original ~= target then
        pcall(vim.cmd, "colorscheme " .. original)
      elseif not original then
        vim.cmd("highlight clear")
        vim.g.colors_name = nil
      end
      assert.are.equal(target, switched)
      assert.are.equal(original, vim.g.colors_name)
    end)
  end)
end)
