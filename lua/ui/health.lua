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
--- What this section says next, historically: at step 4's own time, nothing
--- called `ui.statusline.render.enable()` outside this plugin's own tests
--- yet -- the reference host still wired `chadrc.lua` to NvChad's own render
--- pipeline. Step 7 (2026-09-13) closed that gap in that host; NvChad is not
--- installed there any more at all. This section still reports NvChad's
--- presence as information (see below) because that is a fact about
--- whatever host is running this plugin right now, not a claim about this
--- plugin's own reference host specifically. Step 5 replaced `nvchad.tabufline` the same way (own
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
    "lib.nvim.ui.kit.select",
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
    health.info(
      "NvChad is present -- this plugin's own code does not need it, but the host may still be "
        .. "using NvChad's own tabline/dashboard/LSP-signature/colorify (see its own docs for which)"
    )
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
        .. "(NvChad's own renderer, if the host still routes through one, or something else "
        .. "entirely -- this plugin has no way to know from here)"
    )
  end
end

--- This plugin's own tabline render entrypoint: does it resolve, and does
--- calling it produce a string without NvChad on the runtimepath. Mirrors
--- `check_render_entrypoint()` above, one option later.
---@return nil
local function check_tabline_entrypoint()
  health.start("Tabline render entrypoint")

  local ok_render, render = pcall(require, "ui.tabline.render")
  if not ok_render or type(render) ~= "table" then
    health.error("ui.tabline.render did not load: " .. tostring(render))
    return
  end
  if type(render.generate) ~= "function" or type(render.enable) ~= "function" then
    health.error("ui.tabline.render is missing generate()/enable()")
    return
  end
  health.ok("ui.tabline.render resolves (generate/enable/render/disable)")

  local ok_gen, rendered = pcall(render.generate, require("ui.config.tabline"))
  if ok_gen and type(rendered) == "string" then
    health.ok("generate() renders the shipped tabline config without NvChad")
  else
    health.error("generate() failed against the shipped tabline config: " .. tostring(rendered))
  end

  if render.current() ~= nil then
    health.info("a config is currently enable()d -- vim.o.tabline is owned by this plugin")
  else
    health.info("enable() has not been called -- vim.o.tabline is whatever the host last set")
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
  health.info(("statusline variant (boot default): %s"):format(tostring(variant)))

  -- A typo degrades to "default" with a notification nobody sees twice.
  -- Checked against the registry, not a direct require: a host-registered
  -- variant has no `ui.config.statusline.*` file to find at all.
  local ok_variants, variants = pcall(require, "ui.config.variants")
  if ok_variants and variants.exists(variant) then
    health.ok(("variant %q is registered and resolves"):format(tostring(variant)))
  else
    health.error(
      ("variant %q is not registered -- it will fall back to 'default'"):format(tostring(variant))
    )
  end

  -- Save/restore around this probe call: M.setup() here is only to prove it
  -- doesn't error, but it is the same M.setup() a real caller uses, and it
  -- records what it assembled as "the active configuration" -- calling it
  -- with no variant would otherwise silently reset an actually-active
  -- runtime switch (`:UI variant personal`) back to the boot default the
  -- moment someone runs `:checkhealth ui`.
  local saved_state = cfg_mod.__save_state()
  local ok_setup, assembled = pcall(cfg_mod.setup)
  cfg_mod.__restore_state(saved_state)

  if ok_setup and type(assembled) == "table" then
    health.ok("ui.config.setup() assembles")
  else
    health.error("ui.config.setup() failed: " .. tostring(assembled))
  end

  local active = cfg_mod.get_variant()
  if active then
    health.info(("active variant (currently live, unaffected by this check): %s"):format(active))
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
    -- info, not warn: same lazy-loading normal-state as the usrcmds entry
    -- right above (:UI is what its setup() registers) -- nothing has gone
    -- wrong here, setup() just has not run with usrcmds/all enabled yet.
    -- The advice is folded into the message, not a second argument:
    -- vim.health.info() (unlike .warn()/.error()) takes one param only and
    -- silently drops anything past it.
    health.info(":UI is not registered (call require('ui').setup({ all = true }))")
  end

  -- Not the `package.loaded` shape the two entries above use: `menu` is not
  -- an opt-in `ui.setup()` turns on, it is an opt-OUT that is already on by
  -- default (see `ui.contextmenu`'s own doc comment) -- `require()`ing it
  -- here has no side effect beyond defining its functions (no autocmd/
  -- highlight registration at load time), and `is_enabled()`'s own doc
  -- comment says explicitly "For :checkhealth and tests".
  local ok_menu, enabled = pcall(function()
    return require("ui.contextmenu").is_enabled()
  end)
  if not ok_menu then
    health.warn("ui.contextmenu failed to load: " .. tostring(enabled))
  elseif enabled then
    health.ok("menu -- right-click context menu (ui.contextmenu)")
  else
    health.info("menu is off (ui.setup({ menu = false }) was called)")
  end
end

--- The statusline segments that depend on something outside this plugin.
---
--- Named by the exact module path each segment's own `pcall(require, ...)`
--- checks (see `ui.statusline.modules.*`), not just the plugin's repo name --
--- kept in sync with `ui.statusline.catalog`'s `requires` field by hand,
--- since the catalog itself doesn't carry the require path, only the
--- human-readable plugin name.
---@return nil
local function check_segments()
  health.start("Statusline segments")

  for _, entry in ipairs({
    { "nvim-web-devicons", "file type icons; without it the icon column is blank" },
    { "filetree", "cwd-mode badge (filetree_cwd_mode)" },
    { "github_stats.config", "weekly view-count badge (github_stats_badge)" },
    {
      "runtime-analysis.telemetry",
      "health ampel across instrumented plugins (runtime_analysis_ampel)",
    },
    { "recommender.config", "alias-suggestion count badge (recommender_badge)" },
    { "sessions.statusline", "active session name + dirty marker (session_status)" },
    { "sandbox.statusline", "ambient container summary (sandbox_ambient)" },
  }) do
    if has(entry[1]) then
      health.ok(("%s -- %s"):format(entry[1], entry[2]))
    else
      health.info(("%s not installed -- %s"):format(entry[1], entry[2]))
    end
  end

  health.info("These are soft: a missing one blanks its segment, nothing else.")
end

--- Frame ownership: this module resolving is what lets a content plugin
--- (my.nvim's hl_config.breadcrumbs, or any other) contribute a winbar line
--- instead of writing vim.wo.winbar itself. See ui.winbar's own doc comment
--- for the full ownership pattern -- it mirrors lsp.nvim/my.nvim's existing
--- vim.diagnostic.config() contribute/apply split.
---@return nil
local function check_winbar()
  health.start("Winbar")

  local ok, winbar = pcall(require, "ui.winbar")
  if not ok or type(winbar.set) ~= "function" then
    health.error(
      "ui.winbar did not load -- a contributing plugin will fall back to applying directly"
    )
    return
  end
  health.ok("ui.winbar resolves -- available for a content plugin to contribute to")
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
  check_tabline_entrypoint()
  check_modules()
  check_segments()
  check_winbar()
end

return M
