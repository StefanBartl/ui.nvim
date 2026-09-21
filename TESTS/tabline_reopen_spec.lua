-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.tabline.reopen` -- the closed-tab ring and "reopen closed tab",
--- exercised directly against `M.record`/`M.reopen` rather than through the
--- `BufDelete` autocmd it is normally wired to (state.lua's own spec covers
--- that the autocmd still drops the buffer/pin correctly; this file is
--- about the ring itself).

local reopen = require("ui.tabline.reopen")
local state = require("ui.bindings.keymaps.tabufline.state")

local scratch_dir = vim.fn.stdpath("run") .. "/ui-tabline-reopen-spec"

---@param name string
---@return string path
local function write_file(name)
  vim.fn.mkdir(scratch_dir, "p")
  local path = scratch_dir .. "/" .. name
  vim.fn.writefile({ "line one", "line two", "line three" }, path)
  return path
end

---@param path string
---@return integer bufnr
local function open(path)
  local buf = vim.fn.bufadd(path)
  vim.fn.bufload(buf)
  vim.bo[buf].buflisted = true
  vim.api.nvim_set_current_buf(buf)
  return buf
end

describe("ui.tabline.reopen", function()
  before_each(function()
    state.setup()
    vim.cmd("tabnew")
    reopen.clear()
  end)

  after_each(function()
    reopen.clear()
    pcall(vim.cmd, "tabclose")
    pcall(vim.fn.delete, scratch_dir, "rf")
  end)

  describe("record", function()
    it("ignores a scratch buffer with no name", function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.t.bufs = { buf }
      reopen.record(buf)
      assert.is_false(reopen.has_any())
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("ignores a terminal buffer", function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_call(buf, function()
        vim.fn.jobstart({ vim.v.progpath, "--version" }, { term = true })
      end)
      vim.t.bufs = { buf }
      reopen.record(buf)
      assert.is_false(reopen.has_any())
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("ignores a file no longer readable on disk", function()
      local path = write_file("gone.txt")
      local buf = open(path)
      vim.fn.delete(path)
      reopen.record(buf)
      assert.is_false(reopen.has_any())
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("records a real file, newest first", function()
      local a = open(write_file("a.txt"))
      reopen.record(a)
      local b = open(write_file("b.txt"))
      reopen.record(b)

      local list = reopen.list()
      assert.equals(2, #list)
      assert.equals(vim.api.nvim_buf_get_name(b), list[1].path)
      assert.equals(vim.api.nvim_buf_get_name(a), list[2].path)

      pcall(vim.api.nvim_buf_delete, a, { force = true })
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end)

    it("keeps only the newest entry for the same path", function()
      local path = write_file("dup.txt")
      local buf1 = open(path)
      reopen.record(buf1)
      pcall(vim.api.nvim_buf_delete, buf1, { force = true })

      local buf2 = open(path)
      reopen.record(buf2)

      assert.equals(1, #reopen.list())
      pcall(vim.api.nvim_buf_delete, buf2, { force = true })
    end)

    it("caps the ring at 20 entries", function()
      local bufs = {}
      for i = 1, 25 do
        local buf = open(write_file(("f%d.txt"):format(i)))
        reopen.record(buf)
        bufs[#bufs + 1] = buf
      end

      assert.equals(20, #reopen.list())
      -- Newest first, oldest dropped.
      assert.equals(vim.api.nvim_buf_get_name(bufs[25]), reopen.list()[1].path)

      for _, b in ipairs(bufs) do
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end)
  end)

  describe("reopen", function()
    it("returns false when the ring is empty", function()
      assert.is_false(reopen.reopen())
    end)

    it("re-edits the file, restores the cursor, and removes it from the ring", function()
      local path = write_file("cursor.txt")
      local buf = open(path)
      vim.api.nvim_win_set_cursor(0, { 2, 3 })
      vim.cmd("normal! ma") -- writes the '"' mark on leaving/closing in real use;
      -- nvim_buf_get_mark(buf, '"') is what BufDelete would see -- set it
      -- directly since this test does not go through a real :bdelete.
      vim.api.nvim_buf_set_mark(buf, '"', 2, 3, {})
      reopen.record(buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })

      assert.is_true(reopen.has_any())
      local ok = reopen.reopen()
      assert.is_true(ok)
      assert.is_false(reopen.has_any())

      assert.equals(path, vim.api.nvim_buf_get_name(0))
      assert.same({ 2, 3 }, vim.api.nvim_win_get_cursor(0))
    end)

    it("places the reopened buffer at its remembered slot", function()
      local a = open(write_file("a.txt"))
      local b = open(write_file("b.txt"))
      local c = open(write_file("c.txt"))
      vim.t.bufs = { a, b, c }

      -- Through the real BufDelete autocmd (state.lua), not a manual
      -- `reopen.record` call: it records b at slot 2 (its position in
      -- vim.t.bufs at the moment it closes) and drops it from the list in
      -- the same tick -- the actual sequence a live close goes through.
      pcall(vim.api.nvim_buf_delete, b, { force = true })

      reopen.reopen()

      local names = {}
      for _, buf in ipairs(vim.t.bufs) do
        names[#names + 1] = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
      end
      assert.same({ "a.txt", "b.txt", "c.txt" }, names)

      for _, buf in ipairs(vim.t.bufs) do
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end)

    it("switches to an already-open buffer instead of opening a duplicate", function()
      local path = write_file("still-open.txt")
      local buf = open(path)
      vim.t.bufs = { buf }
      reopen.record(buf)
      -- Still open in THIS tab (unlike the usual case) -- e.g. recorded from
      -- a different tab's close of a buffer this one also has listed.
      local before = #vim.api.nvim_list_bufs()

      reopen.reopen()

      assert.equals(before, #vim.api.nvim_list_bufs())
      assert.equals(buf, vim.api.nvim_get_current_buf())
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("reopens a specific entry, not always the newest", function()
      local a = open(write_file("a.txt"))
      reopen.record(a)
      pcall(vim.api.nvim_buf_delete, a, { force = true })
      local b = open(write_file("b.txt"))
      reopen.record(b)
      pcall(vim.api.nvim_buf_delete, b, { force = true })

      local list = reopen.list()
      assert.equals(2, #list)
      local target = list[2] -- a.txt, the older one

      reopen.reopen(target)

      assert.equals(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t"), "a.txt")
      assert.equals(1, #reopen.list())
      pcall(vim.api.nvim_buf_delete, 0, { force = true })
    end)

    it("notifies instead of raising when the file was deleted after closing", function()
      local path = write_file("will-vanish.txt")
      local buf = open(path)
      reopen.record(buf)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      vim.fn.delete(path)

      local ok
      assert.has_no.errors(function()
        ok = reopen.reopen()
      end)
      assert.is_false(ok)
    end)
  end)
end)
