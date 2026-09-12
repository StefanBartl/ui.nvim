---@module 'ui.health'
--- `:checkhealth ui`.
---
--- The first section used to say NvChad was a hard dependency of this
--- plugin. As of step 4 of the roadmap that is no longer
--- true of this plugin's own code: `ui.statusline.render` is now the
--- `vim.o.statusline` / `order`-`modules` walk that used to be entirely
--- `nvchad.init` + `nvchad.stl.utils.generate()`, and `ui.config.setup()`'s
--- return value assembles without touching a NvChad symbol (step 3). This
--- section checks that entrypoint resolves and runs, standalone.
---
--- What is still true, and what this section says next: nothing calls
--- `ui.statusline.render.enable()` outside this plugin's own tests yet --
--- the actual host still wires `chadrc.lua` to NvChad's own render pipeline,
--- and rewiring it is step 7, not this one. A user running this plugin
--- through that unmodified host is still, in practice, running NvChad's
--- renderer. Step 5 replaced `nvchad.tabufline` the same way (own
--- `vim.t.bufs` bookkeeping, own `close_buffer`/`move_buf`) -- it is gone
--- from this report's dependency list entirely, not merely soft, the same
--- as `nvconfig`/`nvchad.stl.utils` at step 4. `base46` is gone the same way
--- as of step 6: `ui.theme.palette` derives accent colors from the active
--- colorscheme's own highlight groups, `ui.theme.transparency` is this
--- plugin's own toggle, and theme switching is `:colorscheme`.

local M = {}

