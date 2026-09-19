--- `ui.statusline.modules.matchup_offscreen` -- reads vim-matchup's own
--- `w:matchup_statusline` (populated by `method = "status_manual"`) back as
--- one segment, instead of vim-matchup's `method = "status"` overwriting
--- `&l:statusline` wholesale.

local matchup_offscreen = require("ui.statusline.modules.matchup_offscreen")

describe("ui.statusline.modules.matchup_offscreen", function()
  local winid

  before_each(function()
    winid = vim.api.nvim_get_current_win()
    vim.g.statusline_winid = winid
    pcall(function()
      vim.w[winid].matchup_statusline = nil
    end)
  end)

  after_each(function()
    vim.g.statusline_winid = nil
    pcall(function()
      vim.w[winid].matchup_statusline = nil
    end)
  end)

  it("renders empty when w:matchup_statusline is unset (nothing offscreen)", function()
    assert.equals("", matchup_offscreen())
  end)

  it("renders the stored string, space-prefixed, once vim-matchup sets it", function()
    vim.w[winid].matchup_statusline = "%#Normal#foo(%#MatchParen#bar%#Normal#)"

    local out = matchup_offscreen()

    assert.equals(" %#Normal#foo(%#MatchParen#bar%#Normal#)", out)
  end)

  it("renders empty again once vim-matchup unlets the variable (matchparen.clear())", function()
    vim.w[winid].matchup_statusline = "%#Normal#foo"
    assert.is_true(matchup_offscreen() ~= "")

    vim.w[winid].matchup_statusline = nil

    assert.equals("", matchup_offscreen())
  end)

  it("falls back to the current window when statusline_winid is unset", function()
    vim.g.statusline_winid = nil
    vim.w[winid].matchup_statusline = "%#Normal#baz"

    assert.equals(" %#Normal#baz", matchup_offscreen())
  end)
end)
