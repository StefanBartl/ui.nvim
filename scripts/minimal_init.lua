-- scripts/minimal_init.lua — headless test bootstrap for ui.nvim.
--
-- Run from the repo root:
--   nvim --clean --headless -u scripts/minimal_init.lua \
--     -c "PlenaryBustedDirectory TESTS/ { minimal_init = 'scripts/minimal_init.lua', sequential = true }"
--
-- (scripts/test.sh wraps exactly that.) `-u` (not `-c luafile` after startup)
-- matters: 'runtimepath' additions must land before Neovim's own plugin/
-- directory scan, which is what registers plenary's :PlenaryBusted* commands
-- in the first place -- appending rtp afterwards leaves those commands
-- undefined. `--clean` matters too: without it, 'runtimepath' still defaults
-- to stdpath('config')/stdpath('data') -- a real user's own Neovim config,
-- plugins and all -- which is not what a CI run (or anyone else's machine)
-- should be exercising.
vim.opt.rtp:append(vim.fn.getcwd())

--- lib.nvim is a hard runtime dependency (lazy, memo, notify, bindings.*,
--- debounce, fs.*), not an optional one -- nearly every module here
--- `require("lib.*")` at load time, so the specs cannot run without it on the
--- rtp. plenary.nvim is the busted-compatible harness the specs under TESTS/
--- are written against (describe/it/before_each, busted assertions).
---
--- Four ways each can be found, in descending order of explicitness: an
--- explicit env var (`LIB_NVIM_DIR`/`PLENARY_DIR`), a `.deps/<name>` checkout
--- (what CI uses -- see .github/workflows/ci.yml), a sibling checkout next to
--- this repo (`../lib.nvim`, `../plenary.nvim`), or the plugin manager's own
--- directory (`stdpath('data')/lazy/<name>`) -- which is where both already
--- are on any machine that runs this plugin, so `scripts/test.sh` works there
--- with no environment set at all.
---@param env_var string
---@param deps_name string
---@param marker string module `require()`d to confirm the directory is right
local function add_dep(env_var, deps_name, marker)
  if pcall(require, marker) then
    return
  end
  local candidates = {}
  local env_val = vim.env[env_var]
  if env_val and env_val ~= "" then
    candidates[#candidates + 1] = env_val
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/.deps/" .. deps_name
  candidates[#candidates + 1] = vim.fs.dirname(vim.fn.getcwd()) .. "/" .. deps_name
  candidates[#candidates + 1] = vim.fn.stdpath("data") .. "/lazy/" .. deps_name
  for _, dir in ipairs(candidates) do
    if dir and vim.fn.isdirectory(dir) == 1 then
      vim.opt.rtp:append(dir)
      if pcall(require, marker) then
        return
      end
    end
  end
  io.stderr:write(("scripts/minimal_init.lua: %s not found.\n"):format(deps_name))
  io.stderr:write(
    ("  Set %s, or clone it to .deps/%s, or place it beside this repo.\n"):format(
      env_var,
      deps_name
    )
  )
  os.exit(1)
end

add_dep("LIB_NVIM_DIR", "lib.nvim", "lib.nvim.fs.read")
add_dep("PLENARY_DIR", "plenary.nvim", "plenary")
