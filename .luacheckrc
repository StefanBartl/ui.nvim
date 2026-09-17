std = "luajit"
cache = true

-- `luacheck .` is the documented command, here and in CI, and without this
-- it walks directories that are not this plugin's source. CI installs its
-- own luacheck through luarocks into `.luarocks/` in the workspace and
-- checks out lib.nvim and plenary under `.deps/`; locally, `.claude/`
-- holds sibling worktrees. All of it is other people's Lua, and scanning
-- it turned `luacheck .` into 259 warnings from luarocks' own sources --
-- enough noise to keep this job red without anyone reading why.
exclude_files = {
  ".luarocks/",
  ".deps/",
  ".claude/",
}

-- "vim" itself is mutable (plugins assign vim.g.* freely), so it must live in
-- `globals`, not `read_globals`.
globals = {
  "vim",
}

-- Long lines are handled by stylua's column_width; don't duplicate the check.
max_line_length = false

-- luacheck's built-in busted defaults match `**/spec/**`, `**/test/**` and
-- `**/tests/**` -- all lowercase. `TESTS/` matches none of them, so without
-- this declaration every `describe`/`it`/`assert.has_no.errors` becomes an
-- "accessing undefined variable" warning. Declaring it explicitly is better
-- than relying on the implicit match anyway: it says where the globals come
-- from.
files["TESTS/**/*.lua"] = {
  std = "luajit+busted",
}
