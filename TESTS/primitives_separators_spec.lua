-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Regression coverage for 2026-09-12's separator-glyph bug: `default` and
--- `round` (and, it turned out, `arrow`) were empty strings in
--- ui.statusline.utils.primitives.separators since this table's very first
--- commit in this repo -- confirmed via `git log -p`, so every statusline
--- variant using anything but the "block" style rendered with no separator
--- caps at all (reported live: segments looked "square" instead of the
--- expected rounded-pill look, and a badge with no cap glyph read as a
--- stray solid-color bar).

describe("ui.statusline.utils.primitives.separators", function()
  local primitives = require("ui.statusline.utils.primitives")

  it("every named style has a non-empty left and right glyph", function()
    for name, pair in pairs(primitives.separators) do
      assert.is_true(#pair.left > 0, ("%q's left glyph is empty"):format(name))
      assert.is_true(#pair.right > 0, ("%q's right glyph is empty"):format(name))
    end
  end)

  it("default and round are both real Powerline separators, not empty strings", function()
    -- The specific regression: these two used to be `""`.
    assert.is_true(#primitives.separators.default.left > 1)
    assert.is_true(#primitives.separators.default.right > 1)
    assert.is_true(#primitives.separators.round.left > 1)
    assert.is_true(#primitives.separators.round.right > 1)
  end)
end)

describe("ui.statusline.utils.get_separators", function()
  local get_separators = require("ui.statusline.utils.get_separators")

  it("resolves every named style to non-empty glyphs", function()
    for _, name in ipairs({ "default", "round", "block", "arrow" }) do
      local sep = get_separators(name)
      assert.is_true(#sep.left > 0, ("%q resolved empty"):format(name))
      assert.is_true(#sep.right > 0, ("%q resolved empty"):format(name))
    end
  end)

  it("nil (no argument) resolves to the 'default' style, not empty", function()
    local sep = get_separators(nil)
    assert.is_true(#sep.left > 0)
    assert.is_true(#sep.right > 0)
  end)
end)

describe("ui.statusline.modules.filetree_cwd_mode", function()
  local filetree_cwd_mode = require("ui.statusline.modules.filetree_cwd_mode")

  ---@param mode string
  ---@return nil
  local function fake_filetree(mode)
    package.loaded["filetree"] = {
      feature = function(name)
        if name ~= "cwd_mode" then
          return nil
        end
        return {
          badge = function()
            return { text = mode:upper(), mode = mode, hl = "Comment" }
          end,
        }
      end,
    }
  end

  after_each(function()
    package.loaded["filetree"] = nil
  end)

  it("renders the inert 'follow' mode without throwing, with a real accent", function()
    fake_filetree("follow")
    local ok, out = pcall(filetree_cwd_mode, { badge_style = true })
    assert.is_true(ok, tostring(out))
    assert.is_string(out)
    assert.is_true(#out > 0)
    assert.is_not_nil(out:find("FOLLOW", 1, true))
  end)

  it(
    "threads separator_style through to get_separators instead of always using 'default'",
    function()
      fake_filetree("project")
      local out_round = filetree_cwd_mode({ badge_style = true, separator_style = "round" })
      local out_arrow = filetree_cwd_mode({ badge_style = true, separator_style = "arrow" })
      -- Different styles must produce different separator glyphs somewhere in
      -- the rendered string -- if the parameter were being ignored, both
      -- would be byte-identical.
      assert.is_not.equals(out_round, out_arrow)
    end
  )
end)
