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
    -- A contributor without a lib.nvim checkout still gets a useful
    -- suite, so this is not a hard failure -- but CI must never be the
    -- one skipping, which is what happened when `lib_root` returned nil
    -- there and nothing said so loudly enough to notice.
    if not lib_dir then
      print("  (SKIPPED: no lib.nvim checkout -- the drift checks did NOT run)")
    end
    if vim.env.CI then
      assert.is_not_nil(
        lib_dir,
        "CI must have lib.nvim at .deps/lib.nvim; the guard cannot skip here"
      )
    end
    assert.is_true(true)
  end)

  if not lib_dir then
    return
  end

  local ui_dir = vim.fn.getcwd() .. "/lua/ui/kit"

  --- Every .lua file under a kit directory, relative to it.
  ---
  --- `vim.fn.glob` reads its argument as a pattern, not a path -- `root`
  --- goes through `lib.nvim.fs.globbable` first so an 8.3 short name in an
  --- env-var-supplied path (`$LIB_NVIM_DIR` on Windows, e.g.
  --- `C:/Users/STEFAN~1/...`) cannot make glob try to resolve `~1` as a
  --- home directory and come back an empty list with no error (XP-01).
  ---
  --- The resolved (`globbable`d) root, not the original `root`, is what
  --- prefixes every path glob hands back -- when `root` actually contained
  --- a `~`, that resolution changes its length (the 8.3 segment expands to
  --- its long form), so stripping with `#root` instead of `#groot` sliced
  --- the wrong number of characters off `p` and corrupted the very paths
  --- this fix exists to recover, in exactly the case it targets.
  ---@param root string
  ---@return string[]
  local function kit_files(root)
    local globbable = require("lib.nvim.fs.globbable")
    local groot = globbable(root)
    local out = {}
    for _, p in ipairs(vim.fn.glob(groot .. "/**/*.lua", false, true)) do
      out[#out + 1] = p:sub(#groot + 2):gsub("\\", "/")
    end
    table.sort(out)
    return out
  end

  it("carries the same set of files on both sides", function()
    local ui_files, lib_files = kit_files(ui_dir), kit_files(lib_dir)
    -- An empty result on either side means the glob itself came back empty
    -- (e.g. the 8.3 short-name trap XP-01 guards against), which must fail
    -- loudly here rather than let the next test compare two empty lists and
    -- report "no drift" while having checked nothing at all.
    assert.is_true(
      #ui_files > 0,
      "kit_files(ui_dir) found no .lua files -- glob likely came back empty"
    )
    assert.is_true(
      #lib_files > 0,
      "kit_files(lib_dir) found no .lua files -- glob likely came back empty"
    )
    assert.same(ui_files, lib_files)
  end)

  it("has not drifted from lib.nvim's copy", function()
    local files = kit_files(ui_dir)
    -- Same reasoning as the file-set test above: zero files here means this
    -- loop compares nothing and `drifted` stays `{}` regardless of any real
    -- divergence -- an empty glob must not read as "no drift found".
    assert.is_true(
      #files > 0,
      "kit_files(ui_dir) found no .lua files -- glob likely came back empty"
    )

    local drifted = {}
    for _, rel in ipairs(files) do
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
