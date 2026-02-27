local parsers = require("neomagit.git.parsers")
local runner = require("neomagit.git.runner")

local M = {}

local function path_exists(path)
  return path and vim.loop.fs_stat(path) ~= nil
end

local function git_path(context, name)
  local out = runner.run_sync(context, { "rev-parse", "--git-path", name })
  if not out.ok then
    return nil
  end
  local path = (out.stdout or ""):gsub("%s+$", "")
  if path == "" then
    return nil
  end
  if path:match("^/") then
    return path
  end
  return context.root .. "/" .. path
end

local function detect_operation(context)
  local operation_checks = {
    { key = "rebase", paths = { "rebase-merge", "rebase-apply" } },
    { key = "merge", paths = { "MERGE_HEAD" } },
    { key = "cherry-pick", paths = { "CHERRY_PICK_HEAD" } },
    { key = "revert", paths = { "REVERT_HEAD" } },
    { key = "bisect", paths = { "BISECT_LOG" } },
  }
  for _, check in ipairs(operation_checks) do
    for _, rel in ipairs(check.paths) do
      local abs = git_path(context, rel)
      if abs and path_exists(abs) then
        return check.key
      end
    end
  end
  return nil
end

local function run_tasks(context, tasks, on_done)
  local pending = 0
  local results = {}

  for _ in pairs(tasks) do
    pending = pending + 1
  end

  if pending == 0 then
    on_done(results)
    return
  end

  for key, spec in pairs(tasks) do
    runner.run(context, spec.args, spec.opts, function(res)
      results[key] = res
      pending = pending - 1
      if pending == 0 then
        on_done(results)
      end
    end)
  end
end

function M.collect(context, cb)
  run_tasks(context, {
    status = { args = { "status", "--porcelain=v1", "--branch", "--untracked-files=all" } },
    diff_unstaged = { args = { "diff", "--no-color", "--unified=0" } },
    diff_staged = { args = { "diff", "--cached", "--no-color", "--unified=0" } },
    stash_list = { args = { "stash", "list" } },
    log = { args = { "log", "--oneline", "-n", "20" } },
    worktrees = { args = { "worktree", "list", "--porcelain" } },
    submodules = { args = { "submodule", "status", "--recursive" } },
  }, function(results)
    local status_res = results.status
    if not status_res or not status_res.ok then
      cb("Failed to read git status: " .. ((status_res and status_res.stderr) or "unknown"))
      return
    end

    local parsed = parsers.parse_status_porcelain(status_res.stdout)
    local diff_unstaged = parsers.parse_unified_diff(results.diff_unstaged and results.diff_unstaged.stdout or "")
    local diff_staged = parsers.parse_unified_diff(results.diff_staged and results.diff_staged.stdout or "")

    local snapshot = {
      branch = parsed.branch,
      sections = parsed.sections,
      hunks = {
        unstaged = diff_unstaged,
        staged = diff_staged,
      },
      stashes = parsers.parse_stash_list(results.stash_list and results.stash_list.stdout or ""),
      recent = parsers.parse_oneline_log(results.log and results.log.stdout or ""),
      worktrees = parsers.parse_worktree_list(results.worktrees and results.worktrees.stdout or ""),
      submodules = parsers.parse_submodule_status(results.submodules and results.submodules.stdout or ""),
      operation = detect_operation(context),
      timestamp = os.time(),
    }

    cb(nil, snapshot)
  end)
end

return M
