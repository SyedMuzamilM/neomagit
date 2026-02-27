# neomagit

`neomagit` is a Neovim Git plugin inspired by Magit.

It provides a central status buffer with section-based Git workflows:

- stage/unstage/discard (file and hunk)
- commit/amend/fixup/squash
- branch and stash flows
- fetch/push/pull
- rebase/cherry-pick/revert/reset
- worktree/submodule visibility

## Requirements

- Neovim 0.9+
- Git 2.30+

## Installation

### lazy.nvim (local path)

```lua
{
  dir = "/absolute/path/to/neomagit",
  name = "neomagit",
  config = function()
    require("neomagit").setup()
  end,
}
```

### lazy.nvim (git URL)

```lua
{
  "your-org/neomagit",
  config = function()
    require("neomagit").setup()
  end,
}
```

### packer.nvim

```lua
use({
  "your-org/neomagit",
  config = function()
    require("neomagit").setup()
  end,
})
```

## Commands

- `:Neomagit`
- `:NeomagitLog`
- `:NeomagitBranch`
- `:NeomagitStash`
- `:NeomagitRebase`
- `:NeomagitCherryPick`
- `:NeomagitRefresh`

## Default Mappings

Global:

- `<leader>gg` -> open neomagit (when `keymaps = "default"`)

In status buffer:

- `q` close
- `g` refresh
- `<Tab>` fold/unfold section
- `?` toggle help
- `s` stage (file/hunk)
- `u` unstage (file/hunk)
- `x` discard (file/hunk for unstaged)
- `c` commit popup
- `b` branch popup
- `z` stash popup
- `f` fetch
- `p` push/pull popup
- `r` rebase popup
- `A` cherry-pick popup
- `v` revert popup
- `R` reset popup
- `l` full log view

## Configuration

```lua
require("neomagit").setup({
  keymaps = "default", -- "default" | "none"
  signs = {
    staged = "S",
    unstaged = "U",
    untracked = "?",
    conflicted = "!",
  },
  ui = {
    float = false,
    border = "rounded",
    max_width = 120,
    highlights = true,
  },
  git = {
    bin = "git",
    timeout_ms = 15000,
  },
  confirm = {
    destructive = true,
  },
})
```

## Highlight Groups

You can override these in your colorscheme or config:

- `NeomagitTitle`
- `NeomagitMeta`
- `NeomagitSection`
- `NeomagitHint`
- `NeomagitHelp`
- `NeomagitHunk`
- `NeomagitStash`
- `NeomagitCommit`
- `NeomagitWorktree`
- `NeomagitSubmodule`
- `NeomagitFileStaged`
- `NeomagitFileUnstaged`
- `NeomagitFileUntracked`
- `NeomagitFileConflicted`
- `NeomagitSignStaged`
- `NeomagitSignUnstaged`
- `NeomagitSignUntracked`
- `NeomagitSignConflicted`

## Notes

- All Git operations run through async CLI jobs.
- Actions are queued per repository to reduce race conditions.
- Worktree and submodule summaries are shown in status.
