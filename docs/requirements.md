# Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required |

[NvChad](https://github.com/NvChad/NvChad) is **not** required, and is not
even installed any more in the reference host this plugin was extracted
from. See [nvchad-migration.md](nvchad-migration.md) for what that coupling
used to be and how each piece of it was replaced.

Optional, each detected at runtime and blanking only its own segment:

| | |
| --- | --- |
| `nvim-web-devicons` | File icons |
| `neotest` | The test-runner segment |
| [casedesk.nvim](https://github.com/StefanBartl/casedesk.nvim) | The case-info statusline segment |
| [filetree.nvim](https://github.com/StefanBartl/filetree.nvim) | The cwd-mode badge segment |

`:checkhealth ui` reports each of these separately.
