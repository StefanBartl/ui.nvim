---@module 'scripts.mirror_kit'
--- Mirror ui.nvim's kit into lib.nvim's frozen copy (`lua/lib/nvim/ui/kit/`).
---
---   LIB_NVIM_DIR=<lib.nvim> nvim --headless -n -u NONE -l scripts/mirror_kit.lua           # write what differs
---   LIB_NVIM_DIR=<lib.nvim> nvim --headless -n -u NONE -l scripts/mirror_kit.lua --check   # write nothing, exit 1 on drift
---   ... -l scripts/mirror_kit.lua --only buttons.lua form.lua   # only these files (paths relative to the kit dir)
---
--- `--only` is for the day the two copies differ in a file you did NOT touch: without it
--- this overwrites lib.nvim's version of that file with ui.nvim's, which is a loss when
--- lib.nvim is the one that is ahead there (a change landed in lib.nvim first).
---
--- Run from the ui.nvim root. `TESTS/kit_drift_spec.lua` requires the frozen copy
--- to carry the same code as `lua/ui/kit/`, modulo the rename and ignoring
--- whitespace, so every kit change has to be ported. This applies the same rename,
--- writes a file only where it differs by more than whitespace, and formats what
--- it wrote with lib.nvim's own stylua config.
---
--- `SUBS` is a copy of that spec's table. The spec stays the judge: if the two
--- ever disagree, the spec fails, so a stale copy here cannot pass silently.
---
--- After a run: review `git diff` in lib.nvim, commit and push it FIRST -- ui.nvim's
--- CI reads lib.nvim's `ci-verified` branch, which lib.nvim's own CI only advances
--- after a green run on all three systems; pushing ui.nvim before that leaves its
--- drift check red for a while.
---
--- Exit: 0 = in sync (or written), 1 = drift found by `--check`, 2 = no lib.nvim.

local uv = vim.uv or vim.loop
local check_only = vim.tbl_contains(arg or {}, "--check")

--- `--only a.lua b/c.lua`: every argument after the flag that is not itself a flag.
---@type table<string, true>|nil
local only
do
  local seen = false
  for _, a in ipairs(arg or {}) do
    if a == "--only" then
      seen = true
      only = only or {}
    elseif seen and a:sub(1, 2) ~= "--" then
      only[a] = true
    end
  end
end

---@param p string
---@return string
local function norm(p)
  return (p:gsub("\\", "/"):gsub("/+$", ""))
end

local ui_root = norm(uv.cwd())

--- `print` under `nvim -l` leaves the last line without its newline.
---@param line string
local function say(line)
  io.stdout:write(line, "\n")
end

