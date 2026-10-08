-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns, missing-fields

--- The preview of a slot: what a file slot shows (`kinds.file.preview`), the
--- renderer that turns a kind's answer into text (`view.preview`), the pane
--- beside the panel, and the panel's `K`.

local config = require("ui.slots.config")
local file_kind = require("ui.slots.kinds.file")
local panel = require("ui.slots.view.panel")
local preview = require("ui.slots.view.preview")
local registry = require("ui.slots.kinds.registry")
local slots = require("ui.slots")
local store = require("ui.slots.store")

describe("ui.slots preview", function()
  local dir
  local messages
  local original_notify
  local saved

  local function flush()
    vim.wait(20, function()
      return false
    end)
    vim.wait(500, function()
      return not require("ui.slots.view.chips")._pending()
    end, 2)
  end

  ---@param opts table|nil
  local function start(opts)
    vim.fn.delete(dir .. "/data", "rf")
    panel.reset()
    preview.reset()
    require("ui.slots.view.chips").reset()
    slots.reset()
    store.reset()
    registry.reset()
    slots.setup(vim.tbl_extend("force", {
      data_dir = dir .. "/data",
      save_delay_ms = 0,
      preview = { mode = "key", delay = 0 },
    }, opts or {}))
    slots.enable()
  end

  --- Write bytes to a file in the test directory.
  ---@param name string
  ---@param bytes string
  ---@return string path
  local function write(name, bytes)
    local path = dir .. "/" .. name
    local fd = assert(io.open(path, "wb"))
    fd:write(bytes)
    fd:close()
    return require("lib.nvim.fs.normkey")(path)
  end

  --- Press keys in Normal mode. The runner's child does not send CursorMoved by
  --- itself (a real Neovim does, before the next key), so it is sent here.
  ---@param keys string
  local function press(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, true, true), "x", false)
    if panel.is_open() then
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
    end
    flush()
  end

  ---@param slot table
  ---@return table
  local function preview_of(slot)
    return file_kind.preview(slot, { resolve = {} })
  end

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    messages = {}
    original_notify = vim.notify
    vim.notify = function(msg)
      messages[#messages + 1] = msg
    end
    saved = { lines = vim.o.lines, columns = vim.o.columns }
    vim.o.lines, vim.o.columns = 40, 140
    vim.cmd("silent! %bwipeout!")
    start()
  end)

  after_each(function()
    panel.reset()
    preview.reset()
    require("ui.slots.view.chips").reset()
    slots.reset()
    store.reset()
    registry.reset()
    config.reset()
    vim.o.lines, vim.o.columns = saved.lines, saved.columns
    vim.notify = original_notify
    vim.cmd("silent! only")
    vim.cmd("silent! %bwipeout!")
    vim.fn.delete(dir, "rf")
  end)

  describe("a file slot", function()
    it("shows the lines of the file and the filetype for highlighting", function()
      local path = write("a.lua", "local x = 1\nreturn x\n")
      local pv = preview_of({ kind = "file", path = path })
      assert.same({ "local x = 1", "return x" }, pv.lines)
      assert.equals("lua", pv.ft)
    end)

    it("does not show the newline that ends the file as a line, nor a missing one", function()
      assert.same(
        { "a", "b" },
        preview_of({ kind = "file", path = write("n1.txt", "a\nb\n") }).lines
      )
      assert.same({ "a", "b" }, preview_of({ kind = "file", path = write("n2.txt", "a\nb") }).lines)
      assert.same({}, preview_of({ kind = "file", path = write("empty.txt", "") }).lines)
      assert.same({ "", "x" }, preview_of({ kind = "file", path = write("n3.txt", "\nx\n") }).lines)
    end)

    it("drops the CR of a Windows file", function()
      local pv = preview_of({ kind = "file", path = write("crlf.txt", "one\r\ntwo\r\n") })
      assert.same({ "one", "two" }, pv.lines)
    end)

    it(
      "shows a NUL byte as ^@ in a binary file, so every line is one the buffer accepts",
      function()
        local pv = preview_of({ kind = "file", path = write("bin.dat", "ab\0cd\nef\0\0gh\n") })
        assert.same({ "ab^@cd", "ef^@^@gh" }, pv.lines)
        local buf = vim.api.nvim_create_buf(false, true)
        assert.is_true((pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, pv.lines)))
      end
    )

    it("shows a UTF-16 file as the bytes it is, without raising", function()
      local utf16 = "\255\254" .. "h\0e\0l\0l\0o\0\n\0"
      local pv = preview_of({ kind = "file", path = write("u16.txt", utf16) })
      assert.is_true(#pv.lines >= 1)
      assert.is_truthy(table.concat(pv.lines, "\n"):find("h^@e^@l^@l^@o^@", 1, true))
      local buf = vim.api.nvim_create_buf(false, true)
      assert.is_true((pcall(vim.api.nvim_buf_set_lines, buf, 0, -1, false, pv.lines)))
    end)

    it("cuts a big file at max_kb and says where", function()
      config.get().preview.max_kb = 1
      local lines = {}
      for i = 1, 400 do
        lines[i] = "line " .. i .. " " .. string.rep("x", 20)
      end
      local pv =
        preview_of({ kind = "file", path = write("big.txt", table.concat(lines, "\n") .. "\n") })
      local last = pv.lines[#pv.lines]
      assert.is_truthy(last:find("cut here", 1, true))
      assert.is_truthy(last:find("1 KB", 1, true))
      assert.is_true(#pv.lines < 100)
      -- the line before the note is a whole line of the file, not half of one
      assert.is_truthy(pv.lines[#pv.lines - 1]:find("^line %d+ x+$"))
    end)

    it("cuts at max_lines and says where", function()
      config.get().preview.max_lines = 10
      local lines = {}
      for i = 1, 50 do
        lines[i] = "l" .. i
      end
      local pv = preview_of({ kind = "file", path = write("many.txt", table.concat(lines, "\n")) })
      assert.equals(11, #pv.lines)
      assert.equals("l10", pv.lines[10])
      assert.is_truthy(pv.lines[11]:find("cut here", 1, true))
    end)

    it("shows the start of a big file that is one single line", function()
      config.get().preview.max_kb = 1
      local pv = preview_of({ kind = "file", path = write("oneline.js", string.rep("a", 5000)) })
      assert.equals(2, #pv.lines)
      assert.equals(1024, #pv.lines[1])
      assert.is_truthy(pv.lines[2]:find("cut here", 1, true))
    end)

    it("lists only as many entries of a directory as will be shown", function()
      config.get().preview.max_lines = 5
      for i = 1, 30 do
        write(string.format("e%02d.txt", i), "x")
      end
      local pv = preview_of({ kind = "file", path = dir })
      assert.equals(6, #pv.lines)
      assert.is_truthy(pv.lines[6]:find("cut here", 1, true))
    end)

    it("says nothing about a cut when the file fits", function()
      local pv = preview_of({ kind = "file", path = write("small.txt", "a\nb\n") })
      assert.is_nil(table.concat(pv.lines, "\n"):find("cut here", 1, true))
    end)

    it("cuts a very long line instead of handing over a megabyte of it", function()
      local pv =
        preview_of({ kind = "file", path = write("wide.txt", string.rep("x", 5000) .. "\n") })
      assert.equals(1, #pv.lines)
      assert.is_true(#pv.lines[1] < 2100)
      assert.is_truthy(pv.lines[1]:find("…", 1, true))
    end)

    it("says that the file is not there, and writes nothing", function()
      local pv = preview_of({ kind = "file", path = dir .. "/gone.txt" })
      assert.is_truthy(pv.lines[1]:find("does not exist", 1, true))
      assert.equals(0, vim.fn.filereadable(dir .. "/gone.txt"))
    end)

    it("lists a directory", function()
      write("d_one.txt", "x")
      local pv = preview_of({ kind = "file", path = dir })
      assert.is_true(vim.tbl_contains(pv.lines, "d_one.txt"))
    end)

    it("takes the path with placeholders and says when it is empty", function()
      local path = write("p.txt", "via placeholder\n")
      local pv = file_kind.preview(
        { kind = "file", path = "{dir}/p.txt" },
        { resolve = { dir = vim.fs.dirname(path) } }
      )
      assert.same({ "via placeholder" }, pv.lines)
      assert.is_truthy(
        file_kind
          .preview({ kind = "file", path = "{file}" }, { resolve = {} }).lines[1]
          :find("empty", 1, true)
      )
    end)

    it("shows the position the slot remembered", function()
      local path = write("pos.txt", "a\nb\nc\nd\n")
      local pv = preview_of({ kind = "file", path = path, line = 3, col = 2 })
      assert.same({ 3, 2 }, pv.pos)
    end)

    it("shows the position of this session when the slot has none", function()
      local path = write("pos2.txt", "a\nb\nc\nd\n")
      vim.cmd.edit(path)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      file_kind.remember_current()
      local pv = preview_of({ kind = "file", path = path })
      assert.equals(4, pv.pos[1])
      file_kind.forget_positions()
    end)
  end)

  describe("the renderer", function()
    it("takes what each kind answers with", function()
      assert.same({ "hello" }, preview.render({ kind = "yank", text = "hello" }).lines)
      assert.equals(
        "https://example.org",
        preview.render({ kind = "url", url = "https://example.org" }).lines[1]
      )
    end)

    it("says so for an unknown kind and for a kind without a preview", function()
      assert.is_truthy(preview.render({ kind = "ghost" }).lines[1]:find("unknown kind", 1, true))
      registry.register("plain", { apply = function() end })
      assert.is_truthy(preview.render({ kind = "plain" }).lines[1]:find("no preview", 1, true))
    end)

    it("replaces a preview that raises or answers with nonsense by a note", function()
      registry.register("boom", {
        apply = function() end,
        preview = function()
          error("kaboom")
        end,
      })
      registry.register("odd", {
        apply = function() end,
        preview = function()
          return { nothing = true }
        end,
      })
      assert.is_truthy(
        preview.render({ kind = "boom" }).lines[1]:find("could not be made", 1, true)
      )
      assert.is_truthy(preview.render({ kind = "odd" }).lines[1]:find("could not be made", 1, true))
    end)

    it("accepts the three shapes: lines, a buffer, a draw function", function()
      local geom = { row = 0, col = 90, width = 30, height = 10, side = "right" }
      slots.add({ kind = "yank", text = "x" })
      registry.register("shapes", {
        apply = function() end,
        preview = function(slot)
          if slot.shape == "lines" then
            return { lines = { "one", "two" } }
          elseif slot.shape == "buf" then
            return { buf = slot.buf }
          end
          return {
            draw = function(surf)
              surf:set_lines({ "drawn" })
            end,
          }
        end,
      })
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "from a buffer" })
      store.set(2, { kind = "shapes", shape = "lines" })
      store.set(3, { kind = "shapes", shape = "buf", buf = buf })
      store.set(4, { kind = "shapes", shape = "draw" })
      assert.is_true(preview.show(2, geom))
      assert.same({ "one", "two" }, preview.lines())
      preview.show(3, geom)
      assert.same({ "from a buffer" }, preview.lines())
      preview.show(4, geom)
      assert.same({ "drawn" }, preview.lines())
    end)

    it("never leaves the text of the slot before when the next one fails", function()
      local geom = { row = 0, col = 90, width = 30, height = 10, side = "right" }
      registry.register("flaky", {
        apply = function() end,
        preview = function(slot)
          if slot.ok then
            return { lines = { "good text" } }
          end
          error("nope")
        end,
      })
      store.set(1, { kind = "flaky", ok = true })
      store.set(2, { kind = "flaky" })
      preview.show(1, geom)
      assert.same({ "good text" }, preview.lines())
      preview.show(2, geom)
      assert.is_nil(table.concat(preview.lines(), "\n"):find("good text", 1, true))
    end)

    it("survives a draw function that raises", function()
      local geom = { row = 0, col = 90, width = 30, height = 10, side = "right" }
      registry.register("badraw", {
        apply = function() end,
        preview = function()
          return {
            draw = function()
              error("x")
            end,
          }
        end,
      })
      store.set(1, { kind = "badraw" })
      assert.is_true(preview.show(1, geom))
      assert.is_truthy(table.concat(preview.lines(), "\n"):find("could not be drawn", 1, true))
    end)

    it("cleans text that a kind hands over with control characters", function()
      local geom = { row = 0, col = 90, width = 30, height = 10, side = "right" }
      registry.register("dirty", {
        apply = function() end,
        preview = function()
          return { lines = { "a\nb", "c\0d", "e\rf" } }
        end,
      })
      store.set(1, { kind = "dirty" })
      assert.is_true(preview.show(1, geom))
      assert.same({ "a b", "c^@d", "e f" }, preview.lines())
    end)
  end)

  describe("a url slot", function()
    local geom = { row = 2, col = 90, width = 30, height = 20, side = "right" }
    local saved_hover, asked, deliver_now, pending

    --- A stand-in for hover.nvim: records what it was asked, answers at once or
    --- when the test says so.
    local function fake_hover(answer)
      package.loaded["hover"] = {
        preview_target = function(target, cb, opts)
          asked[#asked + 1] = { target = target, opts = opts }
          local entry = { cb = cb, cancelled = false }
          pending[#pending + 1] = entry
          if deliver_now then
            cb(answer or { lines = { "HTTP 200 OK", "A page" } })
          end
          return {
            cancel = function()
              entry.cancelled = true
            end,
          }
        end,
      }
    end

    before_each(function()
      saved_hover = package.loaded["hover"]
      asked, pending, deliver_now = {}, {}, true
      config.get().preview.fetch = true
    end)

    after_each(function()
      package.loaded["hover"] = saved_hover
    end)

    local function pane_text()
      return table.concat(preview.lines(), "\n")
    end

    local function wait_for_text(needle)
      vim.wait(500, function()
        return pane_text():find(needle, 1, true) ~= nil
      end, 5)
    end

    it("shows the address and the host when hover.nvim is not there", function()
      package.loaded["hover"] = nil
      package.preload["hover"] = function()
        error("no hover")
      end
      store.add({ kind = "url", url = "https://example.org/a" })
      preview.show(1, geom)
      package.preload["hover"] = nil
      assert.is_truthy(pane_text():find("host: example.org", 1, true))
    end)

    it("asks hover.nvim only when a preview is shown, not when the slot is rendered", function()
      fake_hover()
      store.add({ kind = "url", url = "https://example.org/a" })
      require("ui.slots.view.chips").open()
      flush()
      assert.equals(0, #asked)
    end)

    it("shows loading first and then the page", function()
      deliver_now = false
      fake_hover()
      store.add({ kind = "url", url = "https://example.org/a" })
      preview.show(1, geom)
      assert.is_truthy(pane_text():find("loading", 1, true))
      assert.equals(1, #asked)
      assert.equals("https://example.org/a", asked[1].target)
      assert.is_true(asked[1].opts.fetch)
      pending[1].cb({ lines = { "HTTP 200 OK", "A page" } })
      wait_for_text("A page")
      assert.same({ "HTTP 200 OK", "A page" }, preview.lines())
    end)

    it("shows an error answer as text", function()
      fake_hover({ lines = { "x no answer", "could not resolve host" } })
      store.add({ kind = "url", url = "https://nowhere.invalid/" })
      preview.show(1, geom)
      wait_for_text("no answer")
      assert.is_truthy(pane_text():find("could not resolve host", 1, true))
    end)

    it("drops the answer of a slot the cursor has left, and cancels its request", function()
      deliver_now = false
      fake_hover()
      store.add({ kind = "url", url = "https://example.org/one" })
      store.add({ kind = "file", path = write("later.txt", "the file\n") })
      preview.show(1, geom)
      preview.show(2, geom)
      assert.is_true(pending[1].cancelled)
      pending[1].cb({ lines = { "stale page" } })
      vim.wait(60, function()
        return false
      end)
      assert.same({ "the file" }, preview.lines())
    end)

    it("shows only the last of several quick moves", function()
      deliver_now = false
      fake_hover()
      store.add({ kind = "url", url = "https://example.org/one" })
      store.add({ kind = "url", url = "https://example.org/two" })
      preview.show(1, geom)
      preview.show(2, geom)
      pending[2].cb({ lines = { "page two" } })
      pending[1].cb({ lines = { "page one" } })
      wait_for_text("page two")
      vim.wait(60, function()
        return false
      end)
      assert.same({ "page two" }, preview.lines())
    end)

    it("ignores an answer that arrives after the pane was closed", function()
      deliver_now = false
      fake_hover()
      store.add({ kind = "url", url = "https://example.org/one" })
      preview.show(1, geom)
      preview.close()
      assert.is_true(pending[1].cancelled)
      pending[1].cb({ lines = { "late" } })
      vim.wait(60, function()
        return false
      end)
      assert.is_false(preview.is_open())
    end)

    it("falls back to the address when hover.nvim raises", function()
      package.loaded["hover"] = {
        preview_target = function()
          error("boom")
        end,
      }
      store.add({ kind = "url", url = "https://example.org/one" })
      preview.show(1, geom)
      wait_for_text("host: example.org")
      assert.is_truthy(pane_text():find("could not preview", 1, true))
    end)

    it("falls back to the address when hover.nvim answers nothing usable", function()
      fake_hover({ lines = {} })
      store.add({ kind = "url", url = "https://example.org/one" })
      preview.show(1, geom)
      wait_for_text("host: example.org")
      assert.is_truthy(pane_text():find("host: example.org", 1, true))
    end)

    it("makes no request unless preview.fetch is on (the default)", function()
      fake_hover()
      assert.is_false(config.DEFAULTS.preview.fetch)
      config.get().preview.fetch = false
      store.add({ kind = "url", url = "https://example.org/one" })
      preview.show(1, geom)
      assert.equals(0, #asked)
      assert.is_truthy(pane_text():find("host: example.org", 1, true))
    end)

    it("never asks about file: or mailto: addresses, nor one that is refused", function()
      fake_hover()
      store.add({ kind = "url", url = "mailto:someone@example.org" })
      store.add({ kind = "url", url = "file:///tmp/x" })
      preview.show(1, geom)
      preview.show(2, geom)
      assert.equals(0, #asked)
    end)

    it("does not ask twice for the same slot, but asks again once it changed", function()
      fake_hover()
      store.add({ kind = "url", url = "https://example.org/one" })
      preview.show(1, geom)
      preview.show(1, geom)
      preview.show(1, geom)
      assert.equals(1, #asked)
      store.update(1, { url = "https://example.org/two" })
      preview.show(1, geom)
      assert.equals(2, #asked)
      assert.equals("https://example.org/two", asked[2].target)
    end)

    it("does not ask again when the panel redraws and the slot shown did not change", function()
      local count = 0
      package.loaded["hover"] = {
        preview_target = function()
          count = count + 1
          return {
            cancel = function() end,
          }
        end,
      }
      slots.add({ kind = "url", url = "https://example.org/a" })
      slots.add({ kind = "url", url = "https://example.org/b" })
      slots.add({ kind = "url", url = "https://example.org/c" })
      panel.open()
      press("K")
      assert.equals(1, count)
      -- slot 3 goes; the pane shows slot 1, which did not change
      slots.clear(3)
      flush()
      assert.equals(1, count)
    end)

    it("makes one request when the panel moves or clears a url slot", function()
      local count = 0
      package.loaded["hover"] = {
        preview_target = function()
          count = count + 1
          return {
            cancel = function() end,
          }
        end,
      }
      slots.add({ kind = "url", url = "https://example.org/a" })
      slots.add({ kind = "url", url = "https://example.org/b" })
      slots.add({ kind = "url", url = "https://example.org/c" })
      panel.open()
      press("K")
      assert.equals(1, count)
      press("<C-j>")
      flush()
      assert.equals(2, count)
      press("dd")
      flush()
      assert.equals(3, count)
    end)

    it("never fetches an address built from placeholders", function()
      fake_hover()
      store.add({ kind = "url", url = "https://example.org/{word}" })
      preview.show(1, geom, {
        resolve = {
          word = function()
            return "hello"
          end,
        },
      })
      assert.equals(0, #asked)
      assert.is_truthy(pane_text():find("https://example.org/hello", 1, true))
    end)
  end)

  describe("hardening", function()
    local geom = { row = 2, col = 90, width = 30, height = 20, side = "right" }

    it("keeps no undo history in the pane", function()
      store.add({ kind = "file", path = write("undo.txt", "text\n") })
      preview.show(1, geom)
      assert.equals(-1, vim.bo[vim.api.nvim_win_get_buf(preview.winid())].undolevels)
    end)

    it("says the buffer is gone, instead of raising, and never keeps the slot before", function()
      registry.register("ghost", {
        apply = function() end,
        preview = function()
          return { buf = 987654 }
        end,
      })
      store.add({ kind = "file", path = write("before.txt", "the file before\n") })
      store.set(2, { kind = "ghost" })
      preview.show(1, geom)
      assert.same({ "the file before" }, preview.lines())
      assert.has_no.errors(function()
        preview.show(2, geom)
      end)
      assert.same({ "(the buffer is gone)" }, preview.lines())
      assert.equals(2, preview.shown())
    end)

    it("does not raise for a position that is not numbers", function()
      registry.register("oddpos", {
        apply = function() end,
        preview = function()
          return { lines = { "a", "b" }, pos = { "x", "y" } }
        end,
      })
      store.add({ kind = "oddpos" })
      assert.has_no.errors(function()
        preview.show(1, geom)
      end)
      assert.same({ "a", "b" }, preview.lines())
    end)

    it("shows a file slot whose line and column in the data file are not numbers", function()
      local path = write("oddline.txt", "one\ntwo\n")
      local pv = preview_of({ kind = "file", path = path, line = "abc", col = { 1 } })
      assert.same({ "one", "two" }, pv.lines)
      assert.is_nil(pv.pos)
    end)

    it("does not touch a network path of a slot that is not from setup()", function()
      local uv = vim.uv or vim.loop
      local original = uv.fs_stat
      local stats = 0
      uv.fs_stat = function(path)
        if tostring(path):find("192.0.2.1", 1, true) then
          stats = stats + 1
        end
        return nil
      end
      local network = "//192.0.2.1/share/x.md"
      local written = preview_of({ kind = "file", path = "//192.0.2.1/share/notes.md" })
      local backslashes = preview_of({ kind = "file", path = [[\\192.0.2.1\share\notes.md]] })
      -- through a placeholder that holds text the user copied: the same
      local via_clip = file_kind.preview(
        { kind = "file", path = "{clip}" },
        { resolve = { clip = network } }
      )
      local applied_ok, applied_why = file_kind.apply(
        { kind = "file", path = "{clip}" },
        { resolve = { clip = network } }
      )
      local before_fixed = stats
      preview_of({ kind = "file", path = "//192.0.2.1/share/notes.md", fixed = true })
      uv.fs_stat = original
      assert.equals(0, before_fixed)
      assert.is_true(stats > before_fixed)
      for _, pv in ipairs({ written, backslashes, via_clip }) do
        assert.is_truthy(pv.lines[1]:find("network path", 1, true))
      end
      assert.is_false(applied_ok)
      assert.is_truthy(applied_why:find("setup()", 1, true))
    end)

    it(
      "follows the user's own tree onto a network share: {dir} and {root} are not refused",
      function()
        local uv = vim.uv or vim.loop
        local original = uv.fs_stat
        local seen = {}
        uv.fs_stat = function(path)
          if tostring(path):find("wsl.localhost", 1, true) then
            seen[#seen + 1] = path
          end
          return nil
        end
        local pv = file_kind.preview({ kind = "file", path = "{dir}/TODO.md" }, {
          resolve = {
            dir = function()
              return "//wsl.localhost/Ubuntu/home/me/proj"
            end,
          },
        })
        uv.fs_stat = original
        assert.equals(1, #seen)
        assert.is_truthy(pv.lines[1]:find("file does not exist", 1, true))
      end
    )

    it("refuses a network path in the editor and the API, with the reason", function()
      local err = registry.validate({ kind = "file", path = "//192.0.2.1/share/notes.md" })
      assert.is_truthy(err and err:find("setup()", 1, true))
      assert.is_nil(registry.validate({ kind = "file", path = "//192.0.2.1/x", fixed = true }))
      local number, why = slots.add({ kind = "file", path = [[\\192.0.2.1\share\notes.md]] })
      assert.is_nil(number)
      assert.is_truthy(why)
    end)

    it("does not take the trust from the slot a caller hands in", function()
      local number, why = slots.add({ kind = "url", url = "file:///C:/x.bat", fixed = true })
      assert.is_nil(number)
      assert.is_truthy(why and why:find("setup()", 1, true))
      slots.setup({ slots = { [9] = { kind = "url", url = "file:///C:/trusted.html" } } })
      -- a copy of a slot from setup() is not one from setup()
      local copy, copy_why = slots.add(slots.get(9))
      assert.is_nil(copy)
      assert.is_truthy(copy_why)
      assert.equals(1, #slots.list())
    end)

    it("gives a slot that came after the last BufLeave its position, cursor unmoved", function()
      local path = write("late.txt", "a\nb\nc\nd\n")
      vim.cmd.edit(path)
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      file_kind.remember_current()
      slots.add({ kind = "file", path = path })
      file_kind.remember_current()
      assert.equals(4, store.get(1).line)
      file_kind.forget_positions()
    end)

    it("does not ask the file system about every slot on a BufLeave", function()
      for i = 1, 400 do
        store.add({ kind = "file", path = dir .. "/other/file" .. i .. ".txt" })
      end
      local path = write("here.txt", "a\nb\n")
      store.add({ kind = "file", path = path })
      vim.cmd.edit(path)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local uv = vim.uv or vim.loop
      local original = uv.fs_realpath
      local calls = 0
      uv.fs_realpath = function(...)
        calls = calls + 1
        return original(...)
      end
      file_kind.remember_current()
      uv.fs_realpath = original
      assert.equals(2, store.get(401).line)
      assert.is_true(calls < 150, "asked for " .. calls .. " real paths")
      file_kind.forget_positions()
    end)

    it("finds the slot of a file also for a relative path as written", function()
      local path = write("rel.txt", "x\n")
      local cwd = vim.fn.getcwd()
      vim.cmd.cd(vim.fs.dirname(path))
      local list = {}
      for i = 1, 300 do
        list[i] = { n = i, kind = "file", path = "other" .. i .. ".txt" }
      end
      list[301] = { n = 301, kind = "file", path = "rel.txt" }
      local hit = file_kind.matching(path, list, true, 0)[1]
      vim.cmd.cd(cwd)
      assert.equals(301, hit and hit.n)
    end)
  end)

  describe("which window the placeholders belong to", function()
    it(
      "a path with {dir} previews the file <CR> will open, not one relative to the panel",
      function()
        local path = write("TODO.md", "the todo\n")
        slots.add({ kind = "file", path = "{dir}/TODO.md" })
        vim.cmd.edit(path)
        panel.open()
        press("K")
        assert.same({ "the todo" }, preview.lines())
      end
    )

    it("{file} resolves to the file you came from", function()
      local path = write("self.txt", "i am the file\n")
      slots.add({ kind = "file", path = "{file}" })
      vim.cmd.edit(path)
      panel.open()
      press("K")
      assert.same({ "i am the file" }, preview.lines())
    end)

    it("the preview and the run agree", function()
      local path = write("same.txt", "same content\n")
      slots.add({ kind = "file", path = "{dir}/same.txt" })
      local other = write("other.txt", "elsewhere\n")
      vim.cmd.edit(other)
      panel.open()
      press("K")
      local shown = preview.lines()[1]
      press("<CR>")
      assert.equals("same content", shown)
      assert.equals(
        require("lib.nvim.fs.normkey")(path),
        require("lib.nvim.fs.normkey")(vim.api.nvim_buf_get_name(0))
      )
    end)
  end)

  describe("the pane", function()
    local geom = { row = 0, col = 100, width = 30, height = 12, side = "right" }

    it("opens beside the panel on its free side, not focusable and read-only", function()
      store.add({ kind = "yank", text = "hello" })
      assert.is_true(preview.show(1, geom))
      local win = preview.winid()
      local cfg = vim.api.nvim_win_get_config(win)
      assert.is_false(cfg.focusable)
      assert.is_true(cfg.col + cfg.width + 2 <= geom.col)
      assert.equals(geom.height, cfg.height)
      assert.is_false(vim.bo[vim.api.nvim_win_get_buf(win)].modifiable)
    end)

    it("opens to the right of a panel docked at the left", function()
      store.add({ kind = "yank", text = "hello" })
      assert.is_true(preview.show(1, { row = 0, col = 0, width = 30, height = 12, side = "left" }))
      assert.is_true(vim.api.nvim_win_get_config(preview.winid()).col >= 30)
    end)

    it("is reused for the next slot and does not open another window", function()
      store.add({ kind = "yank", text = "one" })
      store.add({ kind = "yank", text = "two" })
      preview.show(1, geom)
      local win = preview.winid()
      preview.show(2, geom)
      assert.equals(win, preview.winid())
      assert.same({ "two" }, preview.lines())
      assert.equals(2, preview.shown())
    end)

    it("does not open where there is no room, and says nothing", function()
      store.add({ kind = "yank", text = "hello" })
      assert.is_false(
        preview.show(1, { row = 0, col = 10, width = 30, height = 12, side = "right" })
      )
      assert.is_false(preview.is_open())
    end)

    it("closes when the slot is gone", function()
      store.add({ kind = "yank", text = "hello" })
      preview.show(1, geom)
      store.clear(1)
      assert.is_false(preview.show(1, geom))
      assert.is_false(preview.is_open())
    end)

    it("puts the cursor at the remembered position of a file", function()
      local lines = {}
      for i = 1, 100 do
        lines[i] = "row " .. i
      end
      local path = write("far.txt", table.concat(lines, "\n") .. "\n")
      store.add({ kind = "file", path = path, line = 60, col = 3 })
      preview.show(1, geom)
      assert.equals(60, preview.cursor_line())
    end)

    it("highlights with the filetype of the file", function()
      local path = write("hl.lua", "local a = 1\n")
      store.add({ kind = "file", path = path })
      preview.show(1, geom)
      assert.equals("lua", vim.bo[vim.api.nvim_win_get_buf(preview.winid())].filetype)
    end)

    it("sets the filetype once, not on every move", function()
      local a = write("one.lua", "local a = 1\n")
      local b = write("two.lua", "local b = 2\n")
      store.add({ kind = "file", path = a })
      store.add({ kind = "file", path = b })
      local fired = 0
      local id = vim.api.nvim_create_autocmd("FileType", {
        pattern = "lua",
        callback = function()
          fired = fired + 1
        end,
      })
      preview.show(1, geom)
      preview.show(2, geom)
      preview.show(1, geom)
      vim.api.nvim_del_autocmd(id)
      assert.equals(1, fired)
    end)

    it("clears a draw preview first: lines and filetype of the slot before are gone", function()
      registry.register("lazy", {
        apply = function() end,
        preview = function()
          return {
            draw = function() end,
          }
        end,
      })
      local path = write("before.lua", "local before = true\n")
      store.add({ kind = "file", path = path })
      store.set(2, { kind = "lazy" })
      preview.show(1, geom)
      assert.same({ "local before = true" }, preview.lines())
      preview.show(2, geom)
      assert.same({ "" }, preview.lines())
      assert.equals("", vim.bo[vim.api.nvim_win_get_buf(preview.winid())].filetype)
    end)

    it("leaves no window and no buffer behind", function()
      store.add({ kind = "yank", text = "hello" })
      local before = #vim.api.nvim_list_wins()
      preview.show(1, geom)
      local buf = vim.api.nvim_win_get_buf(preview.winid())
      preview.close()
      assert.equals(before, #vim.api.nvim_list_wins())
      assert.is_false(vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf))
    end)
  end)

  describe("in the panel", function()
    local function add_files()
      for i = 1, 3 do
        local path = write("f" .. i .. ".txt", "content of file " .. i .. "\n")
        slots.add({ kind = "file", path = path })
      end
    end

    it("K shows the preview of the slot under the cursor and K hides it", function()
      add_files()
      panel.open()
      assert.is_false(preview.is_open())
      press("K")
      assert.is_true(preview.is_open())
      assert.same({ "content of file 1" }, preview.lines())
      press("K")
      assert.is_false(preview.is_open())
    end)

    it("follows the cursor while it is open", function()
      add_files()
      panel.open()
      press("K")
      press("j")
      assert.same({ "content of file 2" }, preview.lines())
      press("j")
      assert.same({ "content of file 3" }, preview.lines())
      press("gg")
      assert.same({ "content of file 1" }, preview.lines())
    end)

    it("follows a typed number and a moved slot", function()
      add_files()
      panel.open()
      press("K")
      press("3")
      assert.same({ "content of file 3" }, preview.lines())
      press("<C-k>")
      assert.same({ "content of file 3" }, preview.lines())
    end)

    it("is not there until asked for in the default mode", function()
      add_files()
      panel.open()
      assert.is_false(preview.is_open())
    end)

    it("opens by itself in auto mode, and follows the cursor", function()
      start({ preview = { mode = "auto", delay = 0 } })
      add_files()
      panel.open()
      assert.is_true(preview.is_open())
      press("j")
      assert.same({ "content of file 2" }, preview.lines())
    end)

    it("waits for the delay in auto mode before it follows the cursor", function()
      start({ preview = { mode = "auto", delay = 80 } })
      add_files()
      panel.open()
      press("j")
      assert.same({ "content of file 1" }, preview.lines())
      vim.wait(1000, function()
        return preview.lines()[1] == "content of file 2"
      end, 10)
      assert.same({ "content of file 2" }, preview.lines())
    end)

    it("says when the preview is switched off, and shows none", function()
      start({ preview = { mode = "off" } })
      add_files()
      panel.open()
      press("K")
      assert.is_false(preview.is_open())
      assert.is_truthy(table.concat(messages, "\n"):find("switched off", 1, true))
    end)

    it("closes with the panel, by q, by the focus leaving and by close()", function()
      add_files()
      panel.open()
      press("K")
      press("q")
      assert.is_false(preview.is_open())
      panel.open()
      press("K")
      panel.close()
      assert.is_false(preview.is_open())
      vim.cmd.vsplit()
      local other = vim.api.nvim_get_current_win()
      panel.open()
      press("K")
      vim.api.nvim_set_current_win(other)
      flush()
      assert.is_false(preview.is_open())
    end)

    it("does not cancel or reload the page when the cursor moves within its row", function()
      local saved_hover = package.loaded["hover"]
      local asked, cancelled, deliver = 0, 0, nil
      package.loaded["hover"] = {
        preview_target = function(_, cb)
          asked = asked + 1
          deliver = cb
          return {
            cancel = function()
              cancelled = cancelled + 1
            end,
          }
        end,
      }
      config.get().preview.fetch = true
      slots.add({ kind = "url", url = "https://example.org/a" })
      panel.open()
      press("K")
      assert.equals(1, asked)
      press("l")
      press("h")
      flush()
      assert.equals(1, asked)
      assert.equals(0, cancelled)
      deliver({ lines = { "the page" } })
      vim.wait(500, function()
        return preview.lines()[1] == "the page"
      end, 5)
      assert.same({ "the page" }, preview.lines())
      press("l")
      flush()
      assert.same({ "the page" }, preview.lines())
      package.loaded["hover"] = saved_hover
    end)

    it("goes with the panel when its window is closed directly", function()
      add_files()
      panel.open()
      press("K")
      assert.is_true(preview.is_open())
      vim.cmd("close")
      flush()
      assert.is_false(preview.is_open())
    end)

    it("says when there is no room, and stays off", function()
      add_files()
      vim.o.columns = 80
      config.get().width = 0.8
      panel.open()
      press("K")
      assert.is_false(preview.is_open())
      assert.is_truthy(table.concat(messages, "\n"):find("no room", 1, true))
    end)

    it("is wanted again when the panel comes back from the editor", function()
      add_files()
      panel.open()
      press("K")
      local sheet = require("ui.kit.sheet")
      local original = sheet.open
      local opts
      sheet.open = function(o)
        opts = o
        return {
          is_valid = function()
            return true
          end,
        }
      end
      press("e")
      sheet.open = original
      opts.on_cancel()
      flush()
      assert.is_true(panel.is_open())
      assert.is_true(preview.is_open())
    end)

    it("a cursor moved at once does not read a file per row in key mode with a delay", function()
      start({ preview = { mode = "key", delay = 400 } })
      add_files()
      panel.open()
      press("K")
      assert.same({ "content of file 1" }, preview.lines())
      -- the timer that the K press itself started has run out
      vim.wait(500)
      local shown = {}
      local original = preview.show
      preview.show = function(n, ...)
        shown[#shown + 1] = n
        return original(n, ...)
      end
      press("j")
      press("j")
      vim.wait(2000, function()
        return preview.lines()[1] == "content of file 3"
      end, 10)
      preview.show = original
      assert.same({ "content of file 3" }, preview.lines())
      -- only where the cursor came to rest, not on the row passed
      assert.same({ 3 }, shown)
    end)

    it("steps aside with the panel when the editor opens, and is not left over", function()
      add_files()
      panel.open()
      press("K")
      local sheet = require("ui.kit.sheet")
      local original = sheet.open
      sheet.open = function()
        return {
          is_valid = function()
            return true
          end,
        }
      end
      press("e")
      sheet.open = original
      assert.is_false(preview.is_open())
    end)

    it("follows a change of the slots while it is open", function()
      add_files()
      panel.open()
      press("K")
      slots.clear(1)
      flush()
      assert.same({ "content of file 2" }, preview.lines())
    end)

    it("shows a note for a slot of a kind without a preview, not the one before", function()
      add_files()
      registry.register("plain", { apply = function() end })
      store.set(4, { kind = "plain" })
      panel.open()
      press("K")
      press("4")
      assert.is_truthy(preview.lines()[1]:find("no preview", 1, true))
    end)
  end)
end)
