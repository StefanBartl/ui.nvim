-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- The kit exists twice, on purpose — and this spec is what makes that
--- safe.
---
--- `PLAN-ui-kit-migration.md` step 6 decided it: the kit moved here in
--- 2026-09, and lib.nvim's copy was **deliberately** left in its tree
--- rather than deleted, because eleven of lib.nvim's own call sites use it
--- and lib.nvim cannot depend on ui.nvim without inverting the whole
--- fleet's dependency direction. "Frozen: no new features" was the deal.
---
--- What that deal never said was "keeps known bugs", and by 2026-09-17 it
--- had drifted into exactly that: three fixes and a security note lived
--- only here, while lib.nvim's live copy — the one its own eleven call
--- sites run — still had the augroup leak, the stray picker timer and the
--- submenu anchor bug (cross-feature report, finding A1).
---
--- Nobody noticed for weeks because nothing compared them. This does.
---
--- **Formatting is deliberately ignored.** Undoing the rename changes line
--- widths: `ui.kit.sync` becomes `lib.nvim.ui.kit.sync`, nine characters
--- longer, which pushes one `error(...)` call past the shared 100-column
--- budget so stylua wraps it on one side and not the other. Byte-identity
--- is therefore not achievable and not the point; what must not diverge is
--- the code.
---
--- Skips when lib.nvim is not checked out beside this repo. CI always has
--- it (`.deps/lib.nvim`, pinned to `ci-verified`), so this runs there.

local function lib_root()
  local candidates = {
    vim.env.LIB_NVIM_DIR,
    vim.fn.getcwd() .. "/.deps/lib.nvim",
    vim.fs.dirname(vim.fn.getcwd()) .. "/lib.nvim",
  }
  for _, dir in ipairs(candidates) do
    if dir and vim.fn.isdirectory(dir .. "/lua/lib/nvim/ui/kit") == 1 then
      return dir
    end
  end
  return nil
end

local function lib_kit_dir()
  local root = lib_root()
  return root and (root .. "/lua/lib/nvim/ui/kit") or nil
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

--- Strip whitespace entirely, so a rename-induced re-wrap is not counted
--- as a difference.
---
--- Collapsing runs to a single space is not enough: stylua's wrapped form
--- puts a space after `(` and before `)` where the one-line form has
--- none, so `error("...", 2)` and its four-line equivalent still differ.
--- Removing it all is coarse, and knowingly so -- two genuinely different
--- sources could in principle collapse to the same string. The failure
--- mode of that is a missed drift, never a false alarm, which is the right
--- way round for a guard that must not cry wolf.
---@param text string
---@return string
local function flatten(text)
  return (text:gsub("%s+", ""))
end

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

---@param path string
---@return string
local function read(path)
  return table.concat(vim.fn.readfile(path), "\n")
end

describe("ui.kit and lib.nvim's frozen copy", function()
  local lib_dir = lib_kit_dir()

  it("has lib.nvim available to compare against", function()
    if not lib_dir then
      -- Not a failure: a contributor without a lib.nvim checkout still
      -- gets a useful suite. CI pins one, so the assertions below run
      -- where it matters.
      print("  (skipped: no lib.nvim checkout found)")
    end
    assert.is_true(true)
  end)

  if not lib_dir then
    return
  end

  local ui_dir = vim.fn.getcwd() .. "/lua/ui/kit"

  --- Every .lua file under a kit directory, relative to it.
  ---@param root string
  ---@return string[]
  local function kit_files(root)
    local out = {}
    for _, p in ipairs(vim.fn.glob(root .. "/**/*.lua", false, true)) do
      out[#out + 1] = p:sub(#root + 2):gsub("\\", "/")
    end
    table.sort(out)
    return out
  end

  it("carries the same set of files on both sides", function()
    assert.same(kit_files(ui_dir), kit_files(lib_dir))
  end)

  it("has not drifted from lib.nvim's copy", function()
    local drifted = {}
    for _, rel in ipairs(kit_files(ui_dir)) do
      local mine = flatten(as_lib(read(ui_dir .. "/" .. rel)))
      local theirs = flatten(read(lib_dir .. "/" .. rel))
      if mine ~= theirs then
        drifted[#drifted + 1] = rel
      end
    end

    assert.same(
      {},
      drifted,
      "kit files differ from lib.nvim's copy: "
        .. table.concat(drifted, ", ")
        .. " -- a fix made here has to be ported there too, or lib.nvim's "
        .. "own call sites keep the bug. See this spec's header."
    )
  end)
end)

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
