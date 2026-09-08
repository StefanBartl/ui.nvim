---@module 'ui.health'
--- `:checkhealth ui`.
---
--- The first section is the one that matters most: **NvChad is a hard
--- dependency here.** This plugin paints the frame, and today it does so
--- through NvChad's base46 and statusline primitives. Installing it without
--- NvChad produces a plugin that loads and
--- renders nothing, which is exactly the failure a health check should name
--- rather than leave to guesswork.
---
--- Decoupling from those five symbols is the whole roadmap
--- (`docs/ROADMAP.md`); until it is done, this report says so out loud.

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

--- The hard dependencies: lib.nvim, and the five NvChad/base46 symbols.
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

  -- The NvChad and base46 symbols this plugin still reaches for. Reported one
  -- by one because they fail for different reasons and with different
  -- consequences: the first two are unguarded at their call sites and throw,
  -- the rest sit behind a `pcall` and only blank the feature they serve.
  --
  -- Fatal ones first, so the top of the section is the answer.
  local nvchad_ok = true
  for _, entry in ipairs({
    { "nvconfig", "NvChad's resolved UI configuration -- read unguarded, throws when absent" },
    { "nvchad.stl.utils", "statusline primitives (separators, mode table)" },
  }) do
    if has(entry[1]) then
      health.ok(("%s -- %s"):format(entry[1], entry[2]))
    else
      nvchad_ok = false
      health.error(("%s is missing -- %s"):format(entry[1], entry[2]), {
        "NvChad is a HARD dependency of this plugin, not an optional one",
        "Install NvChad/NvChad (branch v2.5), or do not install ui.nvim",
        "Removing this coupling is the plugin's roadmap, not its current state",
      })
    end
  end

  -- Guarded at every call site: absent means a blank tabline keymap or no
  -- theme switching, not a traceback. Reported as a warning so the difference
  -- from the two above stays visible.
  for _, entry in ipairs({
    { "nvchad.tabufline", "buffer/tab movement for the tabline keymaps" },
    { "base46", "theme loading and the transparency toggle" },
    { "base46.themes", "the theme list `:UI theme` completes over" },
  }) do
    if has(entry[1]) then
      health.ok(("%s -- %s"):format(entry[1], entry[2]))
    else
      health.warn(("%s is missing -- %s"):format(entry[1], entry[2]), {
        "Guarded at its call sites: this degrades the feature, it does not throw",
      })
    end
  end

  return nvchad_ok
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
    ("theme %q, transparency %s, toggle pair %s"):format(
      tostring(defaults.base46.theme),
      tostring(defaults.base46.transparency),
      table.concat(defaults.base46.theme_toggle or {}, " / ")
    )
  )

  local cfg_mod = require("ui.config")
  local variant = cfg_mod.STATUSLINE_VARIANT
  health.info(("statusline variant: %s"):format(tostring(variant)))

  -- The variant is a module path at heart, and a typo in it degrades to
  -- "normal" with a notification nobody sees twice.
  if has("ui.config.statusline." .. tostring(variant)) then
    health.ok(("variant module ui.config.statusline.%s resolves"):format(tostring(variant)))
  else
    health.error(
      ("variant %q does not resolve -- it will fall back to 'normal'"):format(tostring(variant))
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
  check_modules()
  check_segments()
end

return M
