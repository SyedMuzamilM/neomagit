local M = {}

local defaults = {
  keymaps = "default",
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
}

M.values = vim.deepcopy(defaults)

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

return M
