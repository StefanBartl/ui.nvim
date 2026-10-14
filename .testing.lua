-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "ui",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file (nothing leaks from one file into the next).
  isolated = "file",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, expand('<cword>') works), "l" = `nvim -l`.
  host = "c",
  -- "warn" = a case without assertions passes with a recorded warning; "error" = it fails.
  -- Switch to "error" once the empty cases are fixed.
  assertions = "warn",
  -- Limits per case in milliseconds (the old runner had none).
  timeouts = { case_ms = 30000 },
  -- Guards (docs/GUARDS.md of testing.nvim). The suite passes fs, scheduled_error, prompt and
  -- deprecation without a single finding, so they are hard errors; a regression fails the run.
  guards = {
    fs = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    -- Real processes are started on purpose (see guard_allow.spawn); anything else is an error.
    process_net = "error",
    -- Off on purpose: this is a UI plugin, so its specs create windows, buffers, highlight groups,
    -- autocmds and keymaps by design (setup() and every picker/menu/float), about 1800 findings
    -- across 49 files. `isolated = "file"` contains all of it per spec file; the guard has nothing
    -- left to tell between cases of one file.
    state = "off",
  },
  guard_allow = {
    -- `git init` / `rev-parse` / `for-each-ref` in a throwaway repo: the git_clickable spec checks the
    -- 'no commits yet' and 'git itself fails' messages against real git.
    -- `nvim --version` is the cheap long-lived terminal job of the tabline specs that open a terminal buffer.
    spawn = { "git", "nvim" },
  },
  -- gated: a failed conformance check makes `scripts/test.sh conformance` exit 1 (docs/CONFORMANCE.md of testing.nvim)
  conformance = {
    gate = true,
    waivers = {
      {
        check = "K15",
        rule = "LUA-93",
        file = "README.md",
        level = "warn",
        expires = "2027-04-14",
        reason = "false positive: the matched block is the packer.nvim example (use({...})), not a lazy.nvim spec; packer loads eagerly and the lazy.nvim spec above names lazy = false",
      },
      {
        check = "K15",
        rule = "NEW-08",
        file = "lua/ui/bindings",
        level = "warn",
        expires = "2027-04-14",
        reason = "the autocommands belong to their feature modules (context, zen, theme, statusline), none is a user-facing binding; an empty bindings/autocmds would be a stub",
      },
    },
  },
}