--- `vim.health`, resolved per call rather than captured at load time.
---
--- `local health = vim.health` reads once, when this module is first
--- required — and after that a test cannot stand in for it, because the
--- upvalue already points at the real table. The report is the part of this
--- plugin most worth asserting on (it is what says "NvChad is missing and
--- that is fatal"), so it should not be the part that cannot be observed.
---
--- The cost is one `__index` lookup per health call, in a function that runs
--- when a human types `:checkhealth`.
local health = setmetatable({}, {
  __index = function(_, key)
    return vim.health[key]
  end,
})

--- Whether a module resolves.
---@param mod string
---@return boolean
local function has(mod)
  return (pcall(require, mod))
end

--- The hard dependency: lib.nvim. NvChad is not one any more, and neither is
--- base46 as of step 6 -- `nvchad.tabufline` was the same story at step 5:
--- this plugin's own code no longer reads any of them under any name.
---@return boolean ok # false stops the rest of the report
local function check_dependencies()
  health.start("Dependencies")

  if not has("lib.nvim") then
    health.error("lib.nvim is not on the runtimepath", {
      "Install StefanBartl/lib.nvim",
      "In lazy.nvim: dependencies = { 'StefanBartl/lib.nvim' }",
    })
    return false
  end
  health.ok("lib.nvim is available")

  -- Named individually: a partial lib.nvim fails on exactly one of these, and
  -- the point of the report is to say which.
  local lib_modules = {
    "lib.lua.lazy",
    "lib.lua.memo.lru",
    "lib.lua.strings",
    "lib.nvim.bindings.autocmd",
    "lib.nvim.bindings.keymap",
    "lib.nvim.bindings.usercmd",
    "lib.nvim.buf_win_tab.move_buffer_to_tab",
    "lib.nvim.debounce.buffer",
    "lib.nvim.notify",
    "lib.nvim.ui.hl",
  }
  local missing = {}
  for _, mod in ipairs(lib_modules) do
    if not has(mod) then
      missing[#missing + 1] = mod
    end
  end
  if #missing > 0 then
    health.error(
      ("%d lib.nvim module(s) missing: %s"):format(#missing, table.concat(missing, ", ")),
      { "Update lib.nvim -- these paths have moved between releases" }
    )
    return false
  end
  health.ok(("all %d required lib.nvim modules resolve"):format(#lib_modules))

  -- `nvconfig`/`nvchad.stl.utils` are gone from this list entirely as of
  -- step 4: `ui.statusline.render` replaces both, and this plugin's own code
  -- no longer reads either symbol under any variant. Whether NvChad is
  -- present or not is reported below, but as information, not as a
  -- dependency check.
  if has("nvchad.init") then
    health.info("NvChad is present -- the host's chadrc.lua still routes rendering through it")
  else
    health.info("NvChad is not present -- this plugin's own code does not need it any more")
  end

  -- `nvchad.tabufline` dropped from this list at step 5, `base46` at step 6:
  -- buffer/tab movement, theme switching and transparency are this plugin's
  -- own code now (`ui.bindings.keymaps.tabufline.state`,
  -- `ui.bindings.usrcmds.themes`, `ui.theme.*`), not NvChad/base46 symbols to
  -- check for.

  return true
end

--- This plugin's own render entrypoint: does it resolve, and does calling it
--- produce a string without NvChad on the runtimepath.
---@return nil
local function check_render_entrypoint()
  health.start("Statusline render entrypoint")

  local ok_render, render = pcall(require, "ui.statusline.render")
  if not ok_render or type(render) ~= "table" then
    health.error("ui.statusline.render did not load: " .. tostring(render))
    return
  end
  if type(render.generate) ~= "function" or type(render.enable) ~= "function" then
    health.error("ui.statusline.render is missing generate()/enable()")
    return
  end
  health.ok("ui.statusline.render resolves (generate/enable/render/disable)")

  -- The "default" fallback theme, standing in for whichever variant's own
  -- `modules` does not cover a key -- exercised with a minimal synthetic
  -- config so this does not depend on the host's actual assembled variant.
  local ok_gen, rendered = pcall(render.generate, {
    order = { "mode", "%=", "cwd" },
    modules = {},
    theme = "default",
  })
  if ok_gen and type(rendered) == "string" then
    health.ok("generate() renders the 'default' theme's fallback modules without NvChad")
  else
    health.error("generate() failed against the 'default' theme: " .. tostring(rendered))
  end

  if render.current() ~= nil then
    health.info("a config is currently enable()d -- vim.o.statusline is owned by this plugin")
  else
    health.info(
      "enable() has not been called -- vim.o.statusline is whatever the host last set "
        .. "(NvChad, through chadrc.lua, until roadmap step 7 rewires the host)"
    )
  end
end

--- The configuration: does it assemble, and into what.
---@return nil
local function check_config()
  health.start("Configuration")

  local ok_def, defaults = pcall(require, "ui.config.DEFAULTS")
  if not ok_def or type(defaults) ~= "table" then
    health.error("ui.config.DEFAULTS did not load")
    return
  end
  health.ok(
    ("active colorscheme %q, transparency default %s, toggle pair %s"):format(
      tostring(vim.g.colors_name),
      tostring(defaults.theme.transparency),
      table.concat(defaults.theme.theme_toggle or {}, " / ")
    )
  )

  local cfg_mod = require("ui.config")
  local variant = cfg_mod.STATUSLINE_VARIANT
  health.info(("statusline variant: %s"):format(tostring(variant)))

  -- The variant is a module path at heart, and a typo in it degrades to
  -- "default" with a notification nobody sees twice.
  if has("ui.config.statusline." .. tostring(variant)) then
    health.ok(("variant module ui.config.statusline.%s resolves"):format(tostring(variant)))
  else
    health.error(
      ("variant %q does not resolve -- it will fall back to 'default'"):format(tostring(variant))
    )
  end

  local ok_setup, assembled = pcall(cfg_mod.setup)
  if ok_setup and type(assembled) == "table" then
    health.ok("ui.config.setup() assembles")
  else
    health.error("ui.config.setup() failed: " .. tostring(assembled))
  end
end

--- Which submodules `setup()` turned on.
---@return nil
local function check_modules()
  health.start("Modules")

  for _, entry in ipairs({
    { "keymaps", "ui.bindings.keymaps", "buffer/tab navigation, tabline" },
    { "usrcmds", "ui.bindings.usrcmds", "the :UI command and theme management" },
  }) do
    -- package.loaded, not a require: a module left out of setup() should
    -- report as off, and requiring it here would load it.
    if package.loaded[entry[2]] then
      health.ok(("%s -- %s"):format(entry[1], entry[3]))
    else
      health.info(("%s is off (%s)"):format(entry[1], entry[3]))
    end
  end

  if vim.fn.exists(":UI") == 2 then
    health.ok(":UI is registered")
  else
    health.warn(":UI is not registered", { "Call require('ui').setup({ all = true })" })
  end
end

--- The statusline segments that depend on something outside this plugin.
---@return nil
local function check_segments()
  health.start("Statusline segments")

  for _, entry in ipairs({
    { "nvim-web-devicons", "file type icons; without it the icon column is blank" },
    { "neotest", "the test-runner segment" },
    { "casedesk.meta", "the working-directory mode badge" },
  }) do
    if has(entry[1]) then
      health.ok(("%s -- %s"):format(entry[1], entry[2]))
    else
      health.info(("%s not installed -- %s"):format(entry[1], entry[2]))
    end
  end

  health.info("These are soft: a missing one blanks its segment, nothing else.")
end

--- Entry point for `:checkhealth ui`.
---@return nil
function M.check()
  if not check_dependencies() then
    -- Everything below assembles a configuration out of the symbols that just
    -- came back missing; continuing would print a wall of secondary failures
    -- that says nothing the first one did not.
    return
  end
  check_config()
  check_render_entrypoint()
  check_modules()
  check_segments()
end

return M
