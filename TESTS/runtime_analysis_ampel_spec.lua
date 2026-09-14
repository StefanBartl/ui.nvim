-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.runtime_analysis_ampel` -- a traffic-light glyph
--- for whether any runtime-analysis.nvim-instrumented plugin looks
--- unhealthy today, from IDEEN-statusline.md's "Segmente, die dieses
--- Ökosystem einzigartig machen" bucket. runtime-analysis.nvim is not on
--- this suite's runtimepath (a soft dependency, same contract as
--- casedesk/filetree_cwd_mode/github_stats_badge), so every test injects a
--- fake `runtime-analysis.telemetry` module.

local ampel = require("ui.statusline.modules.runtime_analysis_ampel")

---@param fake table
local function install(fake)
  package.loaded["runtime-analysis.telemetry"] = fake
end

local function uninstall()
  package.loaded["runtime-analysis.telemetry"] = nil
end

describe("ui.statusline.modules.runtime_analysis_ampel", function()
  it("renders empty when runtime-analysis.nvim is not installed", function()
    uninstall()
    assert.equals("", ampel())
  end)

  it("renders empty when nothing has ever wrapped a telemetry instance", function()
    install({
      known_namespaces = function()
        return {}
      end,
    })

    local out = ampel()
    uninstall()

    assert.equals("", out)
  end)

  it("renders green when a live namespace has no errors and nothing slow today", function()
    install({
      known_namespaces = function()
        return { "lib.nvim" }
      end,
      get = function()
        return {
          report = function()
            return { entries = { { errors = 0, mean_ms = 2.5 } } }
          end,
        }
      end,
    })

    local out = ampel()
    uninstall()

    assert.is_true(out:find("\xF0\x9F\x9F\xA2", 1, true) ~= nil, out)
  end)

  it("renders yellow when nothing errored but a function is slow today", function()
    install({
      known_namespaces = function()
        return { "lib.nvim" }
      end,
      get = function()
        return {
          report = function(opts)
            assert.equals("1d", opts.since)
            return { entries = { { errors = 0, mean_ms = 500 } } }
          end,
        }
      end,
    })

    local out = ampel()
    uninstall()

    assert.is_true(out:find("\xF0\x9F\x9F\xA1", 1, true) ~= nil, out)
  end)

  it("renders red when any namespace has an error today, even alongside a slow one", function()
    install({
      known_namespaces = function()
        return { "lib.nvim", "documentation.nvim" }
      end,
      get = function(namespace)
        if namespace == "lib.nvim" then
          return {
            report = function()
              return { entries = { { errors = 0, mean_ms = 500 } } }
            end,
          }
        end
        return {
          report = function()
            return { entries = { { errors = 3, mean_ms = 1 } } }
          end,
        }
      end,
    })

    local out = ampel()
    uninstall()

    assert.is_true(out:find("\xF0\x9F\x94\xB4", 1, true) ~= nil, out)
  end)

  it("reads today's disk-only data for a namespace with no live instance", function()
    local today = os.date("%Y-%m-%d")
    install({
      known_namespaces = function()
        return { "cold.nvim" }
      end,
      get = function()
        return nil
      end,
      load = function(namespace)
        assert.equals("cold.nvim", namespace)
        return {
          days = { [today] = { ["some.fn"] = 3 } },
          functions = { ["some.fn"] = { errors = 1 } },
        }
      end,
    })

    local out = ampel()
    uninstall()

    assert.is_true(out:find("\xF0\x9F\x94\xB4", 1, true) ~= nil, out)
  end)

  it("ignores a disk-only namespace's functions that were not called today", function()
    install({
      known_namespaces = function()
        return { "quiet.nvim" }
      end,
      get = function()
        return nil
      end,
      load = function()
        return {
          days = {},
          -- Errored in the past, but not active in today's bucket -- must
          -- not turn the ampel red on stale history alone.
          functions = { ["some.fn"] = { errors = 99 } },
        }
      end,
    })

    local out = ampel()
    uninstall()

    assert.is_true(out:find("\xF0\x9F\x9F\xA2", 1, true) ~= nil, out)
  end)

  it(
    "renders green (not an error) for a disk-only namespace that never persisted anything",
    function()
      install({
        known_namespaces = function()
          return { "ghost.nvim" }
        end,
        get = function()
          return nil
        end,
        load = function()
          return nil
        end,
      })

      local out = ampel()
      uninstall()

      assert.is_true(out:find("\xF0\x9F\x9F\xA2", 1, true) ~= nil, out)
    end
  )
end)
