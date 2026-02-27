local M = {}

local function split_lines(text)
  local lines = {}
  if not text or text == "" then
    return lines
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    table.insert(lines, line)
  end
  if lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  return lines
end

local function trim_prefix(line, prefix)
  if line:sub(1, #prefix) == prefix then
    return line:sub(#prefix + 1)
  end
  return line
end

local function parse_branch(line)
  local branch = {
    head = "HEAD",
    upstream = nil,
    ahead = 0,
    behind = 0,
    detached = false,
  }

  local text = trim_prefix(line, "## ")
  if text:match("^HEAD") then
    branch.detached = true
    branch.head = "HEAD"
    return branch
  end

  local head, upstream = text:match("^(.-)%.%.%.([^ ]+)")
  if head then
    branch.head = head
    branch.upstream = upstream
  else
    branch.head = text:match("^([^ ]+)") or text
  end

  local ahead = text:match("ahead (%d+)")
  local behind = text:match("behind (%d+)")
  branch.ahead = tonumber(ahead) or 0
  branch.behind = tonumber(behind) or 0
  return branch
end

local function is_conflict(x, y)
  if x == "U" or y == "U" then
    return true
  end
  if (x == "A" and y == "A") or (x == "D" and y == "D") then
    return true
  end
  return false
end

local function parse_path(rest)
  local old, new = rest:match("^(.-) %-%> (.+)$")
  if old and new then
    return new, old
  end
  return rest, nil
end

function M.parse_status_porcelain(text)
  local out = {
    branch = {
      head = "HEAD",
      upstream = nil,
      ahead = 0,
      behind = 0,
      detached = false,
    },
    sections = {
      conflicted = {},
      staged = {},
      unstaged = {},
      untracked = {},
    },
  }

  for _, line in ipairs(split_lines(text)) do
    if line:sub(1, 3) == "## " then
      out.branch = parse_branch(line)
    elseif #line >= 3 then
      local xy = line:sub(1, 2)
      local rest = line:sub(4)
      local path, orig_path = parse_path(rest)
      local x = xy:sub(1, 1)
      local y = xy:sub(2, 2)

      if xy == "??" then
        table.insert(out.sections.untracked, { path = path, code = xy })
      elseif xy ~= "!!" then
        if is_conflict(x, y) then
          table.insert(out.sections.conflicted, { path = path, code = xy })
        else
          if x ~= " " then
            table.insert(out.sections.staged, { path = path, orig_path = orig_path, code = x })
          end
          if y ~= " " then
            table.insert(out.sections.unstaged, { path = path, orig_path = orig_path, code = y })
          end
        end
      end
    end
  end

  return out
end

local function parse_hunk_header(line)
  local old_start, old_count, new_start, new_count, label =
    line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@ ?(.*)$")
  return {
    old_start = tonumber(old_start or "0"),
    old_count = tonumber(old_count ~= "" and old_count or "1"),
    new_start = tonumber(new_start or "0"),
    new_count = tonumber(new_count ~= "" and new_count or "1"),
    label = label or "",
  }
end

local function finalize_file(files, path, headers, hunks)
  if not path then
    return
  end
  files[path] = files[path] or { path = path, hunks = {} }
  for _, hunk in ipairs(hunks) do
    local patch_lines = {}
    for _, h in ipairs(headers) do
      table.insert(patch_lines, h)
    end
    for _, l in ipairs(hunk.lines) do
      table.insert(patch_lines, l)
    end
    hunk.patch = table.concat(patch_lines, "\n") .. "\n"
    table.insert(files[path].hunks, hunk)
  end
end

function M.parse_unified_diff(text)
  local files = {}
  local current_path
  local headers = {}
  local hunks = {}
  local current_hunk

  local function flush_hunk()
    if current_hunk then
      table.insert(hunks, current_hunk)
      current_hunk = nil
    end
  end

  local function flush_file()
    flush_hunk()
    finalize_file(files, current_path, headers, hunks)
    headers = {}
    hunks = {}
    current_path = nil
  end

  for _, line in ipairs(split_lines(text)) do
    local a_path, b_path = line:match("^diff %-%-git a/(.-) b/(.-)$")
    if a_path and b_path then
      flush_file()
      current_path = b_path ~= "/dev/null" and b_path or a_path
      table.insert(headers, line)
    elseif line:sub(1, 2) == "@@" then
      flush_hunk()
      current_hunk = {
        header = line,
        lines = { line },
        meta = parse_hunk_header(line),
      }
    elseif current_hunk then
      table.insert(current_hunk.lines, line)
    elseif current_path then
      table.insert(headers, line)
    end
  end

  flush_file()
  return files
end

function M.parse_stash_list(text)
  local stashes = {}
  for _, line in ipairs(split_lines(text)) do
    local ref, subject = line:match("^(stash@{%d+}):%s*(.*)$")
    if ref then
      table.insert(stashes, { ref = ref, subject = subject })
    end
  end
  return stashes
end

function M.parse_oneline_log(text)
  local commits = {}
  for _, line in ipairs(split_lines(text)) do
    local hash, subject = line:match("^([0-9a-fA-F]+)%s+(.*)$")
    if hash then
      table.insert(commits, { hash = hash, subject = subject })
    end
  end
  return commits
end

function M.parse_worktree_list(text)
  local worktrees = {}
  local current
  for _, line in ipairs(split_lines(text)) do
    local key, value = line:match("^(%S+)%s+(.+)$")
    if key == "worktree" then
      if current then
        table.insert(worktrees, current)
      end
      current = { path = value, branch = nil, head = nil, bare = false }
    elseif current and key == "branch" then
      current.branch = value:gsub("^refs/heads/", "")
    elseif current and key == "HEAD" then
      current.head = value
    elseif current and key == "bare" then
      current.bare = true
    end
  end
  if current then
    table.insert(worktrees, current)
  end
  return worktrees
end

function M.parse_submodule_status(text)
  local mods = {}
  for _, line in ipairs(split_lines(text)) do
    local state = line:sub(1, 1)
    local sha, path, rest = line:match("^.([0-9a-f]+)%s+([^ ]+)%s*(.*)$")
    if sha and path then
      table.insert(mods, { state = state, sha = sha, path = path, desc = rest })
    end
  end
  return mods
end

return M
