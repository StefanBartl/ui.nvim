-- See TESTS/config_spec.lua for what these three suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `:checkhealth ui`, run WITHOUT NvChad — which is the case that matters.
---
--- Before step 4 of the roadmap, this report's whole job was to say "NvChad
--- is a hard dependency and it is missing" instead of letting a user
--- discover it as a stack trace. As of step 4 that claim is false: this
--- plugin's own `ui.statusline.render` renders without NvChad, so the
--- report says so as information, not as the fatal error it used to be —
--- and the sections after "Dependencies" now run even with NvChad absent,
--- because nothing below depends on it resolving any more.

local health_mod = require("ui.health")

--- Capture what `M.check()` reports, replacing `vim.health` for the call.
---@return { level: string, msg: string }[]
local function capture()
  local calls = {}
  local saved = vim.health
  --- `vim.health.error`/`warn` take advice as a second argument, and that is
  --- where the sentences a reader acts on actually live -- so the capture
  --- folds it into the recorded text rather than dropping it.
  ---@param level string
  ---@return fun(msg: string, advice: string[]|nil): nil
  local function rec(level)
    return function(msg, advice)
      local text = tostring(msg)
      if type(advice) == "table" then
        text = text .. " | " .. table.concat(advice, " | ")
      end
      calls[#calls + 1] = { level = level, msg = text }
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
  pcall(health_mod.check)
  vim.health = saved
  return calls
end

--- Whether any captured line of `level` contains `needle`.
---@param calls { level: string, msg: string }[]
---@param level string
---@param needle string
---@return boolean
local function has(calls, level, needle)
  for _, c in ipairs(calls) do
    if c.level == level and c.msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe("ui.health", function()
  it("runs without throwing", function()
    assert.has_no.errors(function()
      capture()
    end)
  end)

  it("finds lib.nvim, which the test harness puts on the rtp", function()
    assert.is_true(has(capture(), "ok", "lib.nvim is available"))
  end)

  it("reports a missing NvChad as information, not an error", function()
    -- Step 4: this plugin's own code no longer needs nvconfig/nvchad.stl.utils
    -- at all -- reporting their absence as a fatal error would now be a lie.
    local calls = capture()
    assert.is_true(has(calls, "info", "NvChad is not present"))
    assert.is_false(has(calls, "error", "nvconfig"))
    assert.is_false(has(calls, "error", "nvchad.stl.utils"))
  end)

  it("no longer calls NvChad a hard dependency", function()
    assert.is_false(has(capture(), "error", "HARD dependency"))
  end)

  it("runs every section even with NvChad absent", function()
    -- Nothing below "Dependencies" needs NvChad any more, so a missing
    -- NvChad must not cut the report short the way it used to.
    local calls = capture()
    local starts = {}
    for _, c in ipairs(calls) do
      if c.level == "start" then
        starts[#starts + 1] = c.msg
      end
    end
    assert.same({
      "Dependencies",
      "Configuration",
      "Statusline render entrypoint",
      "Tabline render entrypoint",
      "Modules",
      "Statusline segments",
      "Winbar",
      "Optional integrations",
    }, starts)
  end)

  -- The section exists because a soft dependency that rots away upstream
  -- otherwise disables a feature in total silence -- which is exactly what
  -- `nvim-treesitter.ts_utils` did to the Tree-sitter breadcrumb fallback.
  it("reports the optional integrations it probes", function()
    local calls = capture()
    local seen = false
    for _, c in ipairs(calls) do
      if c.msg and c.msg:find("optional integrations", 1, true) then
        seen = true
      end
    end
    assert.is_true(seen)
  end)

  it("reports its own render entrypoint as resolving and rendering", function()
    local calls = capture()
    assert.is_true(has(calls, "ok", "ui.statusline.render resolves"))
    assert.is_true(has(calls, "ok", "renders the 'default' theme's fallback modules"))
  end)

  it("reports its own tabline entrypoint as resolving and rendering", function()
    local calls = capture()
    assert.is_true(has(calls, "ok", "ui.tabline.render resolves"))
    assert.is_true(has(calls, "ok", "renders the shipped tabline config"))
  end)

  it("does not reset the actually active variant back to the boot default", function()
    -- Regression: check_config() used to call ui.config.setup() with no
    -- variant to verify assembly, and that call's own bookkeeping silently
    -- overwrote whichever variant was really active (found live: running
    -- :checkhealth ui after :UI variant personal made :UI status report
    -- "default" again).
    local cfg = require("ui.config")
    cfg.setup({ variant = "minimal" })
    assert.equals("minimal", cfg.get_variant())

    capture()

    assert.equals("minimal", cfg.get_variant())
  end)
end)