--- Same candidates, same order as the drift spec: an explicit variable (what CI
--- and a worktree need, since the sibling lookup below resolves under
--- `.claude/worktrees/` there), a `.deps/` checkout, a sibling checkout.
---@return string|nil
local function find_lib()
  local candidates = {}
  if vim.env.LIB_NVIM_DIR and vim.env.LIB_NVIM_DIR ~= "" then
    candidates[#candidates + 1] = vim.env.LIB_NVIM_DIR
  end
  candidates[#candidates + 1] = ui_root .. "/.deps/lib.nvim"
  candidates[#candidates + 1] = vim.fs.dirname(ui_root) .. "/lib.nvim"
  for _, dir in ipairs(candidates) do
    if vim.fn.isdirectory(dir .. "/lua/lib/nvim/ui/kit") == 1 then
      return norm(dir)
    end
  end
  return nil
end

local lib_root = find_lib()
if not lib_root then
  io.stderr:write("mirror_kit: no lib.nvim checkout found (set LIB_NVIM_DIR)\n")
  os.exit(2)
end

--- ui.nvim spelling -> lib.nvim spelling. Applied to the ui side only, in this
--- order (the spec explains why never to run it over the lib side as well).
local SUBS = {
  { "lua/ui/kit/", "lua/lib/nvim/ui/kit/" },
  { "ui%.contextmenu", "lib.nvim.contextmenu" },
  { "Ui%.ContextMenu", "Lib.ContextMenu" },
  { "ui%.kit", "lib.nvim.ui.kit" },
  { "Ui%.Kit", "Lib.UI.Kit" },
}

---@param text string
---@return string
local function as_lib(text)
  local out = text
  for _, pair in ipairs(SUBS) do
    out = out:gsub(pair[1], (pair[2]:gsub("%%", "%%%%")))
  end
  return out
end

--- Whitespace does not count, the way the spec compares (a rename re-wraps lines).
---@param text string
---@return string
local function flatten(text)
  return (text:gsub("%s+", ""))
end

---@param path string
---@return string|nil
local function read(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  return table.concat(vim.fn.readfile(path), "\n")
end

local ui_kit = ui_root .. "/lua/ui/kit"
local lib_kit = lib_root .. "/lua/lib/nvim/ui/kit"

---@param dir string
---@return string[]
local function kit_files(dir)
  local out = {}
  for name, kind in vim.fs.dir(dir, { depth = 8 }) do
    if kind == "file" and name:match("%.lua$") then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local ui_files = kit_files(ui_kit)
local all_ui_files = ui_files -- the "only in lib.nvim" report below is about the whole kit, not the --only subset
if only then
  for name in pairs(only) do
    if not vim.tbl_contains(ui_files, name) then
      io.stderr:write(
        "mirror_kit: --only names a file that is not in " .. ui_kit .. ": " .. name .. "\n"
      )
      os.exit(2)
    end
  end
  ui_files = vim.tbl_filter(function(rel)
    return only[rel] == true
  end, ui_files)
end
if #ui_files == 0 then
  io.stderr:write("mirror_kit: no .lua files under " .. ui_kit .. " -- run from the ui.nvim root\n")
  os.exit(2)
end

local written, same = {}, 0
for _, rel in ipairs(ui_files) do
  local want = as_lib(read(ui_kit .. "/" .. rel) or "")
  local have = read(lib_kit .. "/" .. rel)
  if have ~= nil and flatten(have) == flatten(want) then
    same = same + 1
  else
    written[#written + 1] = rel
    if not check_only then
      local dest = lib_kit .. "/" .. rel
      vim.fn.mkdir(vim.fs.dirname(dest), "p")
      vim.fn.writefile(vim.split(want, "\n", { plain = true }), dest)
    end
  end
end

-- Files only lib.nvim has are reported, never deleted: a rename or removal is a
-- decision for a person.
local ui_set = {}
for _, rel in ipairs(all_ui_files) do
  ui_set[rel] = true
end
local only_lib = vim.tbl_filter(function(rel)
  return not ui_set[rel]
end, kit_files(lib_kit))

say(
  ("%s: %d file(s) %s, %d already in sync"):format(
    check_only and "drift" or "mirrored",
    #written,
    check_only and "differ" or "written",
    same
  )
)
for _, rel in ipairs(written) do
  say("  " .. rel)
end
for _, rel in ipairs(only_lib) do
  say("  only in lib.nvim (left alone): " .. rel)
end

if check_only then
  os.exit(#written > 0 and 1 or 0)
end

if #written > 0 then
  -- lib.nvim's own stylua.toml applies from its root. The rename changes line
  -- widths, so a written file usually wants a re-wrap.
  local paths = vim.tbl_map(function(rel)
    return "lua/lib/nvim/ui/kit/" .. rel
  end, written)
  local ok, res = pcall(function()
    return vim.system(vim.list_extend({ "stylua" }, paths), { cwd = lib_root }):wait()
  end)
  if not (ok and res.code == 0) then
    say("stylua did not run cleanly -- format the written files in lib.nvim yourself")
  end
  say("next: review `git diff` in " .. lib_root .. ", commit and push it before ui.nvim")
end
