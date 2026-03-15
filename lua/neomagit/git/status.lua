local config = require("neomagit.config")
local parsers = require("neomagit.git.parsers")
local runner = require("neomagit.git.runner")

local M = {}

local function trim(text)
  return (text or ""):gsub("%s+$", "")
end

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

local function build_header(branch, results)
  local head_ref = branch.detached and "HEAD" or (branch.head or "HEAD")

  local header = {
    head = {
      ref = head_ref,
      subject = trim(results.head_subject and results.head_subject.stdout or ""),
    },
    merge = {
      ref = trim(results.upstream_ref and results.upstream_ref.stdout or "") ~= ""
          and trim(results.upstream_ref.stdout)
        or branch.upstream,
      subject = trim(results.upstream_subject and results.upstream_subject.stdout or ""),
    },
    push = {
      ref = trim(results.push_ref and results.push_ref.stdout or ""),
      subject = trim(results.push_subject and results.push_subject.stdout or ""),
    },
    tag = nil,
  }

  local tag_name = trim(results.head_tag and results.head_tag.stdout or "")
  if tag_name ~= "" then
    header.tag = {
      name = tag_name,
      short_hash = trim(results.head_short and results.head_short.stdout or ""),
    }
  end

  return header
end

local function parse_oneline_result(result)
  if not result or not result.ok then
    return {}
  end
  return parsers.parse_oneline_log(result.stdout or "")
end

local function build_tracking_sections(branch, header, results)
  local sections = {}
  local merge_ref = trim(header and header.merge and header.merge.ref or "")
  if merge_ref == "" then
    merge_ref = trim(branch and branch.upstream or "")
  end
  local push_ref = trim(header and header.push and header.push.ref or "")

  local function push_section(key, title, commits)
    if #commits == 0 then
      return
    end
    table.insert(sections, {
      key = key,
      title = title,
      commits = commits,
    })
  end

  if merge_ref ~= "" then
    push_section("unpulled_upstream", "Unpulled from " .. merge_ref, parse_oneline_result(results.unpulled_upstream))
    push_section("unmerged_upstream", "Unmerged into " .. merge_ref, parse_oneline_result(results.unmerged_upstream))
  end

  if push_ref ~= "" and push_ref ~= merge_ref then
    push_section("unpulled_push", "Unpulled from " .. push_ref, parse_oneline_result(results.unpulled_push))
    push_section("unmerged_push", "Unmerged into " .. push_ref, parse_oneline_result(results.unmerged_push))
  end

  return sections
end

function M.collect(context, cb)
  local diff_context = math.max(0, tonumber(config.values.git.diff_context) or 0)

  run_tasks(context, {
    status = { args = { "status", "--porcelain=v1", "--branch", "--untracked-files=all" } },
    head_subject = { args = { "show", "-s", "--format=%s", "HEAD" } },
    upstream_ref = { args = { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{upstream}" } },
    upstream_subject = { args = { "show", "-s", "--format=%s", "@{upstream}" } },
    push_ref = { args = { "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{push}" } },
    push_subject = { args = { "show", "-s", "--format=%s", "@{push}" } },
    head_tag = { args = { "describe", "--tags", "--exact-match", "HEAD" } },
    head_short = { args = { "rev-parse", "--short", "HEAD" } },
    diff_unstaged = { args = { "diff", "--no-color", "--unified=" .. diff_context } },
    diff_staged = { args = { "diff", "--cached", "--no-color", "--unified=" .. diff_context } },
    unpulled_upstream = { args = { "log", "--oneline", "..@{upstream}", "-n", "20" } },
    unmerged_upstream = { args = { "log", "--oneline", "@{upstream}..", "-n", "20" } },
    unpulled_push = { args = { "log", "--oneline", "..@{push}", "-n", "20" } },
    unmerged_push = { args = { "log", "--oneline", "@{push}..", "-n", "20" } },
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
    local branch = parsed.branch or {}
    local header = build_header(branch, results)
    local tracking = build_tracking_sections(branch, header, results)

    local snapshot = {
      branch = branch,
      header = header,
      tracking = tracking,
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

M._build_header = build_header
M._build_tracking_sections = build_tracking_sections

return M
