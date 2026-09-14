-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.recommender_badge` -- a count of recommender.nvim
--- alias suggestions open for the current buffer, from
--- IDEEN-statusline.md's "Segmente, die dieses Ökosystem einzigartig
--- machen" bucket. recommender.nvim is not on this suite's runtimepath (a
--- soft dependency, same contract as casedesk/filetree_cwd_mode/
--- github_stats_badge/runtime_analysis_ampel), so every "installed" test
--- injects fake `recommender.config`/`recommender.analyzers.<name>` modules.

local badge = require("ui.statusline.modules.recommender_badge")

---@param cfg table
local function install_config(cfg)
  package.loaded["recommender.config"] = {
    get = function()
      return cfg
    end,
  }
end

---@param name string
---@param analyze_fn fun(threshold, custom_aliases, blacklist): table[]
local function install_analyzer(name, analyze_fn)
  package.loaded["recommender.analyzers." .. name] = { analyze = analyze_fn }
end

local function uninstall(name)
  package.loaded["recommender.config"] = nil
  package.loaded["recommender.analyzers." .. (name or "regex")] = nil
end

describe("ui.statusline.modules.recommender_badge", function()
  it("renders empty when recommender.nvim is not installed", function()
    uninstall()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    local out = badge()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.equals("", out)
  end)

  it("renders empty when there are zero suggestions", function()
    install_config({ analyzer = "regex", threshold = 3 })
    install_analyzer("regex", function()
      return {}
    end)

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    local out = badge()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.equals("", out)
  end)

  it("uses singular wording for exactly one suggestion", function()
    install_config({ analyzer = "regex", threshold = 3 })
    install_analyzer("regex", function()
      return { { chain = "vim.api.nvim_buf_get_lines", count = 3, alias = "local x = y" } }
    end)

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    local out = badge()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("1 Alias-Vorschlag ", 1, true) ~= nil, out)
    assert.is_nil(out:find("Alias-Vorschläge", 1, true))
  end)

  it("uses plural wording and shows the count for several suggestions", function()
    install_config({ analyzer = "regex", threshold = 3 })
    install_analyzer("regex", function()
      return {
        { chain = "vim.api.nvim_buf_get_lines", count = 3, alias = "" },
        { chain = "vim.api.nvim_buf_set_lines", count = 4, alias = "" },
      }
    end)

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    local out = badge()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("2 Alias-Vorschläge für diese Datei offen", 1, true) ~= nil, out)
  end)

  it("passes the configured analyzer/threshold/custom_aliases/blacklist through", function()
    local custom_aliases = { ["vim.api"] = "api" }
    local blacklist = { "vim.fn" }
    install_config({
      analyzer = "treesitter",
      threshold = 5,
      custom_aliases = custom_aliases,
      blacklist = blacklist,
    })
    install_analyzer("treesitter", function(threshold, aliases, bl)
      assert.equals(5, threshold)
      assert.equals(custom_aliases, aliases)
      assert.equals(blacklist, bl)
      return {}
    end)

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    badge()

    uninstall("treesitter")
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("caches the analysis per buffer until the buffer changes", function()
    install_config({ analyzer = "regex", threshold = 3 })
    local calls = 0
    install_analyzer("regex", function()
      calls = calls + 1
      return { { chain = "a.b.c", count = 3, alias = "" } }
    end)

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)

    badge()
    badge()
    badge()
    assert.equals(1, calls)

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "changed" })
    badge()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.equals(2, calls)
  end)
end)
