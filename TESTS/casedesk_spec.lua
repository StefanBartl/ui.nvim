-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.casedesk` -- current case's short label + company
--- + reply count, plus an SLA urgency badge (docs/SLA.md §6C, already
--- shipped by casedesk.nvim itself). casedesk.nvim is not on this suite's
--- runtimepath (a soft dependency, same contract as filetree_cwd_mode/
--- github_stats_badge/runtime_analysis_ampel/recommender_badge), so every
--- "in a case" test injects fake `casedesk.resolve`/`casedesk.meta`/
--- `casedesk.sla`/`casedesk.config` modules.
---
--- Every test gives its buffer a distinct name: the module caches its
--- output keyed by (bufname, time bucket), and every unnamed test buffer
--- shares the same empty name, which would let one test see another's
--- cached text instead of calling its own mocks (the exact bug
--- TESTS/github_stats_badge_spec.lua's cache note already describes for a
--- sibling module).

local casedesk = require("ui.statusline.modules.casedesk")

---@param entry { dir: string, short: string }|nil
local function install_resolve(entry)
  package.loaded["casedesk.resolve"] = {
    sync = function()
      return entry
    end,
  }
end

---@param m table|nil
local function install_meta(m)
  package.loaded["casedesk.meta"] = {
    read = function()
      return m
    end,
  }
end

---@param status table|nil
---@param worst table|nil
---@param under_threshold boolean
local function install_sla(status, worst, under_threshold)
  package.loaded["casedesk.sla"] = {
    status = function()
      return status
    end,
    most_urgent = function()
      return worst
    end,
    under_threshold = function()
      return under_threshold
    end,
    format_duration = function(seconds)
      return tostring(seconds) .. "s"
    end,
  }
end

---@param active_priorities string[]
local function install_config(active_priorities)
  package.loaded["casedesk.config"] = {
    sla_active_priorities = active_priorities,
    sla_warn_at = 0.25,
  }
end

local function uninstall()
  package.loaded["casedesk.resolve"] = nil
  package.loaded["casedesk.meta"] = nil
  package.loaded["casedesk.sla"] = nil
  package.loaded["casedesk.config"] = nil
end

---@param name string
---@param n_replies integer|nil
---@return string dir
local function make_case_dir(name, n_replies)
  local dir = vim.fn.tempname() .. "_" .. name
  vim.fn.mkdir(dir .. "/Replies", "p")
  for i = 1, n_replies or 0 do
    local f = io.open(dir .. "/Replies/reply_" .. i .. ".md", "w")
    if f then
      f:write("x")
      f:close()
    end
  end
  return dir
end

---@param buf integer
---@param name string
local function set_buf_name(buf, name)
  vim.api.nvim_buf_set_name(buf, "/tmp/casedesk_" .. name)
end

describe("ui.statusline.modules.casedesk", function()
  it("renders empty when casedesk.nvim is not installed", function()
    uninstall()
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "not_installed")

    local out = casedesk()

    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.equals("", out)
  end)

  it("renders empty when the buffer isn't inside a known case", function()
    install_resolve(nil)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "no_case")

    local out = casedesk()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.equals("", out)
  end)

  it(
    "shows short label, company and reply count with no SLA badge when priority has no SLA level",
    function()
      local dir = make_case_dir("no_sla", 2)
      install_resolve({ dir = dir, short = "CASE-1" })
      install_meta({ company = "Acme" })
      install_sla(nil, nil, false)
      install_config({ "1", "2" })

      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_set_current_buf(buf)
      set_buf_name(buf, "no_sla")

      local out = casedesk()

      uninstall()
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      assert.is_true(out:find("CASE-1 Acme", 1, true) ~= nil, out)
      assert.is_true(out:find("2 replies", 1, true) ~= nil, out)
      assert.is_nil(out:find("SLA", 1, true))
    end
  )

  it("uses singular 'reply' for exactly one reply", function()
    local dir = make_case_dir("singular", 1)
    install_resolve({ dir = dir, short = "CASE-2" })
    install_meta(nil)
    install_sla(nil, nil, false)
    install_config({})

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "singular")

    local out = casedesk()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("1 reply ", 1, true) ~= nil, out)
    assert.is_nil(out:find("replies", 1, true))
  end)

  it("omits the company when meta has none", function()
    local dir = make_case_dir("no_company", 0)
    install_resolve({ dir = dir, short = "CASE-3" })
    install_meta(nil)
    install_sla(nil, nil, false)
    install_config({})

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "no_company")

    local out = casedesk()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("CASE-3 ", 1, true) ~= nil, out)
    assert.is_nil(out:find("CASE-3 nil", 1, true))
  end)

  it("hides the SLA badge when the priority isn't in sla_active_priorities", function()
    local dir = make_case_dir("inactive_prio", 0)
    install_resolve({ dir = dir, short = "CASE-4" })
    install_meta(nil)
    install_sla({ digit = "3" }, { remaining = 60, budget = 3600 }, true)
    install_config({ "1", "2" })

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "inactive_prio")

    local out = casedesk()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_nil(out:find("SLA", 1, true))
  end)

  it("hides the SLA badge while the clock is healthy (not under warn threshold)", function()
    local dir = make_case_dir("healthy", 0)
    install_resolve({ dir = dir, short = "CASE-5" })
    install_meta(nil)
    install_sla({ digit = "1" }, { remaining = 10000, budget = 14400 }, false)
    install_config({ "1", "2" })

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "healthy")

    local out = casedesk()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_nil(out:find("SLA", 1, true))
  end)

  it("shows a yellow SLA badge when under threshold but not yet overdue", function()
    local dir = make_case_dir("yellow", 0)
    install_resolve({ dir = dir, short = "CASE-6" })
    install_meta(nil)
    install_sla({ digit = "1" }, { remaining = 300, budget = 14400 }, true)
    install_config({ "1", "2" })

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "yellow")

    local out = casedesk()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("%#DiagnosticWarn#SLA 300s", 1, true) ~= nil, out)
    assert.is_nil(out:find("DiagnosticError", 1, true))
    assert.is_nil(out:find("SLA!", 1, true))
  end)

  it("shows a red SLA! badge once the clock is overdue", function()
    local dir = make_case_dir("red", 0)
    install_resolve({ dir = dir, short = "CASE-7" })
    install_meta(nil)
    install_sla({ digit = "1" }, { remaining = -120, budget = 14400 }, true)
    install_config({ "1", "2" })

    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(buf)
    set_buf_name(buf, "red")

    local out = casedesk()

    uninstall()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    assert.is_true(out:find("%#DiagnosticError#SLA! -120s", 1, true) ~= nil, out)
    assert.is_nil(out:find("DiagnosticWarn", 1, true))
  end)
end)
