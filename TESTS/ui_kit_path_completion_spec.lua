-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `<Tab>` path completion in a directory with a great many entries.
---
--- `getcompletion(frag, "file")` pays a file-system `stat` per match -- about a tenth
--- of a millisecond each -- so a directory of five thousand files (a Downloads
--- folder) froze the editor for half a second at every <Tab>, to fill a popup nobody
--- can read. With more than `MAX_PATH_MATCHES` candidates (entries that start with the
--- fragment, the files among them for completion = "dir") the list is now built from
--- one directory listing, without a `stat` (a link, or a listing that does not say what
--- an entry is, costs one until the menu is full), sorted and cut to that many; for
--- "dir" it is the whole answer, however few directories there are among the files.
--- Everything else -- few candidates, a pattern, another completion type, a directory
--- that cannot be listed -- is `getcompletion()`'s as before; it is stubbed here, which
--- is what tells the two paths apart.
---
--- The list has to be the one `getcompletion()` would make, so a few cases compare it
--- with the real function (taken before the stub): which entries match and in which order
--- they come under 'fileignorecase' and 'wildignorecase', and for non-ASCII names.

local kit = require("ui.kit")
local api = vim.api
local uv = vim.uv or vim.loop

local MAX = 300

--- 'fileignorecase' and 'wildignorecase', in every combination.
local CASE_OPTIONS = { { true, false }, { false, false }, { false, true }, { true, true } }

