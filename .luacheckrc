std = "luajit"
cache = true

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
