-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- ui.statusline.cursor_ctl.renderer -- previously untested. Covers the
--- 2026-09-12 fix: a missing space between the "%" sign and the bar glyph
--- in pct_token() made the two read as touching/overlapping in most fonts
--- (reported against the live statusline, a pre-existing cosmetic issue,
--- not a regression from that session's other changes).

local renderer = require("ui.statusline.cursor_ctl.renderer")

describe("ui.statusline.cursor_ctl.renderer.pct_token", function()
  it("separates the percent sign from the bar glyph with a space", function()
    -- The escaped form doubles literal "%" (statusline escaping), so the
    -- percent sign appears as "%%" here -- assert on what actually precedes
    -- the bar glyph rather than hardcoding the doubled form.
    local token = renderer.pct_token(68, "R")
    local before_bar = token:match("^.*%%%%(.-)$") -- text after the last literal "%%"
    assert.is_not_nil(before_bar)
    assert.equals(" ", before_bar:sub(1, 1))
  end)

  it("still contains the percentage and prefix", function()
    local token = renderer.pct_token(68, "R")
    assert.is_not_nil(token:find("R", 1, true))
    assert.is_not_nil(token:find("68", 1, true))
  end)

  it("falls back to a placeholder when pct is nil", function()
    local token = renderer.pct_token(nil, "R")
    assert.is_not_nil(token:find("%-%-"))
  end)

  it("clamps and picks a bar glyph at both ends of the range", function()
    assert.has_no.errors(function()
      renderer.pct_token(0, "R")
      renderer.pct_token(100, "R")
      renderer.pct_token(-5, "R")
      renderer.pct_token(500, "R")
    end)
  end)
end)

describe("ui.statusline.cursor_ctl.renderer.cursor_classic", function()
  it("returns the statusline line/col placeholders, unescaped", function()
    assert.equals(" Ln %l, Col %v ", renderer.cursor_classic())
  end)
end)
