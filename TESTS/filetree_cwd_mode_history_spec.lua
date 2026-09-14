-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.statusline.modules.filetree_cwd_mode`'s `opts.history` -- the last 3
--- (mode, root) badges as small dots (current filled, earlier hollow), from
--- IDEEN-statusline.md's "Filetree-cwd-mode-Badge: Historie statt nur
--- aktueller Modus". filetree.nvim is not on this suite's runtimepath (a
--- soft dependency, same contract as casedesk/github_stats_badge/
--- runtime_analysis_ampel/recommender_badge), so every test injects a fake
--- `filetree` module -- see TESTS/primitives_separators_spec.lua for this
--- module's own pre-existing (non-history) coverage.
---
--- The module under test is re-required fresh in every test (`package.
--- loaded[...] = nil` then `require(...)` again): `history` and the
--- "autocmd already registered" flag are both module-level state, and
--- reusing one test's history in the next would defeat the point of
--- testing accumulation/capping/dedup in isolation.

---@param mode string
---@param root string|nil
local function set_filetree(mode, root)
  package.loaded["filetree"] = {
    feature = function(name)
      if name ~= "cwd_mode" then
        return nil
      end
      return {
        badge = function()
          return { text = mode:upper(), mode = mode, root = root, hl = "Comment" }
        end,
      }
    end,
  }
end

local function fire_mode_changed()
  vim.api.nvim_exec_autocmds("User", { pattern = "FiletreeCwdModeChanged" })
end

---@return fun(opts: table): string
local function fresh_module()
  package.loaded["ui.statusline.modules.filetree_cwd_mode"] = nil
  return require("ui.statusline.modules.filetree_cwd_mode")
end

---@param out string
---@return integer current, integer past
local function count_dots(out)
  local current = select(2, out:gsub("\xE2\x97\x8F", ""))
  local past = select(2, out:gsub("\xE2\x97\x8B", ""))
  return current, past
end

describe("ui.statusline.modules.filetree_cwd_mode history dots", function()
  after_each(function()
    package.loaded["filetree"] = nil
  end)

  it("renders no dots when opts.history is not set", function()
    local filetree_cwd_mode = fresh_module()
    set_filetree("lock", "/tmp/case_a")

    local out = filetree_cwd_mode({ badge_style = true })

    local current, past = count_dots(out)
    assert.equals(0, current)
    assert.equals(0, past)
  end)

  it("seeds one filled dot for the current mode on first render", function()
    local filetree_cwd_mode = fresh_module()
    set_filetree("lock", "/tmp/case_a")

    local out = filetree_cwd_mode({ badge_style = true, history = true })

    local current, past = count_dots(out)
    assert.equals(1, current)
    assert.equals(0, past)
  end)

  it("adds a new dot when FiletreeCwdModeChanged fires with a different mode", function()
    local filetree_cwd_mode = fresh_module()
    set_filetree("lock", "/tmp/case_a")
    filetree_cwd_mode({ history = true }) -- seeds entry 1

    set_filetree("project", "/tmp/proj_b")
    fire_mode_changed()

    local out = filetree_cwd_mode({ badge_style = true, history = true })
    local current, past = count_dots(out)
    assert.equals(1, current)
    assert.equals(1, past)
  end)

  it(
    "treats the same mode with a different root as a distinct entry (two-case round trip)",
    function()
      local filetree_cwd_mode = fresh_module()
      set_filetree("lock", "/tmp/case_a")
      filetree_cwd_mode({ history = true }) -- seeds entry 1

      set_filetree("lock", "/tmp/case_b")
      fire_mode_changed()

      local out = filetree_cwd_mode({ badge_style = true, history = true })
      local current, past = count_dots(out)
      assert.equals(1, current)
      assert.equals(1, past)
    end
  )

  it("does not duplicate an entry when the same (mode, root) fires again", function()
    local filetree_cwd_mode = fresh_module()
    set_filetree("lock", "/tmp/case_a")
    filetree_cwd_mode({ history = true }) -- seeds entry 1

    fire_mode_changed() -- same mode/root, must be a no-op
    fire_mode_changed()

    local out = filetree_cwd_mode({ badge_style = true, history = true })
    local current, past = count_dots(out)
    assert.equals(1, current)
    assert.equals(0, past)
  end)

  it("caps history at 3, dropping the oldest entry", function()
    local filetree_cwd_mode = fresh_module()
    set_filetree("lock", "/tmp/case_a")
    filetree_cwd_mode({ history = true }) -- entry 1

    set_filetree("project", "/tmp/case_b")
    fire_mode_changed() -- entry 2
    set_filetree("nearest", "/tmp/case_c")
    fire_mode_changed() -- entry 3
    set_filetree("manual", "/tmp/case_d")
    fire_mode_changed() -- entry 4, entry 1 should fall off

    local out = filetree_cwd_mode({ badge_style = true, history = true })
    local current, past = count_dots(out)
    assert.equals(1, current)
    assert.equals(2, past)
  end)
end)
