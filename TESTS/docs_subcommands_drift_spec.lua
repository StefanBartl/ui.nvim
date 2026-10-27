---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- Every `:UI` subcommand (one composer route each) is documented: an entry with its
--- own tag in `doc/ui.txt` (one `:helptags` turns into a tags line),
--- and a row in the command table of `docs/BINDINGS.md`. The route list is the code's
--- own, so a new subcommand without docs turns this spec red instead of drifting
--- unnoticed (the docs had missed eight of them).

local composer = require("lib.nvim.bindings.usercmd.composer")

---@param rel string
---@return string
local function read(rel)
  local path = vim.fs.joinpath(vim.fn.getcwd(), rel)
  local fd = assert(io.open(path, "rb"), "cannot open " .. rel)
  local text = fd:read("*a")
  fd:close()
  return (text:gsub("\r", ""))
end

---@return string[]
local function subcommands()
  local names = {}
  for _, route in ipairs(composer.registry().UI:spec().routes) do
    if route.path[1] then
      names[#names + 1] = route.path[1]
    end
  end
  table.sort(names)
  return names
end

---@param text string
---@param needles string[]
---@return boolean
local function has_any(text, needles)
  for _, needle in ipairs(needles) do
    if text:find(needle, 1, true) then
      return true
    end
  end
  return false
end

describe("docs list every :UI subcommand", function()
  if type(composer.registry) ~= "function" then
    it("needs a lib.nvim with the composer registry", function()
      pending("lib.nvim has no composer.registry")
    end)
    return
  end

  pcall(function()
    require("ui.bindings.usrcmds").setup()
  end)

  local names = subcommands()

  it("reads a non-empty route list", function()
    assert.is_true(#names > 10, "routes: " .. table.concat(names, ", "))
  end)

  it("doc/ui.txt has a tagged entry for each", function()
    local doc = read("doc/ui.txt")
    local missing = {}
    for _, name in ipairs(names) do
      local tagged = doc:find("*:UI-" .. name .. "*", 1, true) ~= nil
      local entry = has_any(doc, { "\n:UI " .. name .. "\n", "\n:UI " .. name .. " " })
      if not (tagged and entry) then
        missing[#missing + 1] = name
      end
    end
    assert.are.equal("", table.concat(missing, ", "))
  end)

  -- doc/tags is gitignored (plugin managers write it), so the spec runs `:helptags`
  -- on a copy: a malformed or duplicate tag fails here, not in a user's install.
  it(":helptags builds each tag", function()
    -- `:helptags` globs the directory: under an 8.3 short temp path
    -- (`C:/Users/STEFAN~1/...`) the `~1` reads as a user and the glob finds
    -- nothing (E151). `globbable` spells it the long way (XP-01).
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    dir = require("lib.nvim.fs.globbable")(dir)
    local fd = assert(io.open(vim.fs.joinpath(dir, "ui.txt"), "wb"))
    fd:write(read("doc/ui.txt"))
    fd:close()
    vim.cmd.helptags(vim.fn.fnameescape(dir))
    local tfd = assert(io.open(vim.fs.joinpath(dir, "tags"), "rb"))
    local tags = "\n" .. tfd:read("*a"):gsub("\r", "")
    tfd:close()
    vim.fn.delete(dir, "rf")
    local missing = {}
    for _, name in ipairs(names) do
      if not tags:find("\n:UI-" .. name .. "\t", 1, true) then
        missing[#missing + 1] = name
      end
    end
    assert.are.equal("", table.concat(missing, ", "))
  end)

  it("docs/BINDINGS.md has a command row for each", function()
    local bindings = read("docs/BINDINGS.md")
    local missing = {}
    for _, name in ipairs(names) do
      local prefix = "`:UI " .. name
      if not has_any(bindings, { prefix .. "`", prefix .. " " }) then
        missing[#missing + 1] = name
      end
    end
    assert.are.equal("", table.concat(missing, ", "))
  end)
end)

--- The tabline style tables name the canonical styles (`rounded_chip` the default,
--- `chip`, `divider`), not the older alias names; each named style must be registered.
describe("docs name the canonical tabline styles", function()
  local styles = require("ui.tabline.styles")

  ---@type { file: string, rows: string[], stale: string[] }[]
  local cases = {
    {
      file = "docs/configuration.md",
      rows = { "| `rounded_chip` (default) |", "| `chip` |", "| `divider` |" },
      stale = { "| `rounded` (default)", "| `square` |", "falls back to `rounded` " },
    },
    {
      file = "doc/ui.txt",
      rows = { "\n    rounded_chip  (default)", "\n    chip ", "\n    divider " },
      stale = { "\n    rounded   (default)", "\n    square ", "falls back to `rounded` " },
    },
  }

  for _, case in ipairs(cases) do
    it(case.file .. " lists rounded_chip/chip/divider", function()
      local text = read(case.file)
      local problems = {}
      for _, row in ipairs(case.rows) do
        if not text:find(row, 1, true) then
          problems[#problems + 1] = "missing " .. vim.trim(row)
        end
      end
      for _, row in ipairs(case.stale) do
        if text:find(row, 1, true) then
          problems[#problems + 1] = "stale " .. vim.trim(row)
        end
      end
      assert.are.equal("", table.concat(problems, "; "))
    end)
  end

  it("each documented name is registered", function()
    for _, name in ipairs({ "rounded_chip", "chip", "divider", "rounded", "square", "hacker" }) do
      assert.is_true(styles.exists(name), name)
    end
  end)
end)
