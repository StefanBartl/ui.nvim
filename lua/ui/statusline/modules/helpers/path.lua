---@module 'ui.statusline.modules.helpers.path'
--- The current file's path relative to its git root (or `:~:.` when there is
--- no git root), falling back to just the tail name if the git-relative
--- form did not actually shorten anything.

local M = {}

local fnamemodify = vim.fn.fnamemodify

---@nodiscard
---@param path string
---@return string
function M.repo_relative(path)
  if path == "" then
    return "[No Name]"
  end
  local dir = fnamemodify(path, ":h")
  local gitdir = (vim.fs.find(".git", { upward = true, path = dir }) or {})[1]
  if gitdir then
    local root = fnamemodify(gitdir, ":h")
    local rel = fnamemodify(path, (":~:%s"):format(root))
    if rel == path then
      return fnamemodify(path, ":t")
    end
    rel = rel:gsub("^%./", ""):gsub("^/", "")
    return rel
  end
  return fnamemodify(path, ":~:.")
end

return M
