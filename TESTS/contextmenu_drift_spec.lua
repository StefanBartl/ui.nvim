-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.contextmenu` exists twice: lib.nvim keeps a frozen copy (`lib.nvim.contextmenu`) for its own call sites.
--- The kit used to be checked here too; it now lives only in lib.nvim (`ui.kit.*` re-exports it), so this spec is
--- what is left of the old drift guard.
---
--- Skips when lib.nvim is not checked out beside this repo. CI always has it (`.deps/lib.nvim`).

--- Built with `insert`, not as a literal with a possibly-nil first entry.
--- `{ vim.env.LIB_NVIM_DIR, a, b }` is `{ nil, a, b }` when that variable
--- is unset, and `ipairs` stops at the first nil -- so the loop saw no
--- candidates at all and this whole spec skipped. It skipped in CI for
--- exactly that reason while passing locally, where the variable is
--- always set: a guard that is inert precisely where it is needed.
---@return string|nil
local function lib_root()
  local candidates = {}
  if vim.env.LIB_NVIM_DIR and vim.env.LIB_NVIM_DIR ~= "" then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_DIR
  end
  candidates[#candidates + 1] = vim.fn.getcwd() .. "/.deps/lib.nvim"
  candidates[#candidates + 1] = vim.fs.dirname(vim.fn.getcwd()) .. "/lib.nvim"

  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir .. "/lua/lib/nvim/ui/kit") == 1 then
      return dir
    end
  end
  return nil
end

--- ui.nvim spelling -> lib.nvim spelling, applied in a single pass.
---
--- Sequential `gsub`s would re-scan their own output: rewriting `ui.kit`
--- to `lib.nvim.ui.kit` and then running the same rule again yields
--- `lib.nvim.lib.nvim.ui.kit`. One pass over the longest alternatives
--- first is the only correct shape, and getting it wrong is how the first
--- attempt at this comparison produced a false difference.
local SUBS = {
  { "lua/ui/kit/", "lua/lib/nvim/ui/kit/" },
  { "ui%.contextmenu", "lib.nvim.contextmenu" },
  { "Ui%.ContextMenu", "Lib.ContextMenu" },
  { "ui%.kit", "lib.nvim.ui.kit" },
  { "Ui%.Kit", "Lib.UI.Kit" },
}

--- Translate ui.nvim source into what lib.nvim's copy should say.
---
--- Applied to the ui side ONLY. Running it over the lib side as well is
--- the trap: that text already reads `lib.nvim.ui.kit`, which still
--- contains `ui.kit`, so the rule fires again and yields
--- `lib.nvim.lib.nvim.ui.kit`. The first version of this spec did exactly
--- that and reported all 21 files as drifted.
---@param text string
---@return string
local function as_lib(text)
  local out = text
  for _, pair in ipairs(SUBS) do
    out = out:gsub(pair[1], (pair[2]:gsub("%%", "%%%%")))
  end
  return out
end

---@param text string
---@return table<string, true>
local function line_set(text)
  local out = {}
  for line in text:gmatch("[^\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed ~= "" then
      out[trimmed] = true
    end
  end
  return out
end

---@param path string
---@return string
local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

--- `contextmenu` is duplicated the same way, but the right check for it is
--- weaker, and deliberately so.
---
--- It moved with the kit and lib.nvim's copy is frozen on the same terms.
--- Here, though, the divergence is entirely a *feature*: `set_enabled` /
--- `is_enabled`, the gate behind `ui.setup({ menu = false })`, exist only
--- in this copy. 36 added lines, zero changed ones -- which is exactly
--- what "no new features over there" is supposed to look like, so demanding
--- equality would fail on a decision rather than on a defect.
---
--- What must still hold is that lib.nvim's copy contains no line this one
--- has since corrected. So: every line over there must still be present
--- here. A fix rewrites a line, which makes the old one vanish from this
--- side and trips the check; an addition here only adds, and does not.
describe("ui.contextmenu and lib.nvim's frozen copy", function()
  local lib_dir = lib_root()
  if not lib_dir then
    return
  end

  local ui_dir = vim.fn.getcwd() .. "/lua/ui/contextmenu"
  local their_dir = lib_dir .. "/lua/lib/nvim/contextmenu"

  it("has kept every line lib.nvim's copy still relies on", function()
    local lost = {}

    for _, rel in ipairs({ "init.lua", "@types/init.lua" }) do
      local mine = line_set(as_lib(read(ui_dir .. "/" .. rel)))
      for line in pairs(line_set(read(their_dir .. "/" .. rel))) do
        if not mine[line] then
          lost[#lost + 1] = rel .. ": " .. line
        end
      end
    end

    assert.same(
      {},
      lost,
      "lib.nvim's contextmenu has lines this copy no longer has, which means "
        .. "a fix landed here only: "
        .. table.concat(lost, " | ")
    )
  end)
end)
