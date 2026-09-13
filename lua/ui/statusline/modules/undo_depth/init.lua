---@module 'ui.statusline.modules.undo_depth'
--- "↺N" -- N undo steps available on the current branch of the undo tree,
--- plus a small branch glyph when the tree has actually branched (edited
--- again after an undo, rather than redoing back to where it was).
--- `vim.fn.undotree()` already tracks all of this; most statuslines never
--- surface it. Not wired into any shipped preset -- opt in by adding
--- "undo_depth" to a host's own `order` and this module to `modules`.

---@param entries table[]
---@return boolean
local function has_branch(entries)
  -- One level deep: an `alt` list appears on the entry the tree diverged
  -- from, the moment an undo is followed by a fresh edit rather than a
  -- redo. Good enough for "is there a branch at all" without walking the
  -- whole tree recursively for a glyph nobody reads past yes/no.
  for _, entry in ipairs(entries) do
    if entry.alt then
      return true
    end
  end
  return false
end

---@return string
return function()
  local ok, tree = pcall(vim.fn.undotree)
  if not ok or type(tree) ~= "table" or not tree.seq_cur or tree.seq_cur == 0 then
    return ""
  end

  local branch = has_branch(tree.entries or {}) and "󰃻 " or ""
  return " %#St_Lsp#↺" .. tree.seq_cur .. " " .. branch
end
