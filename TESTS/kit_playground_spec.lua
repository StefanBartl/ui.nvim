-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit_playground` (`:UI kit-playground`): every demo opens a window and its closer
--- takes every window it opened away again, without an error; every `ui.kit` module of
--- ui.nvim (the re-exports under `lua/ui/kit/`) is shown by some demo (or named in
--- `NOT_DEMOED` with a reason), so re-exporting a new kit primitive without a demo turns this
--- spec red; the playground list and the `:UI` route start demos.
---
--- The coverage check reads ui.nvim's own re-exports, not lib.nvim's `lua/lib/nvim/ui/kit/`:
--- CI pins lib.nvim at `ci-verified`, and a new module landing there must not turn ui.nvim red
--- before ui.nvim re-exports it (the re-export commit brings the demo along). Covers and
--- excuses may name a module of either repo (`hook` exists only in lib.nvim).

local playground = require("ui.kit_playground")
local api = vim.api

---@return integer
local function float_count()
  local n = 0
  for _, win in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_config(win).relative ~= "" then
      n = n + 1
    end
  end
  return n
end

---Floats and tabs as they are now, with the toasts a demo's answers leave taken away.
---@return integer floats, integer tabs
local function screen()
  require("ui.kit.toast").clear()
  return float_count(), #api.nvim_list_tabpages()
end

---@param key string
local function press(key)
  api.nvim_feedkeys(vim.keycode(key), "mx", false)
end

---Module names (file stems) matching a runtime glob.
---@param glob string
---@return table<string, true> names, integer count
local function module_names(glob)
  local names, count = {}, 0
  for _, file in ipairs(api.nvim_get_runtime_file(glob, true)) do
    names[vim.fn.fnamemodify(file, ":t:r")] = true
    count = count + 1
  end
  return names, count
end

describe("ui.kit_playground", function()
  local errors
  local real_notify

  before_each(function()
    errors = {}
    real_notify = vim.notify
    vim.notify = function(msg, level, ...)
      if level and level >= vim.log.levels.ERROR then
        errors[#errors + 1] = tostring(msg)
      end
      return real_notify(msg, level, ...)
    end
  end)

  after_each(function()
    vim.notify = real_notify
    require("ui.kit.toast").clear()
  end)

  for _, entry in ipairs(playground.entries()) do
    it(("demo %q opens and closes without an error"):format(entry.id), function()
      local floats0, tabs0 = screen()
      local close, err = playground.run(entry.id)
      assert.is_nil(err)
      assert.is_function(close)
      local opened = vim.wait(1000, function()
        return float_count() > floats0 or #api.nvim_list_tabpages() > tabs0
      end, 10)
      assert.is_true(opened, entry.id .. " opened no window")

      close()
      local closed = vim.wait(1000, function()
        local floats, tabs = screen()
        return floats == floats0 and tabs == tabs0
      end, 10)
      local floats, tabs = screen()
      assert.is_true(
        closed,
        ("%s left floats %d -> %d, tabs %d -> %d"):format(entry.id, floats0, floats, tabs0, tabs)
      )
      -- A second close is harmless (the playground closes nothing twice).
      assert.has_no.errors(close)
      vim.wait(50)
      assert.are.equal("", table.concat(errors, " | "))
    end)
  end

  it("ids are unique and every entry is complete", function()
    local seen = {}
    for _, entry in ipairs(playground.entries()) do
      assert.is_nil(seen[entry.id], "duplicate id " .. entry.id)
      seen[entry.id] = true
      assert.is_true(#entry.label > 0 and #entry.desc > 0 and #entry.covers > 0, entry.id)
      assert.is_function(entry.open, entry.id)
    end
  end)

  it("every ui.kit module is shown by a demo or excused in NOT_DEMOED", function()
    local covered = {}
    for _, entry in ipairs(playground.entries()) do
      for _, name in ipairs(entry.covers) do
        covered[name] = true
      end
    end
    local names, count = module_names("lua/ui/kit/*.lua")
    assert.is_true(count > 20, "kit modules found: " .. count)
    local missing = {}
    for name in pairs(names) do
      if not covered[name] and not playground.NOT_DEMOED[name] then
        missing[#missing + 1] = name
      end
    end
    table.sort(missing)
    assert.are.equal("", table.concat(missing, ", "))
  end)

  it("names only real kit modules (no stale cover or excuse)", function()
    local exists = module_names("lua/ui/kit/*.lua")
    for name in pairs(module_names("lua/lib/nvim/ui/kit/*.lua")) do
      exists[name] = true
    end
    local stale = {}
    for _, entry in ipairs(playground.entries()) do
      for _, name in ipairs(entry.covers) do
        if not exists[name] then
          stale[#stale + 1] = entry.id .. ":" .. name
        end
      end
    end
    for name in pairs(playground.NOT_DEMOED) do
      if not exists[name] then
        stale[#stale + 1] = "NOT_DEMOED:" .. name
      end
    end
    assert.are.equal("", table.concat(stale, ", "))
  end)

  it("run() of an unknown id opens nothing and says which ids exist", function()
    local floats0 = screen()
    local close, err = playground.run("no-such-demo")
    assert.is_nil(close)
    assert.matches("no%-such%-demo", err)
    assert.matches("confirm", err)
    assert.are.equal(floats0, float_count())
  end)

  it("the playground list shows every demo and a digit starts one", function()
    local floats0 = screen()
    local h = assert(playground.open())
    local lines = api.nvim_buf_get_lines(h.results.bufnr, 0, -1, false)
    assert.are.equal(#playground.entries(), #lines)
    local first = playground.entries()[1]
    assert.matches(first.id, lines[1], 1, true)

    -- `1` runs the first demo (theme presets: a kit.select of the presets).
    press("1")
    assert.is_true(vim.wait(1000, function()
      return require("ui.kit.chooser").is_open()
    end, 10))
    assert.is_false(h.results:is_valid())
    require("ui.kit.chooser").close()
    assert.is_true(vim.wait(1000, function()
      return float_count() == floats0
    end, 10))
    assert.are.equal("", table.concat(errors, " | "))
  end)

  it("presets: a pick opens a note in that preset, the default stays", function()
    local theme = require("ui.kit.theme")
    local default = theme.default()
    local floats0 = screen()
    local close = playground.run("presets")
    local chooser = require("ui.kit.chooser")
    local presets = theme.presets()
    local target = vim.fn.index(presets, "double") + 1
    assert.is_true(target > 0)
    chooser.move(target - (chooser.current_index() or 1))
    chooser.submit()
    local titles = {}
    local found = vim.wait(1000, function()
      titles = {}
      for _, win in ipairs(api.nvim_list_wins()) do
        local title = api.nvim_win_get_config(win).title
        if type(title) == "table" then
          titles[#titles + 1] = vim.trim(title[1][1])
        end
      end
      return vim.tbl_contains(titles, "double")
    end, 10)
    assert.is_true(found, table.concat(titles, ", "))
    assert.are.equal(default, theme.default())
    close()
    assert.is_true(vim.wait(1000, function()
      return float_count() == floats0
    end, 10))
  end)

  it("history: n records a stop, b and f walk the trail, c clears fn", function()
    local close = playground.run("history")
    local buf = api.nvim_get_current_buf()
    local function first()
      return api.nvim_buf_get_lines(buf, 0, 1, false)[1]
    end
    assert.are.equal("now: id=root fn=nil", first())
    press("n")
    press("n")
    assert.are.equal("now: id=node2 fn=fn2", first())
    press("b")
    assert.are.equal("now: id=node1 fn=fn1", first())
    press("f")
    assert.are.equal("now: id=node2 fn=fn2", first())
    press("c")
    assert.are.equal("now: id=node2 fn=nil", first())
    close()
    assert.are.equal("", table.concat(errors, " | "))
  end)

  describe(":UI kit-playground", function()
    pcall(function()
      require("ui.bindings.usrcmds").setup()
    end)

    it("with an id starts that demo", function()
      local floats0 = screen()
      vim.cmd("UI kit-playground surface")
      assert.is_true(float_count() > floats0)
      local win = api.nvim_get_current_win()
      assert.are.equal("Surface", api.nvim_win_get_config(win).title[1][1])
      api.nvim_win_close(win, true)
      assert.are.equal(floats0, float_count())
    end)

    it("without an id opens the playground list", function()
      local floats0 = screen()
      vim.cmd("UI kit-playground")
      assert.is_true(float_count() >= floats0 + 2) -- list + preview
      press("q")
      assert.is_true(vim.wait(1000, function()
        return float_count() == floats0
      end, 10))
    end)

    it("completes the demo ids", function()
      local got = vim.fn.getcompletion("UI kit-playground shor", "cmdline")
      assert.are.same({ "shortlist" }, got)
    end)

    it("an unknown id is reported as an error", function()
      pcall(vim.cmd, "UI kit-playground no-such-demo")
      assert.matches("no%-such%-demo", table.concat(errors, " | "))
    end)
  end)
end)
