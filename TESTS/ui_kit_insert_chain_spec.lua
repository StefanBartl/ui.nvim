-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Which window a closing prompt leaves in Insert mode.
---
--- A prompt that closes calls `:stopinsert` -- unless a callback has just opened
--- the next window to be typed into, whose own `:startinsert` is ignored while the
--- closing one's Insert mode is still on (that window would then stand in Normal
--- mode, the first thing typed a command). The modes themselves are
--- `ui_kit_input_ui_spec.lua`'s, in a UI-attached child; this runner never enters
--- Insert mode, so what is pinned here is the decision: whether `:stopinsert` is
--- called, and who counts as "opened a window to type into".

local kit = require("ui.kit")
local input = require("ui.kit.input")
local api = vim.api

---@param k string
local function keys(k)
  api.nvim_feedkeys(api.nvim_replace_termcodes(k, true, false, true), "x", false)
end

local function close_floats()
  for _ = 1, 10 do
    local closed = false
    for _, w in ipairs(api.nvim_list_wins()) do
      -- Closing one window can close others (a picker is several): look before touching.
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
        closed = true
      end
    end
    if not closed then
      return
    end
  end
end

--- Run `body` and say how often `:stopinsert` was asked for meanwhile.
---@param body fun()
---@return integer
local function count_stopinsert(body)
  local stops = 0
  local real_cmd = vim.cmd
  vim.cmd = setmetatable({}, {
    __call = function(_, c, ...)
      if c == "stopinsert" then
        stops = stops + 1
      end
      return real_cmd(c, ...)
    end,
    __index = real_cmd,
  })
  local ok, err = pcall(body)
  vim.cmd = real_cmd
  assert(ok, err)
  return stops
end

describe("a prompt that closes while its callback opens another window", function()
  after_each(close_floats)

  it("counts every component that is typed into", function()
    local before = input.opened_count()
    kit.input({})
    assert.equals(before + 1, input.opened_count(), "a prompt")
    kit.sheet({ fields = { { name = "a" } }, on_submit = function() end })
    assert.equals(before + 2, input.opened_count(), "a sheet")
    kit.picker({ on_change = function() end, on_submit = function() end })
    assert.equals(before + 3, input.opened_count(), "a picker")
    kit.live_input({ on_change = function() end })
    assert.equals(before + 4, input.opened_count(), "a live_input")
    kit.compare({
      items = { "a", "b" },
      render = function(item, surface)
        surface:set_lines({ item })
      end,
    })
    assert.equals(before + 5, input.opened_count(), "a compare")
    -- Not typed into: a chooser, a confirm dialog.
    require("ui.kit.select").open({ items = { "a" }, on_select = function() end })
    require("ui.kit.confirm").open({ question = "?" })
    assert.equals(before + 5, input.opened_count(), "a chooser and a confirm are not counted")
  end)

  local openers = {
    ["a sheet"] = function()
      kit.sheet({ fields = { { name = "a" } }, on_submit = function() end })
    end,
    ["a picker"] = function()
      kit.picker({ on_change = function() end, on_submit = function() end })
    end,
    ["a live_input"] = function()
      kit.live_input({ on_change = function() end })
    end,
    ["a compare"] = function()
      kit.compare({
        items = { "a", "b" },
        render = function(item, surface)
          surface:set_lines({ item })
        end,
      })
    end,
    ["another prompt"] = function()
      kit.input({})
    end,
  }
  for name, open_next in pairs(openers) do
    it("does not stop Insert mode under " .. name, function()
      local stops = count_stopinsert(function()
        kit.input({ on_submit = open_next })
        keys("<CR>")
      end)
      assert.equals(0, stops)
    end)
  end

  it("stops Insert mode when it opens nothing that is typed into", function()
    local answered
    local stops = count_stopinsert(function()
      kit.input({
        on_submit = function(v)
          answered = v
        end,
      })
      keys("<CR>")
    end)
    assert.equals("", answered)
    assert.equals(1, stops)

    stops = count_stopinsert(function()
      kit.input({
        on_submit = function()
          require("ui.kit.select").open({ items = { "a", "b" }, on_select = function() end })
        end,
      })
      keys("<CR>")
    end)
    assert.equals(1, stops, "a chooser is driven from Normal mode")
  end)

  it("does not stop Insert mode under the sheet a form opens after its last field", function()
    local stops = count_stopinsert(function()
      kit.form({
        fields = { { name = "a" } },
        on_submit = function()
          kit.sheet({ fields = { { name = "b" } }, on_submit = function() end })
        end,
      })
      keys("<CR>")
    end)
    assert.equals(0, stops)
  end)

  describe("a sheet that closes over a float that was there before", function()
    -- The focus goes back to the float, which is modifiable like a prompt's buffer
    -- but is not waiting for anything: it used to be taken for the next prompt of a
    -- chain, and the Insert mode of the sheet was left running in it.
    ---@return integer
    local function sheet_over_float(leave)
      local origin_buf = api.nvim_create_buf(false, true)
      api.nvim_open_win(
        origin_buf,
        true,
        { relative = "editor", row = 2, col = 2, width = 20, height = 3 }
      )
      local origin = api.nvim_get_current_win()
      local surf = kit.sheet({
        fields = { { name = "a" } },
        on_submit = function() end,
        on_cancel = function() end,
      })
      assert.is_not.equals(origin, surf.winid)
      local stops = count_stopinsert(function()
        leave()
      end)
      assert.equals(origin, api.nvim_get_current_win(), "the focus is back in the float")
      return stops
    end

    it("stops Insert mode when it is cancelled", function()
      assert.equals(
        1,
        sheet_over_float(function()
          keys("<Esc>")
        end)
      )
    end)

    it("stops Insert mode when it is submitted", function()
      assert.equals(
        1,
        sheet_over_float(function()
          keys("<CR>")
        end)
      )
    end)
  end)
end)
