-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `<Tab>` path completion in a directory with a great many entries.
---
--- `getcompletion(frag, "file")` pays a file-system `stat` per match -- about a tenth
--- of a millisecond each -- so a directory of five thousand files (a Downloads
--- folder) froze the editor for half a second at every <Tab>, to fill a popup nobody
--- can read. With more than `MAX_PATH_MATCHES` matches the candidates are now built
--- from one directory listing, without a `stat`, sorted and cut to that many.
--- Everything else -- few matches, a pattern, another completion type, a directory
--- that cannot be listed -- is `getcompletion()`'s as before; it is stubbed here, which
--- is what tells the two paths apart.

local kit = require("ui.kit")
local api = vim.api
local uv = vim.uv or vim.loop

local MAX = 300

---@param path string
local function touch(path)
  local f = assert(io.open(path, "w"))
  f:write("")
  f:close()
end

local function close_floats()
  for _ = 1, 10 do
    local closed = false
    for _, w in ipairs(api.nvim_list_wins()) do
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

describe("path completion in a big directory", function()
  local dir ---@type string
  local real_getcompletion, real_complete, real_stat
  local getcompletion_calls, stat_calls, shown, shown_col

  --- A directory (forward slashes, long names: getcompletion() would choke on the
  --- 8.3 form of a Windows temp path) with `files` `item_NNN` files and `dirs`
  --- `sub_NNN` subdirectories, a dot file and one more file.
  ---@param files integer
  ---@param dirs integer
  ---@return string
  local function make_dir(files, dirs)
    local d = vim.fn.tempname()
    vim.fn.mkdir(d, "p")
    d = (uv.fs_realpath(d) or d):gsub("\\", "/")
    for i = 0, files - 1 do
      touch(("%s/item_%03d"):format(d, i))
    end
    for i = 0, dirs - 1 do
      vim.fn.mkdir(("%s/sub_%03d"):format(d, i), "p")
    end
    touch(d .. "/.hidden")
    touch(d .. "/other.txt")
    return d
  end

  --- <Tab> in a prompt of `completion` type, with `line` typed and the cursor at its end.
  ---@param line string
  ---@param completion? string
  local function press_tab(line, completion)
    getcompletion_calls, stat_calls, shown, shown_col = 0, 0, nil, nil
    local surf = kit.input({ completion = completion or "file" })
    api.nvim_buf_set_lines(surf.bufnr, 0, -1, false, { line })
    api.nvim_win_set_cursor(surf.winid, { 1, #line })
    vim.fn.maparg("<Tab>", "i", false, true).callback()
    surf:close()
  end

  before_each(function()
    getcompletion_calls, stat_calls = 0, 0
    real_getcompletion, real_complete, real_stat = vim.fn.getcompletion, vim.fn.complete, uv.fs_stat
    vim.fn.getcompletion = function()
      getcompletion_calls = getcompletion_calls + 1
      return { "from-getcompletion" }
    end
    vim.fn.complete = function(col, items)
      shown_col, shown = col, items
    end
    uv.fs_stat = function(...)
      stat_calls = stat_calls + 1
      return real_stat(...)
    end
  end)

  after_each(function()
    vim.fn.getcompletion, vim.fn.complete, uv.fs_stat = real_getcompletion, real_complete, real_stat
    close_floats()
    if dir then
      vim.fn.delete(dir, "rf")
      dir = nil
    end
  end)

  it("lists a directory of many files once, without a stat per match", function()
    dir = make_dir(MAX + 100, 0)
    press_tab(dir .. "/item")
    assert.is_not_nil(shown, "a popup opens")
    assert.equals(MAX, #shown, "cut to the most a menu holds")
    assert.equals(0, getcompletion_calls, "getcompletion() is not asked")
    assert.equals(0, stat_calls, "and nothing is stat'ed")
    assert.equals(dir .. "/item_000", shown[1], "sorted, from the start")
    assert.equals(dir .. "/item_" .. ("%03d"):format(MAX - 1), shown[MAX])
    assert.equals(1, shown_col, "complete() starts where the fragment began")
  end)

  it("lists every file of the directory for an empty fragment, dot files left out", function()
    dir = make_dir(MAX + 50, 0)
    local saved = vim.fn.getcwd()
    vim.cmd("cd " .. vim.fn.fnameescape(dir))
    local ok, err = pcall(press_tab, "")
    vim.cmd("cd " .. vim.fn.fnameescape(saved))
    assert(ok, err)
    assert.equals(MAX, #shown)
    assert.equals(0, getcompletion_calls)
    for _, name in ipairs(shown) do
      assert.is_nil(name:match("^%."), "no dot file: " .. name)
    end
  end)

  it("marks a directory with a slash and keeps only directories for completion = dir", function()
    dir = make_dir(20, MAX + 20)
    press_tab(dir .. "/", "dir")
    assert.equals(MAX, #shown)
    assert.equals(0, getcompletion_calls)
    assert.equals(0, stat_calls)
    for _, name in ipairs(shown) do
      assert.is_truthy(name:match("^" .. vim.pesc(dir) .. "/sub_%d+/$"), "a directory: " .. name)
    end

    press_tab(dir .. "/", "file")
    assert.equals(MAX, #shown)
    local dirs = 0
    for _, name in ipairs(shown) do
      if name:sub(-1) == "/" then
        dirs = dirs + 1
      end
    end
    assert.is_true(dirs > 0, "a directory is among the files, with its slash")
  end)

  it("sorts the way getcompletion() does", function()
    dir = make_dir(MAX + 10, 0)
    touch(dir .. "/Item_upper")
    touch(dir .. "/item_ZZ")
    press_tab(dir .. "/item")
    local keys = {}
    for i, name in ipairs(shown) do
      keys[i] = vim.o.fileignorecase and name:lower() or name
    end
    local sorted = vim.deepcopy(keys)
    table.sort(sorted)
    assert.same(sorted, keys)
  end)

  it("leaves a fragment with few matches to getcompletion()", function()
    dir = make_dir(MAX + 100, 0)
    press_tab(dir .. "/item_00")
    assert.equals(1, getcompletion_calls)
    assert.same({ "from-getcompletion" }, shown)
  end)

  it("leaves a directory with few directories to getcompletion() for completion = dir", function()
    dir = make_dir(MAX + 100, 3)
    press_tab(dir .. "/", "dir")
    assert.equals(1, getcompletion_calls, "three directories among all those files")
  end)

  it("leaves a pattern, another type and a directory it cannot list to getcompletion()", function()
    dir = make_dir(MAX + 100, 0)
    press_tab(dir .. "/item*")
    assert.equals(1, getcompletion_calls, "a pattern")
    press_tab(dir .. "/item_{0,1}")
    assert.equals(1, getcompletion_calls, "a brace pattern")
    press_tab(dir .. "/item", "buffer")
    assert.equals(1, getcompletion_calls, "a completion type that is no path")
    press_tab(dir .. "/no/such/dir/item")
    assert.equals(1, getcompletion_calls, "a directory that does not exist")
  end)

  it("lists a dot file only when asked for it by name", function()
    dir = make_dir(MAX + 100, 0)
    press_tab(dir .. "/.")
    assert.equals(1, getcompletion_calls, "one dot file is few matches")
  end)
end)
