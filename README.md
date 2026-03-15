# neomagit

`neomagit` is a Neovim Git plugin inspired by Magit.

It provides a central status buffer with section-based Git workflows:

- stage/unstage/discard (file and hunk)
- commit/amend/fixup/squash
- branch flows
- remote management (add/set-url/rename/remove/list)
- stash flows (create/apply/pop/drop/clear, include-untracked/all, keep-index, branch-from-stash, show patch)
- fetch/push/pull flows (upstream/push-target aware, remote+branch selection, force-with-lease, rebase pull mode, tags)
- tracking sections (Unpulled from / Unmerged into for upstream and push-target)
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
- `:NeomagitRemote`
- `:NeomagitStash`
- `:NeomagitFetch`
- `:NeomagitPull`
- `:NeomagitPush`
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
- `C` quick commit
- `b` branch popup
- `m` remote popup
- `O` quick add remote
- `z` stash popup
- `f` fetch popup
- `p` push/pull popup
- `P` quick push
- `U` quick pull
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
    style = "magit", -- "magit" | "classic"
    float = false,
    border = "rounded",
    max_width = 120,
    highlights = true,
    magit = {
      show_header = true, -- Head/Merge/Push/Tag lines
      show_tag_line = true,
      compact_sections = false,
    },
  },
  git = {
    bin = "git",
    timeout_ms = 15000,
    diff_context = 3,
  },
  confirm = {
    destructive = true,
  },
})
```

`ui.style = "magit"` uses a Magit-like status layout (Head/Merge/Push/Tag header + status-word file rows).
Set `ui.style = "classic"` to keep the previous neomagit layout.
Set `git.diff_context` to control how many unchanged lines are shown around each diff hunk.

## Highlight Groups

You can override these in your colorscheme or config:

- `NeomagitTitle`
- `NeomagitMeta`
- `NeomagitSection`
- `NeomagitSectionMarker`
- `NeomagitSectionCount`
- `NeomagitSectionTitle`
- `NeomagitHeaderLabel`
- `NeomagitHeaderRef`
- `NeomagitHeaderSubject`
- `NeomagitHint`
- `NeomagitHelp`
- `NeomagitHunk`
- `NeomagitHunkMarker`
- `NeomagitStash`
- `NeomagitHash`
- `NeomagitCommit`
- `NeomagitWorktree`
- `NeomagitSubmodule`
- `NeomagitFileStaged`
- `NeomagitFileUnstaged`
- `NeomagitFileUntracked`
- `NeomagitFileConflicted`
- `NeomagitItemStatusStaged`
- `NeomagitItemStatusUnstaged`
- `NeomagitItemStatusUntracked`
- `NeomagitItemStatusConflicted`
- `NeomagitItemPath`
- `NeomagitSignStaged`
- `NeomagitSignUnstaged`
- `NeomagitSignUntracked`
- `NeomagitSignConflicted`

## Notes

- All Git operations run through async CLI jobs.
- Actions are queued per repository to reduce race conditions.
- Worktree and submodule summaries are shown in status.
- The status buffer auto-refreshes when you re-enter it or refocus Neovim, so new/untracked and deleted files stay in sync with the worktree.
