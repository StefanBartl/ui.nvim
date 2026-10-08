-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `input.conceal_line`: the mask over a secret's characters, in linear time.
---
--- It used to walk the line with `byteidx(line, i)` and `byteidx(line, i + 1)` for
--- every character, and each call rescans the line from its start: quadratic. A
--- 20 000 character token took a second to mask, a prompt did it on every edit and a
--- `kit.sheet` for every secret row on every repaint. The marks it sets are the same
--- ones: one per character, a base character and its combining marks counting as one.

local kit = require("ui.kit")
local input = require("ui.kit.input")
local api = vim.api
local fn = vim.fn

--- What the old walk produced, as `start-end` byte ranges: the reference.
---@param line string
---@return string
local function reference(line)
  local out = {}
  for i = 0, fn.strchars(line) - 1 do
    local s, e = fn.byteidx(line, i), fn.byteidx(line, i + 1)
    if s >= 0 and e >= s then
      out[#out + 1] = s .. "-" .. e
    end
  end
  return table.concat(out, ",")
end

--- Mask `line` in a scratch buffer; the marks it set as `start-end` ranges, and whether
--- every one carries `mask`.
---@param line string
---@param mask? string
---@return string ranges
---@return boolean all_masked
local function masked(line, mask)
  mask = mask or "*"
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  local ns = api.nvim_create_namespace("ui_kit_conceal_spec")
  input.conceal_line(buf, ns, 0, mask)
  local marks = api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  table.sort(marks, function(a, b)
    return a[3] < b[3]
  end)
  local out, all = {}, true
  for _, m in ipairs(marks) do
    out[#out + 1] = m[3] .. "-" .. m[4].end_col
    all = all and m[4].conceal == mask
  end
  api.nvim_buf_delete(buf, { force = true })
  return table.concat(out, ","), all
end

describe("input.conceal_line", function()
  it("sets one mark per character, over every byte", function()
    local ranges, all = masked("abc")
    assert.equals("0-1,1-2,2-3", ranges)
    assert.is_true(all, "each one carries the mask")
    assert.equals("0-2,2-4", (masked("éé")), "two-byte characters")
    assert.equals("0-1,1-3,3-6,6-10,10-11", (masked("aé漢😀z")), "one to four bytes")
    assert.equals("", (masked("")), "an empty line has nothing to hide")
    assert.equals("0-2", (masked("é", "•")), "a custom mask")
    assert.is_true(select(2, masked("é", "•")))
  end)

  it("keeps a base character and its combining marks under one mark", function()
    assert.equals("0-3,3-4", (masked("e\204\129x")), "e + U+0301, then x")
    assert.equals("0-5,5-6", (masked("x\204\129\204\130y")), "two marks on one base")
    assert.equals(
      "0-6,6-7",
      (masked("\226\157\164\239\184\143a")),
      "a heart and its variation selector"
    )
  end)

  it("sets the marks the byteidx() walk set, for any valid text", function()
    local samples = {
      "plain ascii",
      "Grüße aus Wien: 漢字 😀 👍🏽 🇩🇪",
      "👨\226\128\141👩\226\128\141👧 family",
      "ke\204\129y\204\130 \227\130\153",
      "  leading and trailing  ",
    }
    for _, s in ipairs(samples) do
      assert.equals(reference(s), (masked(s)), ("%q"):format(s))
    end
    -- And a deterministic jumble of all of them.
    local pieces = {
      "a",
      "é",
      "e\204\129",
      "漢",
      "😀",
      "\226\157\164\239\184\143",
      "👍\240\159\143\189",
      "🇩🇪",
      "x\204\129\204\130",
      " ",
      "ß",
    }
    math.randomseed(20261007)
    for _ = 1, 300 do
      local parts = {}
      for i = 1, math.random(0, 12) do
        parts[i] = pieces[math.random(#pieces)]
      end
      local s = table.concat(parts)
      assert.equals(reference(s), (masked(s)), ("%q"):format(s))
    end
  end)

  it("hides every byte of text that is not valid UTF-8 too", function()
    for _, s in ipairs({ "a\255b", "\226\130x", "\192\128", "\255\204\129" }) do
      local ranges = masked(s)
      local covered = 0
      for from, to in ranges:gmatch("(%d+)-(%d+)") do
        assert.equals(
          covered,
          tonumber(from),
          "no gap before " .. from .. " in " .. ("%q"):format(s)
        )
        covered = tonumber(to)
      end
      assert.equals(#s, covered, "every byte of " .. ("%q"):format(s) .. " is under a mark")
    end
  end)

  it("takes time in proportion to the line, not its square", function()
    -- The old walk needed many seconds for this (20 000 characters took it about a
    -- second, and the cost grows with the square); one pass needs well under one.
    local line = string.rep("pässwörd漢", 3333)
    local buf = api.nvim_create_buf(false, true)
    api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    local ns = api.nvim_create_namespace("ui_kit_conceal_spec_perf")
    local t0 = vim.uv.hrtime()
    input.conceal_line(buf, ns, 0, "*")
    local ms = (vim.uv.hrtime() - t0) / 1e6
    local count = #api.nvim_buf_get_extmarks(buf, ns, 0, -1, {})
    api.nvim_buf_delete(buf, { force = true })
    assert.equals(29997, count, "one mark per character")
    assert.is_true(ms < 1500, ("masking 30 000 characters took %.0f ms"):format(ms))
  end)
end)

--- A NUL byte in text that goes through `vim.fn`.
---
--- A NUL in a Lua string reaches `vim.fn` as a Blob, and `split()` or `strdisplaywidth()`
--- raise E976 on it. The mask is re-applied from a `TextChanged` handler that clears its
--- namespace first: a raise there left every character of the secret unmasked, on screen.
--- A NUL gets into a prompt by a paste or `<C-v>000`, or through `default`; a title is
--- measured when the prompt opens. (`kit.sheet` masks its secret rows with the same
--- `conceal_line`.)
describe("a NUL byte in a secret or a title", function()
  local nul = string.char(0)

  after_each(function()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end)

  it("is masked like any other character instead of raising E976", function()
    local ok, ranges, all = pcall(masked, "abc" .. nul .. "def")
    assert.is_true(ok, "conceal_line does not raise: " .. tostring(ranges))
    assert.equals("0-1,1-2,2-3,3-4,4-5,5-6,6-7", ranges, "one mark per character, the NUL included")
    assert.is_true(all, "each one carries the mask")
    assert.equals(
      "0-3,3-4",
      (masked("e\204\129" .. nul)),
      "a base with its combining mark, then the NUL"
    )
  end)

  it("keeps the whole secret masked while the line holds one", function()
    local surf = kit.input({ secret = true, relative = "editor" })
    local ns = api.nvim_create_namespace("lib_kit_input_secret_" .. surf.bufnr)
    local function marks()
      return #api.nvim_buf_get_extmarks(surf.bufnr, ns, 0, -1, {})
    end
    api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { "abcdef" })
    api.nvim_exec_autocmds("TextChanged", { buffer = surf.bufnr })
    assert.equals(6, marks(), "six characters, six marks")

    api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { "abc" .. nul .. "def" })
    api.nvim_exec_autocmds("TextChanged", { buffer = surf.bufnr })
    assert.equals(7, marks(), "the NUL is masked as well, and the rest still is")
    surf:close()
  end)

  it("opens a secret prompt whose default holds one", function()
    local surf
    local ok, err = pcall(function()
      surf = kit.input({ secret = true, default = "a" .. nul .. "b", relative = "editor" })
    end)
    assert.is_true(ok, "the prompt opens instead of raising: " .. tostring(err))
    local ns = api.nvim_create_namespace("lib_kit_input_secret_" .. surf.bufnr)
    assert.equals(3, #api.nvim_buf_get_extmarks(surf.bufnr, ns, 0, -1, {}), "all of it masked")
    surf:close()
  end)

  it("opens a prompt whose title holds one", function()
    local surf
    local ok, err = pcall(function()
      surf = kit.input({ title = "case" .. nul .. "title", relative = "editor" })
    end)
    assert.is_true(ok, "the prompt opens instead of raising: " .. tostring(err))
    assert.is_not_nil(surf, "and there is a prompt")
    surf:close()
  end)
end)

--- `opts.mask` is text for `conceal`, and anything else is the default.
---
--- A number, `true` or a table (a value handed on from a config) went to
--- `nvim_buf_set_extmark` as it was: it raised "Invalid 'conceal': Expected Lua string" -- out of
--- `open()` itself for a prompt with a default, with the window already open and no key mapped, and
--- out of the `TextChanged` handler for one without, after `apply_mask` had cleared the marks. The
--- password stood on screen, with an error for every key. `kit.sheet` already took a string only.
describe("a mask that is not a string", function()
  after_each(function()
    for _, w in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(w) and api.nvim_win_get_config(w).relative ~= "" then
        pcall(api.nvim_win_close, w, true)
      end
    end
  end)

  --- The marks on the prompt's line: how many, and the text each conceals with.
  ---@param surf Ui.Kit.Surface
  ---@return integer count
  ---@return string[] conceals
  local function secret_marks(surf)
    local ns = api.nvim_create_namespace("lib_kit_input_secret_" .. surf.bufnr)
    local conceals = {}
    for _, m in ipairs(api.nvim_buf_get_extmarks(surf.bufnr, ns, 0, -1, { details = true })) do
      conceals[#conceals + 1] = m[4].conceal
    end
    return #conceals, conceals
  end

  for label, bad in pairs({ number = 5, boolean = true, table = {} }) do
    it(
      ("masks with the default when it is a %s, from the start and while typing"):format(label),
      function()
        local surf
        local ok, err = pcall(function()
          surf = kit.input({ secret = true, mask = bad, default = "hunter2", relative = "editor" })
        end)
        assert.is_true(ok, "the prompt opens instead of raising: " .. tostring(err))
        if not surf then
          return
        end
        local count, conceals = secret_marks(surf)
        assert.equals(7, count, "all of the default is masked")
        assert.same(vim.fn["repeat"]({ "*" }, 7), conceals, "with the default mask")

        api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { "hunter22" })
        api.nvim_exec_autocmds("TextChanged", { buffer = surf.bufnr })
        count, conceals = secret_marks(surf)
        assert.equals(8, count, "and what is typed on top of it")
        assert.same(vim.fn["repeat"]({ "*" }, 8), conceals)
        surf:close()
      end
    )
  end

  it("masks with the default while typing into an empty prompt", function()
    local surf = kit.input({ secret = true, mask = 5, relative = "editor" })
    api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { "hunter2" })
    api.nvim_exec_autocmds("TextChanged", { buffer = surf.bufnr })
    local count, conceals = secret_marks(surf)
    assert.equals(7, count, "the marks are there, not cleared and left unset")
    assert.same(vim.fn["repeat"]({ "*" }, 7), conceals)
    surf:close()
  end)

  it("still masks with a string the caller chose, an empty one included", function()
    local surf = kit.input({ secret = true, mask = "•", default = "abc", relative = "editor" })
    local _, conceals = secret_marks(surf)
    assert.same({ "•", "•", "•" }, conceals)
    surf:close()

    surf = kit.input({ secret = true, mask = "", default = "abc", relative = "editor" })
    local count
    count, conceals = secret_marks(surf)
    assert.equals(3, count)
    assert.same({ "", "", "" }, conceals, "an empty string is a string: the characters are hidden")
    surf:close()
  end)
end)
