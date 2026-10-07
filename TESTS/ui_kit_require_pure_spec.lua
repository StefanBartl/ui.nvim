-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- LUA-92: `require` registers nothing. `ui.kit` used to create `:KitPreview`
--- when it was loaded and `ui.kit.toast` the `lib_kit_toast_resize` group, so
--- any sibling plugin that merely required the kit got both.

local function unload()
  for name in pairs(package.loaded) do
    if name == "ui.kit" or name:match("^ui%.kit%.") then
      package.loaded[name] = nil
    end
  end
end

local function has_group(name)
  return pcall(vim.api.nvim_get_autocmds, { group = name })
end

describe("requiring ui.kit", function()
  before_each(function()
    pcall(vim.api.nvim_del_user_command, "KitPreview")
    pcall(vim.api.nvim_del_augroup_by_name, "lib_kit_toast_resize")
    unload()
  end)

  after_each(function()
    pcall(vim.api.nvim_del_user_command, "KitPreview")
    pcall(vim.api.nvim_del_augroup_by_name, "lib_kit_toast_resize")
    unload()
  end)

  it("registers neither :KitPreview nor the toast resize group", function()
    require("ui.kit")
    require("ui.kit.toast")
    assert.equals(0, vim.fn.exists(":KitPreview"))
    assert.is_false(has_group("lib_kit_toast_resize"))
  end)

  it("kit.setup() registers :KitPreview", function()
    require("ui.kit").setup()
    assert.equals(2, vim.fn.exists(":KitPreview"))
  end)

  it("opening the first toast creates the resize group, once", function()
    local toast = require("ui.kit.toast")
    local surf = toast.open({ message = "hi", timeout = 0 })
    assert.is_true(has_group("lib_kit_toast_resize"))
    local n = #vim.api.nvim_get_autocmds({ group = "lib_kit_toast_resize" })
    toast.open({ message = "again", timeout = 0 })
    assert.equals(n, #vim.api.nvim_get_autocmds({ group = "lib_kit_toast_resize" }))
    toast.clear()
    if surf and surf.close then
      pcall(surf.close, surf)
    end
  end)
end)
