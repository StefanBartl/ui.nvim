-- ui.kit.viewer with `keys`: the winbar legend, the `?` cheatsheet and the
-- keymaps all come from one list, `table_view` sets the window up for an
-- aligned table, and `on_lines` decorates the first lines and every refresh.
---@diagnostic disable: need-check-nil, undefined-field, missing-fields

describe("ui.kit.viewer keys", function()
  local kit
  local opened

  before_each(function()
    package.loaded["ui.kit"] = nil
    package.loaded["ui.kit.viewer"] = nil
    package.loaded["ui.kit.viewer_keys"] = nil
    kit = require("ui.kit")
    opened = {}
  end)

  after_each(function()
    for _, surf in ipairs(opened) do
      pcall(function()
        surf:close()
      end)
    end
    vim.cmd("silent! only")
  end)

  local function open(opts)
    opts.lines = opts.lines or { "heading", "row one", "row two" }
    local surf = kit.viewer(opts)
    assert(surf, "viewer opens")
    opened[#opened + 1] = surf
    return surf
  end

  local function map_of(bufnr, lhs)
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if m.lhs == lhs then
        return m
      end
    end
  end

  describe("legend", function()
    local viewer_keys = require("ui.kit.viewer_keys")

    it("lists the entries that have a legend, then `? Keys` last", function()
      local bar = viewer_keys.legend({
        { lhs = "r", legend = "Refresh" },
        { lhs = "x", desc = "no legend: works, is not advertised" },
        { lhs = "<CR>", legend = "Open" },
      })
      assert.is_truthy(bar:find("r %%#Comment#Refresh"))
      assert.is_truthy(bar:find("<CR> %%#Comment#Open"))
      assert.is_nil(bar:find("x %%#Comment#"))
      assert.is_truthy(bar:find("%? %%#Comment#Keys%%#Normal#$"))
    end)

    it("is just `? Keys` for a list with nothing to advertise", function()
      assert.is_truthy(viewer_keys.legend({}):find("%? %%#Comment#Keys"))
    end)
  end)

  describe("cheatsheet lines", function()
    it("aligns the keys, appends `?`, and names the title", function()
      local lines = require("ui.kit.viewer_keys").cheatsheet_lines("Report", {
        { lhs = "r", desc = "Refresh" },
        { lhs = "<CR>", desc = "Open the row" },
      })
      assert.are.equal(" Report keys", lines[2])
      assert.are.equal("  r      Refresh", lines[4])
      assert.are.equal("  <CR>   Open the row", lines[5])
      assert.are.equal("  ?      Show this help", lines[6])
    end)
  end)

  describe("a viewer with keys", function()
    it("derives the winbar from the keys it wired", function()
      local ran = 0
      local surf = open({
        title = "Report",
        keys = {
          {
            lhs = "r",
            desc = "Refresh",
            legend = "Refresh",
            run = function()
              ran = ran + 1
            end,
          },
          { lhs = "gx", desc = "Hidden", run = function() end },
        },
      })
      local winbar = vim.wo[surf.winid].winbar
      assert.is_truthy(winbar:find("Refresh", 1, true))
      assert.is_nil(winbar:find("Hidden", 1, true))
      assert.is_not_nil(map_of(surf.bufnr, "r"))
      assert.is_not_nil(map_of(surf.bufnr, "gx"))
      assert.is_not_nil(map_of(surf.bufnr, "?"))

      map_of(surf.bufnr, "r").callback()
      assert.are.equal(1, ran)
    end)

    it("keeps the winbar row out of the content height", function()
      local plain = open({ lines = { "a", "b", "c" } })
      local with_keys = open({ lines = { "a", "b", "c" }, keys = {} })
      assert.are.equal(
        vim.api.nvim_win_get_height(plain.winid) + 1,
        vim.api.nvim_win_get_height(with_keys.winid)
      )
    end)

    it("leaves a height the caller chose alone", function()
      local surf = open({ lines = { "a", "b" }, height = 7, keys = {} })
      assert.are.equal(7, vim.api.nvim_win_get_height(surf.winid))
    end)

    it("gives run() a view that replaces the lines and the title", function()
      local surf = open({
        title = "One",
        keys = {
          {
            lhs = "n",
            desc = "Next",
            run = function(view)
              view.set_lines({ "fresh 1", "fresh 2", "fresh 3", "fresh 4" })
              view.set_title(" Two ")
            end,
          },
        },
      })
      map_of(surf.bufnr, "n").callback()
      assert.are.same(
        { "fresh 1", "fresh 2", "fresh 3", "fresh 4" },
        vim.api.nvim_buf_get_lines(surf.bufnr, 0, -1, false)
      )
    end)

    it("`?` opens a cheatsheet with exactly the wired keys", function()
      local surf = open({
        title = " Report ",
        keys = {
          { lhs = "r", desc = "Refresh", legend = "Refresh", run = function() end },
          { lhs = "gO", desc = "Open as HTML", run = function() end },
        },
      })
      map_of(surf.bufnr, "?").callback()
      local help = vim.api.nvim_get_current_buf()
      assert.are_not.equal(surf.bufnr, help)
      local text = table.concat(vim.api.nvim_buf_get_lines(help, 0, -1, false), "\n")
      assert.is_truthy(text:find("Report keys", 1, true))
      assert.is_truthy(text:find("Refresh", 1, true))
      assert.is_truthy(text:find("Open as HTML", 1, true))
      assert.is_truthy(text:find("q, <Esc>", 1, true))
      assert.is_truthy(text:find("Show this help", 1, true))
      assert.are.equal("lib-kit-viewer-help", vim.bo[help].filetype)
    end)

    it("takes the keymap descriptions and the cheatsheet filetype from the options", function()
      local surf = open({
        desc_prefix = "myplugin",
        help_title = "My view",
        help_filetype = "my-help",
        keys = { { lhs = "r", desc = "Refresh", run = function() end } },
      })
      assert.are.equal("myplugin: Refresh", map_of(surf.bufnr, "r").desc)
      map_of(surf.bufnr, "?").callback()
      assert.are.equal("my-help", vim.bo[vim.api.nvim_get_current_buf()].filetype)
    end)
  end)

  describe("a viewer without keys", function()
    it("is the viewer it was: no winbar, no `?`", function()
      local surf = open({ lines = { "a", "b" } })
      assert.are.equal("", vim.wo[surf.winid].winbar)
      assert.is_nil(map_of(surf.bufnr, "?"))
    end)
  end)

  describe("table_view", function()
    it("turns wrap off, cursorline on and starts on the first content row", function()
      local surf = open({ table_view = true })
      assert.is_false(vim.wo[surf.winid].wrap)
      assert.is_true(vim.wo[surf.winid].cursorline)
      assert.are.equal(2, vim.api.nvim_win_get_cursor(surf.winid)[1])
    end)

    it("is not applied when not asked for", function()
      local surf = open({})
      assert.is_false(vim.wo[surf.winid].cursorline)
      assert.are.equal(1, vim.api.nvim_win_get_cursor(surf.winid)[1])
    end)
  end)

  describe("on_lines", function()
    it("runs on the first lines and again after every set_lines", function()
      local seen = {}
      local surf = open({
        lines = { "head", "a" },
        on_lines = function(bufnr, lines)
          seen[#seen + 1] = { bufnr = bufnr, first = lines[1] }
        end,
      })
      assert.are.equal(1, #seen)
      assert.are.equal("head", seen[1].first)
      assert.are.equal(surf.bufnr, seen[1].bufnr)

      surf:set_lines({ "head2", "b" })
      assert.are.equal(2, #seen)
      assert.are.equal("head2", seen[2].first)
      assert.are.same({ "head2", "b" }, vim.api.nvim_buf_get_lines(surf.bufnr, 0, -1, false))
    end)

    it("also runs after a refresh made from a key", function()
      local count = 0
      local surf = open({
        on_lines = function()
          count = count + 1
        end,
        keys = {
          {
            lhs = "r",
            desc = "Refresh",
            run = function(view)
              view.set_lines({ "x", "y" })
            end,
          },
        },
      })
      assert.are.equal(1, count)
      map_of(surf.bufnr, "r").callback()
      assert.are.equal(2, count)
    end)
  end)
end)
