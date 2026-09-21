-- See TESTS/config_spec.lua for what these suppressions cover and why.
---@diagnostic disable: need-check-nil, undefined-field, discard-returns

--- `ui.context` against real grammars Neovim does not bundle: Go, Java, C#,
--- JavaScript, TypeScript, Kotlin and Bash. Every expectation here was read off
--- the real parser (2026-09-21) rather than assumed from nvim-treesitter's query
--- files, which is how the Allman-brace bug was found: a `*_body` node starts at
--- its `{`, so with the brace on a line of its own the overlay pinned a row
--- saying nothing.
---
--- These run wherever the parser is installed (`:TSInstall go java c_sharp
--- javascript typescript kotlin bash`) and are skipped, not failed, where it is
--- not -- which is the ordinary case on CI. Rows are 0-based; each case lists
--- the rows pinned when the window's top line is `top`.

local context = require("ui.context")

---@param lang string
---@return boolean
local function has_real_parser(lang)
  return #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".*", false) > 0
    and pcall(vim.treesitter.language.add, lang)
end

---@param lang string
---@param lines string[]
---@return integer buf
local function scratch(lang, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = lang
  return buf
end

---@param buf integer
---@param top integer  0-based top row
---@return integer[] rows
local function context_rows(buf, top)
  return vim.tbl_map(function(e)
    return e.row
  end, context.contexts(buf, top))
end

---@class Ui.ContextLang.Case
---@field top integer
---@field rows integer[]
---@field why string

---@class Ui.ContextLang.Sample
---@field lang string
---@field lines string[]
---@field cases Ui.ContextLang.Case[]

---@type Ui.ContextLang.Sample[]
local SAMPLES = {
  {
    lang = "go",
    lines = {
      "package main", -- 0
      "",
      "type Server struct {", -- 2
      "\tname string",
      "}",
      "",
      "func (s *Server) Handle(n int) int {", -- 6
      "\ttotal := 0",
      "\tif n > 2 {", -- 8
      "\t\tfor i := 0; i < n; i++ {", -- 9
      "\t\t\tswitch i {", -- 10
      "\t\t\tcase 1:", -- 11
      "\t\t\t\ttotal += 1",
      "\t\t\t\ttotal += 2",
      "\t\t\tdefault:", -- 14
      "\t\t\t\ttotal -= 1",
      "\t\t\t\ttotal -= 2",
      "\t\t\t}",
      "\t\t}",
      "\t}",
      "\treturn total",
      "}",
      "",
      "func TestX(t *testing.T) {", -- 23
      '\tt.Run("case", func(t *testing.T) {', -- 24
      "\t\tx := 1",
      "\t\ty := 2",
      "\t\t_ = x + y",
      "\t})",
      "}",
    },
    cases = {
      { top = 3, rows = { 2 }, why = "the type declaration" },
      { top = 12, rows = { 6, 8, 9, 10, 11 }, why = "method, if, for, switch, case" },
      { top = 15, rows = { 6, 8, 9, 10, 14 }, why = "the default case, not case 1" },
      { top = 25, rows = { 23, 24 }, why = "function and the func literal in t.Run" },
    },
  },
  {
    lang = "java",
    lines = {
      "public class Demo {", -- 0
      "    public int run(int n) {", -- 1
      "        int total = 0;",
      "        if (n > 2) {", -- 3
      "            for (int x : items) {", -- 4
      "                switch (x) {", -- 5
      "                    case 1:", -- 6
      "                        total += 1;",
      "                        total += 2;",
      "                        break;",
      "                    default:", -- 10
      "                        total -= 1;",
      "                        total -= 2;",
      "                }",
      "            }",
      "        } else {",
      "            try {", -- 16
      "                total += helper(n);",
      "                total += 1;",
      "            } catch (Exception e) {", -- 19
      "                total = 0;",
      "                total = 1;",
      "            } finally {", -- 22
      "                total = 2;",
      "                total = 3;",
      "            }",
      "        }",
      "        return total;",
      "    }",
      "}",
    },
    cases = {
      { top = 4, rows = { 0, 1, 3 }, why = "class, method, if" },
      { top = 7, rows = { 0, 1, 3, 4, 5, 6 }, why = "class, method, if, for-each, switch, case" },
      { top = 20, rows = { 0, 1, 3, 16, 19 }, why = "try and its catch" },
      { top = 23, rows = { 0, 1, 3, 16, 22 }, why = "try and its finally" },
    },
  },
  {
    -- The grammar's own name; the `cs` filetype maps to it in a real config.
    lang = "c_sharp",
    lines = {
      "namespace Demo", -- 0
      "{",
      "    public class Service", -- 2
      "    {",
      "        public int Run(int n)", -- 4
      "        {",
      "            var total = 0;",
      "            if (n > 2)", -- 7
      "            {",
      "                foreach (var x in items)", -- 9
      "                {",
      "                    switch (x)", -- 11
      "                    {", -- 12: `switch_body`, its brace alone on the line
      "                        case 1:", -- 13
      "                            total += 1;",
      "                            total += 2;",
      "                            break;",
      "                        default:", -- 17
      "                            total -= 1;",
      "                            break;",
      "                    }",
      "                }",
      "            }",
      "            return total;",
      "        }",
      "    }",
      "}",
    },
    cases = {
      { top = 6, rows = { 0, 2, 4 }, why = "namespace, class, method" },
      {
        top = 14,
        rows = { 0, 2, 4, 7, 9, 11, 13 },
        why = "...and the switch and its case, not the lone `{` (row 12)",
      },
      { top = 19, rows = { 0, 2, 4, 7, 9, 11, 17 }, why = "the default section" },
    },
  },
  {
    lang = "javascript",
    lines = {
      'describe("thing", function () {', -- 0
      '  it("works", () => {', -- 1
      "    const a = 1;",
      "    if (a > 0) {", -- 3
      "      for (const x of items) {", -- 4
      "        switch (x) {", -- 5
      "          case 1:", -- 6
      "            run(x);",
      "            run(x + 1);",
      "            break;",
      "          default:", -- 10
      "            run(0);",
      "            run(1);",
      "        }",
      "      }",
      "    }",
      "    try {", -- 16
      "      run(1);",
      "      run(2);",
      "    } catch (e) {", -- 19
      "      run(3);",
      "      run(4);",
      "    }",
      "  });",
      "});",
    },
    cases = {
      { top = 2, rows = { 0, 1 }, why = "the describe callback and the it callback" },
      { top = 8, rows = { 0, 1, 3, 4, 5, 6 }, why = "callbacks, if, for-of, switch, case" },
      { top = 20, rows = { 0, 1, 16, 19 }, why = "try and its catch" },
    },
  },
  {
    lang = "typescript",
    lines = {
      "namespace Outer {", -- 0
      "  export interface Shape {", -- 1
      "    area(): number;",
      "    name: string;",
      "  }",
      "  export enum Kind {", -- 5
      "    A,",
      "    B,",
      "  }",
      "  export class Box implements Shape {", -- 9
      "    area(): number {", -- 10
      "      const total = 1;",
      "      return total;",
      "    }",
      '    name = "box";',
      "  }",
      "}",
    },
    cases = {
      { top = 3, rows = { 0, 1 }, why = "namespace and interface" },
      { top = 6, rows = { 0, 5 }, why = "namespace and enum" },
      { top = 12, rows = { 0, 9, 10 }, why = "namespace, class, method" },
    },
  },
  {
    lang = "kotlin",
    lines = {
      "class Demo {", -- 0
      "    fun run(n: Int): Int {", -- 1
      "        var total = 0",
      "        if (n > 2) {", -- 3
      "            for (x in items) {", -- 4
      "                when (x) {", -- 5
      "                    1 -> {", -- 6
      "                        total += 1",
      "                        total += 2",
      "                    }",
      "                    else -> total -= 1",
      "                }",
      "            }",
      "        }",
      "        while (total < 10) {", -- 14
      "            total++",
      "            total++",
      "        }",
      "        try {",
      "            total += helper(n)",
      "            total += 1",
      "        } catch (e: Exception) {", -- 21
      "            total = 0",
      "            total = 1",
      "        }",
      "        return total",
      "    }",
      "}",
    },
    cases = {
      {
        top = 7,
        rows = { 0, 1, 3, 4, 5, 6 },
        why = "class, fun, if, for, when, the `1 -> {` branch",
      },
      { top = 16, rows = { 0, 1, 14 }, why = "the while" },
      { top = 22, rows = { 0, 1, 21 }, why = "the catch block; Kotlin's `try` is not pinned" },
    },
  },
  {
    lang = "bash",
    lines = {
      "run() {", -- 0
      '  local n="$1"',
      '  if [ "$n" -gt 2 ]; then', -- 2
      "    for i in 1 2 3; do", -- 3
      '      case "$i" in', -- 4
      "        1)", -- 5
      "          echo one",
      "          echo uno",
      "          ;;",
      "        *)", -- 9
      "          echo other",
      "          echo otro",
      "          ;;",
      "      esac",
      "    done",
      '  elif [ "$n" -eq 1 ]; then', -- 15
      "    while true; do", -- 16
      "      echo loop",
      "      echo loop2",
      "    done",
      "  fi",
      "}",
    },
    cases = {
      { top = 7, rows = { 0, 2, 3, 4, 5 }, why = "function, if, for, case, its first item" },
      { top = 11, rows = { 0, 2, 3, 4, 9 }, why = "the second case item" },
      { top = 17, rows = { 0, 2, 15, 16 }, why = "the elif and the while under it" },
    },
  },
}

describe("ui.context on real grammars", function()
  for _, sample in ipairs(SAMPLES) do
    it(sample.lang .. ": pins what the real parser says is a scope", function()
      if not has_real_parser(sample.lang) then
        pending("no " .. sample.lang .. " parser installed")
        return
      end
      local buf = scratch(sample.lang, sample.lines)
      for _, case in ipairs(sample.cases) do
        assert.same(
          case.rows,
          context_rows(buf, case.top),
          ("%s, top row %d: %s"):format(sample.lang, case.top, case.why)
        )
      end
    end)
  end
end)
