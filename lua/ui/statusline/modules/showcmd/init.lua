---@module 'ui.statusline.modules.showcmd'
--- The pending key sequence (`'showcmd'`, e.g. `2d` or `"a`) as a statusline
--- segment instead of in the last line of the screen. Neovim already draws
--- it into a statusline on its own once `'showcmdloc'` is `"statusline"`,
--- through the `%S` item -- so this module renders nothing but that item.
---
--- Setting `'showcmdloc'` is NOT this function's job: a redraw is the wrong
--- place to change a global option, and the option must go back to what it
--- was once the segment is no longer shown. `ui.statusline.modules.showcmd
--- .loc` does that, driven by `ui.statusline.render` from whether the key
--- `"showcmd"` is in the active `order` (see that module's doc comment).
---
--- `%(...%)` is a Vim statusline group: when every item inside it is empty
--- -- here, `%S` with no key pending -- the group's literal padding goes too,
--- so an idle segment takes no columns at all rather than two blanks.

---@return string
return function()
  return "%#St_Lsp#%( %S %)"
end
