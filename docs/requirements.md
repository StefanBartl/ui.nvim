# Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required |

[NvChad](https://github.com/NvChad/NvChad) is **not** required, and is not
even installed any more in the reference host this plugin was extracted
from. See [nvchad-migration.md](nvchad-migration.md) for what that coupling
used to be and how each piece of it was replaced.

## Optional integrations

Each is detected at runtime and blanks only its own segment. None of them is
loaded by this plugin — the segment reads what the other plugin already
published, or renders nothing.

| | |
| --- | --- |
| `nvim-web-devicons` | File icons; without it `lib.nvim.ui.icons` (a curated devicons subset shipped as data) fills the column |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Branch name and added/changed/removed counts (`git`, `git_clickable`) |
| [casedesk.nvim](https://github.com/StefanBartl/casedesk.nvim) | Case info plus the SLA urgency badge (`casedesk`) |
| [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) | The cwd-mode badge (`filetree_cwd_mode`) |
| [github_stats.nvim](https://github.com/StefanBartl/github_stats.nvim) | This week's view count for the repo the buffer is in (`github_stats_badge`) |
| [runtime-analysis.nvim](https://github.com/StefanBartl/runtime-analysis.nvim) | The health traffic light across instrumented plugins (`runtime_analysis_ampel`) |
| [recommender.nvim](https://github.com/StefanBartl/recommender.nvim) | Count of open alias suggestions for the current buffer (`recommender_badge`) |
| [sessions.nvim](https://github.com/StefanBartl/sessions.nvim) | Active session name with a dirty marker (`session_status`) |
| [sandbox.nvim](https://github.com/StefanBartl/sandbox.nvim) | Ambient container summary (`sandbox_ambient`) |
| [lazy.nvim](https://github.com/folke/lazy.nvim) | Own/external plugin count (`plugin_summary`) |
| `nvim-treesitter` | Breadcrumb fallback while the LSP has not produced document symbols yet |

`:checkhealth ui` reports each of these separately, under "Statusline
segments" — except `nvim-treesitter`, which is a fallback inside another
segment rather than a segment of its own.

Which preset actually wires which of these in is
[modules.md](modules.md); a segment listed here but not in your preset's
`order` costs nothing either way.
