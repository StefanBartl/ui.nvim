---@meta
---@module 'ui.statusline.modules.lsp.@types'

---@alias Ui.UI.Stl.Modules.Based.PathMode_t
--- Controls the reference frame used to render the buffer path.
--- Behavior details:
---| '"auto"' : Try repo root (fast upward scan for ".git"; if worktree, use the worktree top). If no repo,
---             use cwd-relative. If still identical, emit absolute (canonicalized).
---| "repo": Always compute relative to repo root; if no repo is detected, emit absolute (canonicalized).
---| "cwd":  Always compute relative to current working directory (vim.fn.getcwd()).
---| "absolute": Emit absolute (canonicalized) path; no relativization is attempted.
---| "home": Emit absolute path but replace $HOME prefix with "~" (if path is inside $HOME).
--- Edge cases:
---   • Unnamed/empty buffer names yield "[No Name]".
---   • Non-existing paths are still normalized syntactically; realpath resolution is best-effort.
---   • Symlinks: If uv.fs_realpath succeeds, the canonical target is shown; otherwise the expanded absolute path.
---   • Git worktrees: If ".git" is a file containing "gitdir: ...", the enclosing directory is treated as the repo root.

---@alias Ui.UI.Stl.Modules.Based.Path_home_tilde_t boolean
--- Whether to shorten the user's home directory prefix to "~" in absolute-style outputs.
--- Applies to:
---   • "absolute" and "home" modes directly.
---   • "auto" mode when it falls back to absolute output (i.e., no repo and cwd-relative equals absolute).
--- Does not affect:
---   • Purely relative outputs ("repo"/"cwd"), unless those modes fall back to absolute as described.
--- Rationale:
---   • Improves readability by reducing long, stable prefixes ("/Users/alice/", "/home/alice/") to "~/".
---   • Never alters genuinely relative strings like "src/module/file.lua".
--- Notes:
---   • Only applied if the absolute path begins with the user's home directory as returned by uv.os_homedir().
---   • On systems without a valid home directory, this option is effectively a no-op.

---@class Ui.UI.Stl.Modules.LSP.PathCfg
---@field path_mode Ui.UI.Stl.Modules.Based.PathMode_t
---@field path_home_tilde Ui.UI.Stl.Modules.Based.Path_home_tilde_t

---@class Ui.UI.Stl.Modules.LSP.Cfg
---@field debounce_ms? integer
---@field update_events? string[]
---@field center_width_frac? number
---@field center_width_min? number
---@field path_max_frac? number
---@field path_max_chars? number|nil
---@field path_min_room? number
---@field path_mode Ui.UI.Stl.Modules.Based.PathMode_t
---@field path_home_tilde Ui.UI.Stl.Modules.Based.Path_home_tilde_t

---@alias Ui.UI.Stl.Modules.Lsp.CfgKey
---| "debounce_ms"
---| "update_events"
---| "center_width_frac"
---| "center_width_min"
---| "path_max_frac"
---| "path_max_chars"
---| "path_min_room"
---| "path_mode"
---| "path_home_tilde"

---@class Ui.UI.Status.Modules.Lsp.Symbols.Doc.SymCache
---@field version integer
---@field items table[]|nil
---@field hierarchical boolean
---@field client_id integer|nil
---@field last_req number
---@field pending boolean

---@class Ui.UI.Stl.Modules.LSP.Cfg.Module
---@field get_cfg fun(): Ui.UI.Stl.Modules.LSP.Cfg
---@field get fun(key: Ui.UI.Stl.Modules.Lsp.CfgKey): any
---@field set fun(key: Ui.UI.Stl.Modules.Lsp.CfgKey, value: any): nil
---@field update fun(patch: table<string, any>): nil

return {}
