--- Guards the text files of the repository against double-encoded UTF-8.
---
--- A file that is read as Latin-1 or Windows-1252 and written back as UTF-8
--- turns every non-ASCII character into two or three others, and nothing
--- complains: Lua accepts any bytes in a string, stylua does not touch them, and
--- a reviewer reading the diff sees a plausible-looking glyph or two. This is
--- what happened to the open-box glyph (U+2423) that `screenkey_spec.lua` and
--- `docs/health.md` use as the example label for `<Space>`: the spec still
--- passed, because it only needed some multi-byte string, and the documented
--- example handed a user who copied it garbage as the label. Nothing checked it;
--- it was found by scanning the sibling repositories for the byte pattern. The
--- tools that cause it are the ones a Windows session reaches for: PowerShell's
--- default output encoding, a script that opens a file without saying which one.
---
--- The signature is a lead byte of a Latin letter (0xC3) followed by a second
--- character in the C1 / Latin-1 range, which UTF-8 text does not contain: the
--- second byte of that pair is what a real accented letter never has after it.
--- The patterns are written as decimal escapes so this file does not match
--- itself, and no comment here quotes the damage.

local uv = vim.uv or vim.loop

--- Directories and files that carry text worth guarding, from the repo root.
---@type string[]
local ROOTS = { "lua", "TESTS", "docs", "doc", "scripts", "README.md" }

---@type table<string, true>
local EXTENSIONS = { lua = true, md = true, txt = true, yml = true, yaml = true, json = true }

---@class SourceEncoding.Signature
---@field pattern string
---@field what string

---@type SourceEncoding.Signature[]
local SIGNATURES = {
  {
    -- Two-byte characters (accented letters, most punctuation) read as Latin-1.
    pattern = "\195[\130\131]\194[\128-\191]",
    what = "a capital A with tilde or circumflex, then a C1 or Latin-1 character",
  },
  {
    -- Three- and four-byte characters (the typographic quotes and arrows, the
    -- control pictures, emoji) read as Latin-1: the lead byte becomes a lowercase
    -- a with circumflex or an eth, and the rest keeps its value as U+0080..U+00BF.
    pattern = "\195[\162\176]\194[\128-\191]",
    what = "a lowercase a with circumflex or eth, then a C1 or Latin-1 character",
  },
  {
    -- The same three-byte characters read as Windows-1252, where 0x80 is the
    -- euro sign: an a with circumflex followed by the euro sign.
    pattern = "\195\162\226\130\172",
    what = "an a with circumflex followed by the euro sign (Windows-1252 reading)",
  },
}

--- The working directory, which is the repository root: `scripts/minimal_init.lua`
--- puts it on the runtimepath and every other spec relies on that too.
---@return string
local function repo_root()
  return vim.fs.normalize(vim.fn.getcwd())
end

---@param path string
---@param out string[]
---@return nil
local function collect(path, out)
  local stat = uv.fs_stat(path)
  if not stat then
    return
  end
  if stat.type == "file" then
    if EXTENSIONS[path:match("%.([%w]+)$") or ""] then
      out[#out + 1] = path
    end
    return
  end
  if stat.type ~= "directory" then
    return
  end
  for name, kind in vim.fs.dir(path) do
    if kind == "directory" or kind == "file" then
      collect(path .. "/" .. name, out)
    end
  end
end

---@param path string
---@return string|nil
local function read(path)
  local handle = io.open(path, "rb")
  if not handle then
    return nil
  end
  local content = handle:read("*a")
  handle:close()
  return content
end

describe("the repository's text files", function()
  it("hold no double-encoded UTF-8", function()
    local root = repo_root()

    ---@type string[]
    local files = {}
    for _, name in ipairs(ROOTS) do
      collect(root .. "/" .. name, files)
    end
    -- A run from somewhere else, or a layout change, must not turn this into a
    -- guard over nothing.
    assert.is_true(#files > 50, ("only %d files found under %s"):format(#files, root))

    ---@type string[]
    local hits = {}
    for _, path in ipairs(files) do
      local content = read(path)
      if content then
        local number = 0
        for line in (content .. "\n"):gmatch("(.-)\n") do
          number = number + 1
          for _, signature in ipairs(SIGNATURES) do
            if line:find(signature.pattern) then
              hits[#hits + 1] = ("%s:%d: %s"):format(path:sub(#root + 2), number, signature.what)
              break
            end
          end
        end
      end
    end

    assert.are.same({}, hits)
  end)

  -- The patterns are only worth anything if they match the damage they are
  -- written for. Built from bytes, so this file stays clean.
  it("recognises the damage the patterns are written for", function()
    -- U+2423 (the open box) is E2 90 A3; read as Latin-1 and written back as
    -- UTF-8 it becomes C3 A2, C2 90, C2 A3.
    local latin1 = "\195\162\194\144\194\163"
    -- U+203A (the single right angle quote) is E2 80 BA; read as Windows-1252,
    -- where 0x80 is the euro sign: C3 A2, E2 82 AC, C2 BA.
    local cp1252 = "\195\162\226\130\172\194\186"
    -- U+00E4 (a with diaeresis) is C3 A4; read as Latin-1: C3 83, C2 A4.
    local accented = "\195\131\194\164"
    -- And the real characters are left alone: the open box itself, an a with
    -- diaeresis, a lone a with circumflex.
    local clean = "\226\144\163 \195\164 \195\162"

    for _, damaged in ipairs({ latin1, cp1252, accented }) do
      local matched = false
      for _, signature in ipairs(SIGNATURES) do
        matched = matched or damaged:find(signature.pattern) ~= nil
      end
      assert.is_true(matched, vim.inspect(damaged) .. " was not recognised")
    end
    for _, signature in ipairs(SIGNATURES) do
      assert.is_nil(clean:find(signature.pattern), "flagged clean text: " .. signature.what)
    end
  end)
end)
