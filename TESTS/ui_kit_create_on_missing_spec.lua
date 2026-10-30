-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.kit.create_on_missing`: the "path does not exist" dialog (a re-export of
--- `lib.nvim.ui.kit.create_on_missing`, whose TESTS/ui_kit_create_on_missing_spec.lua covers every
--- branch). This pins the ui.nvim names and the paths a consumer relies on: Create with the missing
--- parents, Cancel, and the "Open in filetree" button only for a set-up filetree.nvim.

local kit = require("ui.kit")
local com = require("ui.kit.create_on_missing")

describe("ui.kit.create_on_missing", function()
  local root, seen, answer

  --- Run the dialog for `path`, answered with `value`; the result on_done got.
  local function run(path, value, opts)
    seen, answer = {}, value
    local box = {}
    opts = vim.tbl_extend("force", opts or {}, {
      path = path,
      on_done = function(res)
        box.res = res
      end,
    })
    kit.create_on_missing(opts)
    vim.wait(500, function()
      return box.res ~= nil
    end, 5)
    return box.res
  end

  before_each(function()
    root = vim.fs.normalize(vim.fn.tempname())
    vim.fn.mkdir(root, "p")
    kit.set_dialog_hook(function(kind, opts)
      seen[#seen + 1] = { kind = kind, choices = opts.choices }
      return true, answer
    end)
  end)

  after_each(function()
    kit.set_dialog_hook(nil)
    package.loaded["filetree"] = nil
    vim.fn.delete(root, "rf")
  end)

  it("is lib.nvim's module under both names", function()
    assert.equals(require("lib.nvim.ui.kit.create_on_missing"), com)
    assert.equals(require("lib.nvim.ui.kit").create_on_missing, kit.create_on_missing)
  end)

  it("creates the file with its missing parents and opens it", function()
    local target = root .. "/a/b/new.lua"
    local res = run(target, com.CREATE)
    assert.equals("created", res.action)
    assert.equals("file", res.kind)
    assert.equals(1, vim.fn.filereadable(target))
    assert.equals(target, vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
    vim.cmd("enew!")
  end)

  it("creates nothing on Cancel", function()
    local res = run(root .. "/x/y.lua", com.CANCEL)
    assert.equals("cancelled", res.action)
    assert.equals(0, vim.fn.isdirectory(root .. "/x"))
  end)

  it("offers a set-up filetree.nvim and reveals the existing ancestor", function()
    package.loaded["filetree"] = nil
    run(root .. "/x/y.lua", com.CANCEL)
    assert.same({ com.CREATE, com.CANCEL }, seen[1].choices)

    local revealed
    package.loaded["filetree"] = {
      is_initialized = function()
        return true
      end,
      adapter = function()
        return {
          open_reveal = function(p)
            revealed = p
            return true
          end,
        }
      end,
    }
    local res = run(root .. "/x/y.lua", com.FILETREE)
    assert.same({ com.CREATE, com.FILETREE, com.CANCEL }, seen[1].choices)
    assert.equals("filetree", res.action)
    assert.equals(root, revealed)
    assert.equals(0, vim.fn.isdirectory(root .. "/x"))
  end)
end)