---@param path string
local function touch(path)
  -- Not `io.open`: on Windows LuaJIT's takes the ANSI code page, which turns a file name
  -- with a non-ASCII character into another name. "S": no fsync, a few hundred files add up.
  assert(vim.fn.writefile({}, path, "S") == 0, "could not create " .. path)
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
  local real_getcompletion, real_complete, real_stat, real_scandir, real_scandir_next
  local getcompletion_calls, stat_calls, shown, shown_col

  --- An empty directory (forward slashes, long names: getcompletion() would choke on
  --- the 8.3 form of a Windows temp path).
  ---@return string
  local function new_dir()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d, "p")
    return (uv.fs_realpath(d) or d):gsub("\\", "/")
  end

  --- A directory with `files` `item_NNN` files and `dirs` `sub_NNN` subdirectories, a
  --- dot file and one more file.
  ---@param files integer
  ---@param dirs integer
  ---@return string
  local function make_dir(files, dirs)
    local d = new_dir()
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

  --- The same listing, but it does not say what an entry is -- what a link, a junction
  --- and a file system without `d_type` do: the code has to `stat` those.
  local function hide_entry_kinds()
    uv.fs_scandir_next = function(handle)
      return (real_scandir_next(handle))
    end
  end

  --- What `getcompletion()` itself lists for `frag`: slashes forward, cut to what a
  --- menu holds.
  ---@param frag string
  ---@return string[]
  local function expected_list(frag)
    local names = vim.tbl_map(function(name)
      return (name:gsub("\\", "/"))
    end, real_getcompletion(frag, "file"))
    return vim.list_slice(names, 1, MAX)
  end

  --- Run `fn` with 'fileignorecase' and 'wildignorecase' set, whatever happens in it.
  ---@param fic boolean
  ---@param wic boolean
  ---@param fn fun()
  local function with_case_options(fic, wic, fn)
    local saved_fic, saved_wic = vim.o.fileignorecase, vim.o.wildignorecase
    vim.o.fileignorecase, vim.o.wildignorecase = fic, wic
    local ok, err = pcall(fn)
    vim.o.fileignorecase, vim.o.wildignorecase = saved_fic, saved_wic
    assert(ok, err)
  end

  --- <Tab> on `frag`, under every combination of the case options, has to give what the
  --- real `getcompletion()` gives: its list cut to what a menu holds when it has more than
  --- that (and then it is not asked), `getcompletion()` itself otherwise. With
  --- `via_getcompletion` it is `getcompletion()` that has to answer however long its list
  --- is -- names the big list cannot order the way it does.
  ---@param frag string
  ---@param via_getcompletion? boolean
  local function check_like_getcompletion(frag, via_getcompletion)
    for _, case in ipairs(CASE_OPTIONS) do
      with_case_options(case[1], case[2], function()
        local label = ("%s with 'fileignorecase' %s, 'wildignorecase' %s"):format(
          vim.inspect(frag:sub(#dir + 2)),
          tostring(case[1]),
          tostring(case[2])
        )
        local full = vim.tbl_map(function(name)
          return (name:gsub("\\", "/"))
        end, real_getcompletion(frag, "file"))
        press_tab(frag)
        if via_getcompletion or #full <= MAX then
          assert.equals(1, getcompletion_calls, label .. ": getcompletion() answers")
        else
          assert.equals(0, getcompletion_calls, label .. ": the big list answers")
          assert.same(vim.list_slice(full, 1, MAX), shown, label)
        end
      end)
    end
  end

  --- Whether the directory lists each of `names` as it was created (a file system that
  --- normalizes Unicode -- HFS+ -- does not, and the spec has nothing to say there).
  ---@param d string
  ---@param names string[]
  ---@return boolean
  local function listed_verbatim(d, names)
    local at = {}
    local handle = real_scandir(d)
    while handle do
      local entry = real_scandir_next(handle)
      if not entry then
        break
      end
      at[entry] = true
    end
    for _, name in ipairs(names) do
      if not at[name] then
        return false
      end
    end
    return true
  end

  before_each(function()
    getcompletion_calls, stat_calls = 0, 0
    real_getcompletion, real_complete, real_stat = vim.fn.getcompletion, vim.fn.complete, uv.fs_stat
    real_scandir, real_scandir_next = uv.fs_scandir, uv.fs_scandir_next
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
    uv.fs_scandir, uv.fs_scandir_next = real_scandir, real_scandir_next
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

  it("stats a link, or an entry of unknown type, only until the menu is full", function()
    dir = make_dir(MAX + 100, 0)
    hide_entry_kinds()
    press_tab(dir .. "/item")
    assert.equals(0, getcompletion_calls, "getcompletion() is not asked")
    assert.is_true(stat_calls <= MAX, stat_calls .. " stats for " .. MAX + 100 .. " matches")
    assert.equals(MAX, #shown)
    assert.equals(dir .. "/item_000", shown[1])
    assert.equals(dir .. "/item_" .. ("%03d"):format(MAX - 1), shown[MAX])
  end)

  it("stats nothing when too few entries match to need the list", function()
    dir = make_dir(MAX - 50, 0)
    hide_entry_kinds()
    press_tab(dir .. "/item")
    assert.equals(1, getcompletion_calls, "getcompletion() has the few")
    assert.equals(0, stat_calls, "nothing was stat'ed on the way")
  end)

  it("tells a directory of unknown type from a file, for its slash and for 'dir'", function()
    dir = make_dir(20, MAX + 20)
    hide_entry_kinds()
    press_tab(dir .. "/", "dir")
    assert.equals(MAX, #shown)
    for _, name in ipairs(shown) do
      assert.is_truthy(name:match("^" .. vim.pesc(dir) .. "/sub_%d+/$"), "a directory: " .. name)
    end

    press_tab(dir .. "/", "file")
    local expected = {}
    for i = 0, 19 do
      expected[#expected + 1] = ("%s/item_%03d"):format(dir, i)
    end
    expected[#expected + 1] = dir .. "/other.txt"
    for i = 0, MAX - 22 do
      expected[#expected + 1] = ("%s/sub_%03d/"):format(dir, i)
    end
    assert.same(expected, shown)
  end)

  --- `stat` as a broken link has it: no answer for the first ten items.
  local function broken_first_ten()
    uv.fs_stat = function(path)
      stat_calls = stat_calls + 1
      if path:match("/item_00%d$") then
        return nil
      end
      return real_stat(path)
    end
  end

  it(
    "leaves out an entry that cannot be stat'ed (a broken link), as getcompletion() does",
    function()
      dir = make_dir(MAX + 20, 0)
      hide_entry_kinds()
      broken_first_ten()
      press_tab(dir .. "/item")
      assert.equals(0, getcompletion_calls, "the list is the answer")
      assert.equals(MAX, #shown, "the broken ones do not fill the menu")
      assert.equals(dir .. "/item_010", shown[1])
      assert.equals(dir .. "/item_309", shown[MAX])
    end
  )

  it("lists what is left when the broken links leave the menu short of full", function()
    dir = make_dir(MAX + 10, 0)
    hide_entry_kinds()
    broken_first_ten()
    press_tab(dir .. "/item")
    assert.equals(0, getcompletion_calls, "every candidate has been looked at: the list is whole")
    assert.equals(MAX, #shown)
    assert.equals(dir .. "/item_010", shown[1])
    assert.equals(dir .. "/item_309", shown[MAX])

    uv.fs_stat = function()
      stat_calls = stat_calls + 1
    end
    press_tab(dir .. "/item")
    assert.equals(0, getcompletion_calls, "nothing to show is an answer too")
    assert.is_nil(shown, "and no popup opens for it")

    press_tab(dir .. "/", "dir")
    assert.equals(0, getcompletion_calls, "no directory among them")
    assert.is_nil(shown)
  end)

  --- A link whose target is gone (a junction on Windows, where a plain symlink needs a
  --- privilege). false where this system lets the spec create none.
  ---@param path string
  ---@return boolean
  local function make_dangling(path)
    local target = path .. ".target"
    vim.fn.mkdir(target, "p")
    local linked = uv.fs_symlink(target, path, { dir = true, junction = true })
    vim.fn.delete(target, "d")
    return linked and real_stat(path) == nil or false
  end

  it("lists no broken link, as getcompletion() lists none, below and above the limit", function()
    dir = make_dir(MAX + 20, 0)
    local made = 0
    for i = 1, 3 do
      if make_dangling(("%s/brk%03d"):format(dir, i)) then
        made = made + 1
      end
    end
    if made == 0 then
      pending("this system does not allow a link to be created here")
      return
    end
    local expected = expected_list(dir .. "/")
    assert.equals(MAX, #expected, "more than a menu holds: the big list runs")
    assert.is_false(vim.tbl_contains(expected, dir .. "/brk001"), "getcompletion() has none")
    press_tab(dir .. "/")
    assert.equals(0, getcompletion_calls)
    assert.same(expected, shown)
  end)

  it("answers completion = dir from the listing when many files hide a few directories", function()
    -- getcompletion() stats every one of those files to find the three directories: 0.7 s
    -- for five thousand. The listing says what a file is.
    dir = make_dir(MAX + 100, 3)
    press_tab(dir .. "/", "dir")
    assert.equals(0, getcompletion_calls, "the listing has them")
    assert.equals(0, stat_calls, "and nothing is stat'ed")
    assert.same({ dir .. "/sub_000/", dir .. "/sub_001/", dir .. "/sub_002/" }, shown)
    assert.same(
      vim.tbl_map(function(name)
        return (name:gsub("\\", "/"))
      end, real_getcompletion(dir .. "/", "dir")),
      shown,
      "the directories getcompletion() lists"
    )
  end)

  it("counts the files among the candidates for completion = dir", function()
    -- The limit is on what getcompletion() would have to look at, and that is every
    -- entry the fragment starts, files included: it stats them all to find the directories.
    -- Candidates for "<dir>/": MAX - 2 items, one directory and other.txt, exactly MAX ...
    dir = make_dir(MAX - 2, 1)
    press_tab(dir .. "/", "dir")
    assert.equals(1, getcompletion_calls, "exactly MAX candidates are getcompletion()'s")

    -- ... and one file more is the first list that is built from the listing.
    dir = make_dir(MAX - 1, 1)
    press_tab(dir .. "/", "dir")
    assert.equals(0, getcompletion_calls)
    assert.same({ dir .. "/sub_000/" }, shown)
  end)

  it("shows nothing, and asks getcompletion() nothing, when the files hold no directory", function()
    dir = make_dir(MAX + 1, 0)
    press_tab(dir .. "/", "dir")
    assert.equals(0, getcompletion_calls, "the listing has the answer")
    assert.is_nil(shown, "an empty list opens no popup")
  end)

  it(
    "stats each entry of unknown type once, and has the whole answer for completion = dir",
    function()
      -- Links to files, in a directory of two directories: the walk has stat'ed every one of
      -- them when it ends, so asking getcompletion() afterwards would pay for all of them again.
      local files = 2 * MAX + 100
      dir = make_dir(files, 2)
      hide_entry_kinds()
      press_tab(dir .. "/", "dir")
      assert.equals(0, getcompletion_calls, "the walk's list is the answer")
      assert.is_true(
        stat_calls <= files + 3,
        stat_calls .. " stats for " .. files + 3 .. " candidates"
      )
      assert.same({ dir .. "/sub_000/", dir .. "/sub_001/" }, shown)
    end
  )

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

  --- Over the limit, with names that tell the cases apart and the characters that sort
  --- between the capitals and the small letters (`[ ] ^ _` and the backtick) from the
  --- letters. The mixed-case names are all among the first `MAX` however they sort.
  ---@return string
  local function make_mixed_dir()
    local d = make_dir(MAX + 10, 0)
    for _, name in ipairs({
      "itemA",
      "itemb",
      "item[x",
      "item]x",
      "item^x",
      "item`x",
      "Item_000x",
      "ITEM_001y",
    }) do
      touch(d .. "/" .. name)
    end
    vim.fn.mkdir(d .. "/Item_000Dir", "p")
    return d
  end

  for _, case in ipairs(CASE_OPTIONS) do
    local fic, wic = case[1], case[2]
    it(
      ("lists what getcompletion() does, in its order: 'fileignorecase' %s, 'wildignorecase' %s"):format(
        tostring(fic),
        tostring(wic)
      ),
      function()
        dir = make_mixed_dir()
        with_case_options(fic, wic, function()
          local expected = expected_list(dir .. "/item")
          assert.equals(MAX, #expected, "more than a menu holds: the big list runs")
          press_tab(dir .. "/item")
          assert.equals(0, getcompletion_calls, "the big list, not getcompletion()")
          assert.same(expected, shown)
        end)
      end
    )
  end

  it("orders non-ASCII names under 'fileignorecase' the way getcompletion() does", function()
    -- `string.upper` folds ASCII only: left to it, an a-umlaut would sort behind a
    -- capital U-umlaut, where Neovim (which upper-cases the whole character) has it ahead.
    -- The bulk is Cyrillic so that it sorts behind the Latin-1 names and they stay in the
    -- first `MAX`.
    dir = new_dir()
    local bulk = "a" .. vim.fn.nr2char(0x400)
    for i = 0, MAX + 9 do
      touch(("%s/%s%03d"):format(dir, bulk, i))
    end
    for _, name in ipairs({
      "ae",
      "aF",
      "a" .. vim.fn.nr2char(0xE4),
      "a" .. vim.fn.nr2char(0xC9),
      "a" .. vim.fn.nr2char(0xCA),
      "a" .. vim.fn.nr2char(0xF6),
      "a" .. vim.fn.nr2char(0xDC),
    }) do
      touch(dir .. "/" .. name)
    end
    with_case_options(true, false, function()
      local expected = expected_list(dir .. "/a")
      assert.equals(MAX, #expected, "more than a menu holds: the big list runs")
      press_tab(dir .. "/a")
      assert.equals(0, getcompletion_calls, "the big list, not getcompletion()")
      assert.same(expected, shown)
    end)
  end)

  it("orders names that fold to one key by spelling, not by the order of the listing", function()
    -- Zebra / zebra can only exist side by side on a file system that tells the cases
    -- apart, so the listing is made up here.
    local names = { "Zebra", "zebra", "ZEBRA" }
    for i = 0, MAX do
      names[#names + 1] = ("zz_%03d"):format(i)
    end
    local function list(order)
      local at = 0
      uv.fs_scandir = function()
        at = 0
        return {}
      end
      uv.fs_scandir_next = function()
        at = at + 1
        local name = names[order(at)]
        return name, name and "file"
      end
      press_tab("fake/")
      return shown
    end
    with_case_options(true, false, function()
      local forward = list(function(i)
        return i
      end)
      local backward = list(function(i)
        return #names + 1 - i
      end)
      assert.same({ "fake/ZEBRA", "fake/Zebra", "fake/zebra" }, vim.list_slice(forward, 1, 3))
      assert.same(forward, backward)
    end)
  end)

  it("leaves a fragment with few matches to getcompletion()", function()
    dir = make_dir(MAX + 100, 0)
    press_tab(dir .. "/item_00")
    assert.equals(1, getcompletion_calls)
    assert.same({ "from-getcompletion" }, shown)
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

  it("lists the same entries getcompletion() does, whatever 'wildignore' says", function()
    -- getcompletion() without `filtered` does not apply 'wildignore', so neither may
    -- the big-directory list: what <Tab> shows must not depend on the directory size.
    local saved = vim.o.wildignore
    dir = make_dir(MAX + 10, 0)
    touch(dir .. "/aaa.o")
    vim.o.wildignore = "*.o,item_00*"
    local ok, err = pcall(function()
      local expected = vim.tbl_map(function(name)
        return (name:gsub("\\", "/"))
      end, real_getcompletion(dir .. "/", "file"))
      assert.is_true(vim.tbl_contains(expected, dir .. "/aaa.o"), "getcompletion() keeps it")
      press_tab(dir .. "/")
      assert.same(vim.list_slice(expected, 1, MAX), shown)
    end)
    vim.o.wildignore = saved
    assert(ok, err)
  end)

  it("matches a name by Neovim's own case folding, not by upper-casing it", function()
    -- toupper() turns U+0131 (dotless i) into "I", which Neovim's folding does not, and
    -- leaves the Kelvin sign (U+212A) alone, which Neovim folds to "k".
    dir = new_dir()
    local dotless, kelvin = vim.fn.nr2char(0x131), vim.fn.nr2char(0x212A)
    local lone = { dir .. "/itemIa", dir .. "/itemia" }
    for i = 0, MAX do
      touch(("%s/item%sx%03d"):format(dir, dotless, i))
      touch(("%s/item%sx%03d"):format(dir, kelvin, i))
    end
    for _, path in ipairs(lone) do
      touch(path)
    end
    for _, frag in ipairs({
      "itemI",
      "itemi",
      "item" .. dotless,
      "itemk",
      "itemK",
      "item" .. kelvin,
    }) do
      check_like_getcompletion(dir .. "/" .. frag)
    end
    -- the cases above must not all end at getcompletion(): the dotless i is no "I"...
    with_case_options(true, true, function()
      assert.is_true(#real_getcompletion(dir .. "/item" .. dotless, "file") > MAX)
    end)
  end)

  it("does not take a combining mark after the fragment for part of the name", function()
    -- "U" is no prefix of "U" + U+0308 (an umlaut written as two characters, as macOS
    -- writes them): getcompletion() lists the four plain names, the bytes would list 305.
    dir = new_dir()
    local names = { "Ua", "Ub", "Uber", "Ubz" }
    for i = 0, MAX do
      names[#names + 1] = ("U%sz%03d"):format(vim.fn.nr2char(0x308), i)
    end
    for _, name in ipairs(names) do
      touch(dir .. "/" .. name)
    end
    if not listed_verbatim(dir, names) then
      pending("this file system normalizes the names")
      return
    end
    check_like_getcompletion(dir .. "/U")
    check_like_getcompletion(dir .. "/u")
  end)

  it(
    "orders a name with a combining mark by its base characters, as getcompletion() does",
    function()
      -- pathcmp() steps over the combining mark and compares the base characters only, so
      -- "Abe" + U+0308 + "y" sorts between "Abex" and "Abez"; ordered by bytes (CC 88 is above
      -- every ASCII letter) it would come behind "Abez". No two names share a key once the
      -- mark is skipped: getcompletion() leaves such ties to an unstable qsort.
      dir = new_dir()
      local names = { "Abex", "Abe\204\136y", "Abez" } -- U+0308 is CC 88
      for i = 0, MAX do
        names[#names + 1] = ("Abz%03d"):format(i)
      end
      for _, name in ipairs(names) do
        touch(dir .. "/" .. name)
      end
      if not listed_verbatim(dir, names) then
        pending("this file system normalizes the names")
        return
      end
      with_case_options(true, false, function()
        assert.is_true(#real_getcompletion(dir .. "/Ab", "file") > MAX, "more than a menu holds")
      end)
      check_like_getcompletion(dir .. "/Ab")
      check_like_getcompletion(dir .. "/Abz")
      press_tab(dir .. "/Ab")
      assert.same(
        { dir .. "/Abex", dir .. "/Abe\204\136y", dir .. "/Abez" },
        vim.list_slice(shown, 1, 3),
        "between Abex and Abez, not behind Abez"
      )
    end
  )

  it("keeps the big list when a single name in it has a combining mark", function()
    -- One name written the macOS way (a letter and its accent as two characters) used to
    -- send the whole directory back to getcompletion(): 0.8 s at five thousand names, after
    -- the walk had been paid for. Its place is the one of "item_005x", between item_005 and
    -- item_006; by its bytes it would come behind item_009.
    dir = new_dir()
    local marked = "item_00\204\1815x" -- U+0301 is CC 81
    local names = { marked }
    for i = 0, MAX + 9 do
      names[#names + 1] = ("item_%03d"):format(i)
    end
    for _, name in ipairs(names) do
      touch(dir .. "/" .. name)
    end
    if not listed_verbatim(dir, names) then
      pending("this file system normalizes the names")
      return
    end
    check_like_getcompletion(dir .. "/item_")
    press_tab(dir .. "/item_")
    assert.equals(0, getcompletion_calls, "the big list answers")
    assert.equals(dir .. "/" .. marked, shown[7], "after item_005")
  end)

  --- A base character with combining marks after it, in the scripts that write them.
  for _, script in ipairs({
    { name = "Thai", base = 0x0E01, marks = { 0x0E34, 0x0E48 } },
    { name = "Devanagari", base = 0x0939, marks = { 0x0902 } },
    { name = "Arabic", base = 0x0628, marks = { 0x0651, 0x064E } },
  }) do
    it(
      ("orders %s names with combining marks as getcompletion() does"):format(script.name),
      function()
        -- Every second name carries the marks, the rest do not, and each has its own number:
        -- no two share a key once the marks are skipped. By bytes all the plain names would
        -- come before all the marked ones; getcompletion() interleaves them by number. In such
        -- a script nearly every name carries a mark, so the list has to cope with that.
        local nr2char = vim.fn.nr2char
        local base, marks = nr2char(script.base), ""
        for _, mark in ipairs(script.marks) do
          marks = marks .. nr2char(mark)
        end
        dir = new_dir()
        local names = {}
        for i = 0, MAX + 9 do
          names[#names + 1] = ("%s%s%03d"):format(base, i % 2 == 1 and marks or "", i)
        end
        for _, name in ipairs(names) do
          touch(dir .. "/" .. name)
        end
        if not listed_verbatim(dir, names) then
          pending("this file system normalizes the names")
          return
        end
        check_like_getcompletion(dir .. "/")
      end
    )
  end

  it("orders names with Hangul jamo, ZWJ sequences and flags as getcompletion() does", function()
    -- Characters of more than two code points: a flag is two regional indicators, a family
    -- is three people joined by U+200D, a syllable is written as its jamo. `pathcmp()` reads
    -- the first code point of each and no more, so two flags that begin alike (DE, DK) or
    -- two families that begin with the same person are interleaved by the number behind.
    local nr2char = vim.fn.nr2char
    local function chars(...)
      local out = {}
      for _, cp in ipairs({ ... }) do
        out[#out + 1] = nr2char(cp)
      end
      return table.concat(out)
    end
    local clusters = {
      chars(0x1F1E9, 0x1F1EA), -- DE
      chars(0x1F1E9, 0x1F1F0), -- DK
      chars(0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467), -- man, woman, girl
      chars(0x1F468, 0x200D, 0x1F467), -- man, girl
      chars(0x1112, 0x1161, 0x11AB), -- a syllable as lead, vowel and tail
      chars(0x1112, 0x1161), -- ... without the tail
    }
    dir = new_dir()
    local names = {}
    for i = 0, MAX + 9 do
      names[#names + 1] = ("g_%s%03d"):format(clusters[i % #clusters + 1], i)
    end
    for _, name in ipairs(names) do
      touch(dir .. "/" .. name)
    end
    if not listed_verbatim(dir, names) then
      pending("this file system normalizes the names")
      return
    end
    check_like_getcompletion(dir .. "/g_")
  end)

  it("leaves a fragment with a NUL byte to getcompletion() instead of raising", function()
    -- No file name holds a NUL. The fold of a non-ASCII name goes through `toupper()`, and a
    -- NUL in a Lua string reaches `vim.fn` as a Blob: E976 out of the <Tab> mapping, where
    -- getcompletion() refuses such a fragment itself, under its pcall.
    dir = make_dir(MAX + 10, 0)
    with_case_options(true, false, function()
      for _, line in ipairs({ "\195\164\0x", "ab\0x", dir .. "/\195\164\0x", dir .. "/item_\0" }) do
        local ok, err = pcall(press_tab, line)
        assert.is_true(ok, "<Tab> on " .. vim.inspect(line) .. ": " .. tostring(err))
        assert.equals(1, getcompletion_calls, "getcompletion() has it: " .. vim.inspect(line))
      end
    end)
  end)

  it("lists a dot file only when asked for it by name", function()
    dir = make_dir(MAX + 100, 0)
    press_tab(dir .. "/.")
    assert.equals(1, getcompletion_calls, "one dot file is few matches")
  end)
end)
