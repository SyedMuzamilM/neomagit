local runner = require("neomagit.git.runner")

local M = {}

local function normalize(path)
  if not path or path == "" then
    return vim.loop.cwd()
  end
  local stat = vim.loop.fs_stat(path)
  if stat and stat.type == "file" then
    return vim.fn.fnamemodify(path, ":h")
  end
  return path
end

local function trim(text)
  return (text or ""):gsub("%s+$", "")
end

function M.discover(start_path)
  local cwd = normalize(start_path or vim.api.nvim_buf_get_name(0))
  local root_res = runner.run_sync(cwd, { "rev-parse", "--show-toplevel" })
  if not root_res.ok then
    return nil, "Not inside a git repository"
  end

  local root = trim(root_res.stdout)
  local git_dir_res = runner.run_sync(root, { "rev-parse", "--git-dir" })
  local git_dir = trim(git_dir_res.stdout)
  if git_dir ~= "" and not git_dir:match("^/") then
    git_dir = root .. "/" .. git_dir
  end

  local inside_worktree = runner.run_sync(root, { "rev-parse", "--is-inside-work-tree" })
  return {
    cwd = root,
    root = root,
    git_dir = git_dir,
    is_worktree = trim(inside_worktree.stdout) == "true",
  }
end

return M
