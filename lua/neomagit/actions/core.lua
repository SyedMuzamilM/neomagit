local config = require("neomagit.config")
local runner = require("neomagit.git.runner")
local state = require("neomagit.state.session")
local ui = require("neomagit.ui.status")
local transient = require("neomagit.ui.transient")

local M = {}

local function notify(msg, level)
  vim.notify("[neomagit] " .. msg, level or vim.log.levels.INFO)
end

local function trim(text)
  return (text or ""):gsub("%s+$", "")
end

local function split_lines(text)
  local out = {}
  if not text or text == "" then
    return out
  end
  for line in (text .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      table.insert(out, line)
    end
  end
  return out
end

local function current_session()
  local session = state.current()
  if not session then
    notify("No active neomagit buffer", vim.log.levels.WARN)
    return nil
  end
  return session
end

local function with_refresh(session)
  ui.refresh(session)
end

local function run_serial(session, args, opts, success_msg, cb)
  state.enqueue(session, function(done)
    runner.run(session.context, args, opts, function(res)
      if not res.ok then
        local stderr = trim(res.stderr)
        if stderr == "" then
          stderr = "git " .. table.concat(args, " ") .. " failed"
        end
        notify(stderr, vim.log.levels.ERROR)
      else
        if success_msg then
          notify(success_msg)
        end
        with_refresh(session)
      end
      if cb then
        cb(res)
      end
      done()
    end)
  end)
end

local function require_confirm(message)
  if not config.values.confirm.destructive then
    return true
  end
  return transient.confirm(message, false)
end

local function hunk_apply_args(base_args, hunk)
  local args = vim.deepcopy(base_args)
  local has_context = false

  for idx = 2, #(hunk and hunk.lines or {}) do
    if (hunk.lines[idx] or ""):sub(1, 1) == " " then
      has_context = true
      break
    end
  end

  if not has_context then
    table.insert(args, #args, "--unidiff-zero")
  end

  return args
end

local function choose_commit(session, prompt, cb)
  local recent = (session.snapshot and session.snapshot.recent) or {}
  local items = {}
  for _, commit in ipairs(recent) do
    table.insert(items, { label = commit.hash .. " " .. commit.subject, hash = commit.hash })
  end
  table.insert(items, { label = "Enter commit hash manually", manual = true })

  transient.select(prompt, items, function(choice)
    if not choice then
      return
    end
    if choice.manual then
      transient.input("Commit hash: ", "", function(hash)
        if hash and hash ~= "" then
          cb(hash)
        end
      end)
      return
    end
    cb(choice.hash)
  end)
end

local function list_local_branches(session, cb)
  runner.run(session.context, { "branch", "--format=%(refname:short)" }, nil, function(res)
    if not res.ok then
      notify(trim(res.stderr), vim.log.levels.ERROR)
      return
    end
    local branches = {}
    for _, line in ipairs(split_lines(res.stdout)) do
      table.insert(branches, line)
    end
    table.sort(branches)
    cb(branches)
  end)
end

local function list_remotes(session, cb)
  runner.run(session.context, { "remote" }, nil, function(res)
    if not res.ok then
      notify(trim(res.stderr), vim.log.levels.ERROR)
      return
    end
    local remotes = split_lines(res.stdout)
    table.sort(remotes)
    cb(remotes)
  end)
end

local function list_remote_tracking_branches(session, remote, cb)
  runner.run(session.context, { "branch", "-r", "--format=%(refname:short)" }, nil, function(res)
    if not res.ok then
      notify(trim(res.stderr), vim.log.levels.ERROR)
      return
    end

    local out = {}
    local prefix = remote .. "/"
    for _, ref in ipairs(split_lines(res.stdout)) do
      if ref:sub(1, #prefix) == prefix and not ref:match("/HEAD$") then
        table.insert(out, ref:sub(#prefix + 1))
      end
    end
    table.sort(out)
    cb(out)
  end)
end

local function parse_remote_branch(ref)
  local normalized = trim(ref or ""):gsub("^refs/remotes/", "")
  if normalized == "" then
    return nil, nil
  end
  return normalized:match("^([^/]+)/(.+)$")
end

local function current_branch(session)
  local branch = session.snapshot and session.snapshot.branch or {}
  return branch.head or "HEAD"
end

local function default_remote(session)
  local branch = session.snapshot and session.snapshot.branch or {}
  local upstream_remote = parse_remote_branch(branch.upstream)
  if upstream_remote then
    return upstream_remote
  end
  local push_ref = session.snapshot and session.snapshot.header and session.snapshot.header.push and session.snapshot.header.push.ref
  local push_remote = parse_remote_branch(push_ref)
  if push_remote then
    return push_remote
  end
  return "origin"
end

local function choose_remote(session, prompt, fallback_default, cb)
  list_remotes(session, function(remotes)
    if #remotes == 0 then
      transient.input(prompt or "Remote: ", fallback_default or "origin", function(remote)
        if remote and remote ~= "" then
          cb(remote)
        end
      end)
      return
    end

    local items = {}
    for _, remote in ipairs(remotes) do
      table.insert(items, { label = remote, remote = remote })
    end
    table.insert(items, { label = "Enter remote manually", manual = true })

    transient.select(prompt or "Select remote:", items, function(choice)
      if not choice then
        return
      end
      if choice.manual then
        transient.input("Remote name: ", fallback_default or remotes[1] or "origin", function(remote)
          if remote and remote ~= "" then
            cb(remote)
          end
        end)
        return
      end
      cb(choice.remote)
    end)
  end)
end

local function choose_existing_remote(session, prompt, cb)
  list_remotes(session, function(remotes)
    if #remotes == 0 then
      notify("No remotes configured", vim.log.levels.WARN)
      return
    end

    local items = {}
    for _, remote in ipairs(remotes) do
      table.insert(items, { label = remote, remote = remote })
    end

    transient.select(prompt or "Select remote:", items, function(choice)
      if choice then
        cb(choice.remote)
      end
    end)
  end)
end

local function choose_remote_branch(session, remote, prompt, fallback_default, cb)
  list_remote_tracking_branches(session, remote, function(branches)
    if #branches == 0 then
      transient.input(prompt or ("Remote branch on " .. remote .. ": "), fallback_default or current_branch(session), function(name)
        if name and name ~= "" then
          cb(name)
        end
      end)
      return
    end

    local items = {}
    for _, name in ipairs(branches) do
      table.insert(items, { label = name, branch = name })
    end
    table.insert(items, { label = "Enter branch manually", manual = true })

    transient.select(prompt or ("Select branch on " .. remote .. ":"), items, function(choice)
      if not choice then
        return
      end
      if choice.manual then
        transient.input("Branch name: ", fallback_default or current_branch(session), function(name)
          if name and name ~= "" then
            cb(name)
          end
        end)
        return
      end
      cb(choice.branch)
    end)
  end)
end

local function stash_under_cursor(session)
  local meta = ui.cursor_meta(session)
  if meta and meta.kind == "stash" and meta.stash then
    return meta.stash
  end
  return nil
end

local function choose_stash(session, prompt, cb)
  local stashes = (session.snapshot and session.snapshot.stashes) or {}
  if #stashes == 0 then
    notify("No stashes available", vim.log.levels.WARN)
    return
  end

  local current = stash_under_cursor(session)
  local items = {}

  if current then
    table.insert(items, {
      label = "At cursor: " .. current.ref .. " " .. (current.subject or ""),
      stash = current,
    })
  end

  for _, stash in ipairs(stashes) do
    if not current or current.ref ~= stash.ref then
      table.insert(items, { label = stash.ref .. " " .. stash.subject, stash = stash })
    end
  end
  table.insert(items, { label = "Enter stash ref manually", manual = true })

  transient.select(prompt or "Choose stash:", items, function(choice)
    if not choice then
      return
    end
    if choice.manual then
      transient.input("Stash ref: ", "stash@{0}", function(ref)
        if ref and ref ~= "" then
          cb({ ref = ref, subject = "" })
        end
      end)
      return
    end
    cb(choice.stash)
  end)
end

local function open_readonly_buffer(name, filetype, lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  if filetype and filetype ~= "" then
    vim.bo[buf].filetype = filetype
  end
  pcall(vim.api.nvim_buf_set_name, buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or {})
  vim.api.nvim_set_current_buf(buf)
  vim.keymap.set("n", "q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, { buffer = buf, silent = true, desc = "Close buffer" })
  return buf
end

local function extract_cursor_target()
  local session = current_session()
  if not session then
    return nil, nil
  end
  local meta = ui.cursor_meta(session)
  if not meta then
    notify("Move cursor to a file or hunk first", vim.log.levels.WARN)
    return nil, nil
  end
  return session, meta
end

local function hunk_target_line(meta)
  local hunk = meta and meta.hunk
  local hunk_meta = hunk and hunk.meta or {}
  local new_line = tonumber(hunk_meta.new_start or 1) or 1
  local target_idx = tonumber(meta and meta.hunk_line or 1) or 1

  if new_line < 1 then
    new_line = 1
  end

  if not hunk or target_idx <= 1 then
    return new_line
  end

  for idx = 2, target_idx do
    local line = hunk.lines and hunk.lines[idx] or ""
    local prefix = line:sub(1, 1)

    if idx == target_idx then
      return new_line
    end

    if prefix == " " or prefix == "+" then
      new_line = new_line + 1
    end
  end

  return new_line
end

local function repo_file_path(session, path)
  if not session or not session.context or not path or path == "" then
    return nil
  end
  if path:match("^/") then
    return path
  end
  return session.context.root .. "/" .. path
end

local function file_target_line(session, meta)
  if meta and meta.kind == "hunk" then
    return hunk_target_line(meta)
  end

  local hunks = session
    and session.snapshot
    and session.snapshot.hunks
    and session.snapshot.hunks[meta and meta.section or nil]
  local file_hunks = hunks and hunks[meta and meta.path or nil]
  local first_hunk = file_hunks and file_hunks.hunks and file_hunks.hunks[1]
  if first_hunk then
    return hunk_target_line({ hunk = first_hunk, hunk_line = 2 })
  end

  return 1
end

function M.open_file_from_cursor()
  local session, meta = extract_cursor_target()
  if not session then
    return
  end

  if meta.kind ~= "file" and meta.kind ~= "hunk" then
    notify("Move cursor to a file or hunk first", vim.log.levels.WARN)
    return
  end

  local path = repo_file_path(session, meta.path)
  if not path or not vim.loop.fs_stat(path) then
    notify("File is not available in the working tree: " .. tostring(meta.path or ""), vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(path))

  local line = file_target_line(session, meta)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.max(line, 1), 0 })
end

function M.stage_from_cursor()
  local session, meta = extract_cursor_target()
  if not session then
    return
  end

  if meta.kind == "hunk" and meta.section == "unstaged" then
    run_serial(
      session,
      hunk_apply_args({ "apply", "--cached", "-" }, meta.hunk),
      { stdin = meta.hunk.patch },
      "Staged hunk"
    )
    return
  end

  if meta.kind == "file" and (meta.section == "unstaged" or meta.section == "untracked" or meta.section == "conflicted") then
    run_serial(session, { "add", "--", meta.path }, nil, "Staged " .. meta.path)
    return
  end

  notify("Nothing stageable under cursor", vim.log.levels.WARN)
end

function M.unstage_from_cursor()
  local session, meta = extract_cursor_target()
  if not session then
    return
  end

  if meta.kind == "hunk" and meta.section == "staged" then
    run_serial(
      session,
      hunk_apply_args({ "apply", "--cached", "-R", "-" }, meta.hunk),
      { stdin = meta.hunk.patch },
      "Unstaged hunk"
    )
    return
  end

  if meta.kind == "file" and (meta.section == "staged" or meta.section == "conflicted") then
    run_serial(session, { "restore", "--staged", "--", meta.path }, nil, "Unstaged " .. meta.path)
    return
  end

  notify("Nothing unstageable under cursor", vim.log.levels.WARN)
end

function M.discard_from_cursor()
  local session, meta = extract_cursor_target()
  if not session then
    return
  end

  if meta.kind == "hunk" and meta.section == "unstaged" then
    if not require_confirm("Discard this hunk?") then
      return
    end
    run_serial(
      session,
      hunk_apply_args({ "apply", "-R", "-" }, meta.hunk),
      { stdin = meta.hunk.patch },
      "Discarded hunk"
    )
    return
  end

  if meta.kind == "hunk" and meta.section == "staged" then
    notify("Discard staged hunk is not supported directly. Unstage first.", vim.log.levels.WARN)
    return
  end

  if meta.kind ~= "file" then
    notify("Select a file or hunk to discard", vim.log.levels.WARN)
    return
  end

  if not require_confirm("Discard changes for " .. meta.path .. "?") then
    return
  end

  if meta.section == "untracked" then
    run_serial(session, { "clean", "-f", "--", meta.path }, nil, "Deleted untracked file " .. meta.path)
    return
  end

  if meta.section == "staged" then
    run_serial(
      session,
      { "restore", "--source=HEAD", "--staged", "--worktree", "--", meta.path },
      nil,
      "Discarded staged and unstaged changes for " .. meta.path
    )
    return
  end

  if meta.section == "unstaged" or meta.section == "conflicted" then
    run_serial(session, { "restore", "--worktree", "--", meta.path }, nil, "Discarded " .. meta.path)
    return
  end

  notify("Nothing discardable under cursor", vim.log.levels.WARN)
end

function M.commit_popup()
  local session = current_session()
  if not session then
    return
  end

  local items = {
    { label = "Commit", action = "commit" },
    { label = "Amend", action = "amend" },
    { label = "Amend (no edit)", action = "amend_no_edit" },
    { label = "Fixup", action = "fixup" },
    { label = "Squash", action = "squash" },
  }

  transient.select("Commit action:", items, function(choice)
    if not choice then
      return
    end

    if choice.action == "commit" then
      transient.input("Commit message: ", "", function(msg)
        if msg and msg ~= "" then
          run_serial(session, { "commit", "-m", msg }, nil, "Commit created")
        end
      end)
    elseif choice.action == "amend" then
      transient.input("Amend message (leave blank to keep existing): ", "", function(msg)
        if msg and msg ~= "" then
          run_serial(session, { "commit", "--amend", "-m", msg }, nil, "Commit amended")
        else
          run_serial(session, { "commit", "--amend", "--no-edit" }, nil, "Commit amended")
        end
      end)
    elseif choice.action == "amend_no_edit" then
      run_serial(session, { "commit", "--amend", "--no-edit" }, nil, "Commit amended")
    elseif choice.action == "fixup" then
      choose_commit(session, "Fixup target:", function(hash)
        run_serial(session, { "commit", "--fixup", hash }, nil, "Fixup commit created")
      end)
    elseif choice.action == "squash" then
      choose_commit(session, "Squash target:", function(hash)
        transient.input("Squash commit message (optional): ", "", function(msg)
          local args = { "commit", "--squash", hash }
          if msg and msg ~= "" then
            table.insert(args, "-m")
            table.insert(args, msg)
          end
          run_serial(session, args, nil, "Squash commit created")
        end)
      end)
    end
  end)
end

function M.commit_quick()
  local session = current_session()
  if not session then
    return
  end
  transient.input("Commit message: ", "", function(msg)
    if msg and msg ~= "" then
      run_serial(session, { "commit", "-m", msg }, nil, "Commit created")
    end
  end)
end

function M.branch_popup()
  local session = current_session()
  if not session then
    return
  end

  local items = {
    { label = "Create branch", action = "create" },
    { label = "Switch branch", action = "switch" },
    { label = "Delete branch", action = "delete" },
    { label = "Rename branch", action = "rename" },
  }

  transient.select("Branch action:", items, function(choice)
    if not choice then
      return
    end

    if choice.action == "create" then
      transient.input("New branch name: ", "", function(name)
        if name and name ~= "" then
          run_serial(session, { "switch", "-c", name }, nil, "Switched to new branch " .. name)
        end
      end)
      return
    end

    list_local_branches(session, function(branches)
      if #branches == 0 then
        notify("No branches found", vim.log.levels.WARN)
        return
      end

      transient.select("Select branch:", branches, function(branch)
        if not branch then
          return
        end
        if choice.action == "switch" then
          run_serial(session, { "switch", branch }, nil, "Switched to " .. branch)
        elseif choice.action == "delete" then
          if not require_confirm("Delete branch " .. branch .. "?") then
            return
          end
          run_serial(session, { "branch", "-d", branch }, nil, "Deleted branch " .. branch)
        elseif choice.action == "rename" then
          transient.input("Rename " .. branch .. " to: ", "", function(new_name)
            if new_name and new_name ~= "" then
              run_serial(session, { "branch", "-m", branch, new_name }, nil, "Renamed branch to " .. new_name)
            end
          end)
        end
      end)
    end)
  end)
end

function M.add_remote_quick()
  local session = current_session()
  if not session then
    return
  end
  transient.input("Remote name: ", default_remote(session), function(name)
    if not name or name == "" then
      return
    end
    transient.input("Remote URL: ", "", function(url)
      if not url or url == "" then
        return
      end
      run_serial(session, { "remote", "add", name, url }, nil, "Added remote " .. name)
    end)
  end)
end

function M.remote_popup()
  local session = current_session()
  if not session then
    return
  end

  transient.select("Remote action:", {
    { label = "Add remote", action = "add" },
    { label = "Set remote URL", action = "set_url" },
    { label = "Rename remote", action = "rename" },
    { label = "Remove remote", action = "remove" },
    { label = "Show remotes", action = "show" },
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == "add" then
      M.add_remote_quick()
      return
    end

    if choice.action == "show" then
      runner.run(session.context, { "remote", "-v" }, nil, function(res)
        if not res.ok then
          local stderr = trim(res.stderr)
          notify(stderr ~= "" and stderr or "Failed to list remotes", vim.log.levels.ERROR)
          return
        end
        local lines = split_lines(res.stdout)
        if #lines == 0 then
          lines = { "(no remotes configured)" }
        end
        open_readonly_buffer("Neomagit://remotes", "gitconfig", lines)
      end)
      return
    end

    choose_existing_remote(session, "Select remote:", function(remote)
      if choice.action == "set_url" then
        runner.run(session.context, { "remote", "get-url", remote }, nil, function(res)
          local current_url = ""
          if res.ok then
            current_url = trim(res.stdout)
          end
          transient.input("New URL for " .. remote .. ": ", current_url, function(url)
            if not url or url == "" then
              return
            end
            run_serial(session, { "remote", "set-url", remote, url }, nil, "Updated " .. remote .. " URL")
          end)
        end)
      elseif choice.action == "rename" then
        transient.input("Rename " .. remote .. " to: ", remote, function(new_name)
          if not new_name or new_name == "" or new_name == remote then
            return
          end
          run_serial(session, { "remote", "rename", remote, new_name }, nil, "Renamed remote to " .. new_name)
        end)
      elseif choice.action == "remove" then
        if not require_confirm("Remove remote " .. remote .. "?") then
          return
        end
        run_serial(session, { "remote", "remove", remote }, nil, "Removed remote " .. remote)
      end
    end)
  end)
end

function M.stash_popup()
  local session = current_session()
  if not session then
    return
  end
  local items = {
    { label = "Create stash", action = "create" },
    { label = "Create stash (include untracked)", action = "create_untracked" },
    { label = "Create stash (include ignored)", action = "create_all" },
    { label = "Create stash (keep index)", action = "create_keep_index" },
    { label = "Apply stash", action = "apply" },
    { label = "Pop stash", action = "pop" },
    { label = "Branch from stash", action = "branch" },
    { label = "Show stash patch", action = "show" },
    { label = "Drop stash", action = "drop" },
    { label = "Clear all stashes", action = "clear" },
  }

  transient.select("Stash action:", items, function(choice)
    if not choice then
      return
    end

    if choice.action == "create"
        or choice.action == "create_untracked"
        or choice.action == "create_all"
        or choice.action == "create_keep_index" then
      local extra = {}
      if choice.action == "create_untracked" then
        extra = { "-u" }
      elseif choice.action == "create_all" then
        extra = { "-a" }
      elseif choice.action == "create_keep_index" then
        extra = { "--keep-index" }
      end

      transient.input("Stash message (optional): ", "", function(message)
        local args = { "stash", "push" }
        vim.list_extend(args, extra)
        if message and message ~= "" then
          table.insert(args, "-m")
          table.insert(args, message)
        end
        run_serial(session, args, nil, "Stash created")
      end)
      return
    end

    if choice.action == "clear" then
      if not require_confirm("Clear all stashes? This cannot be undone.") then
        return
      end
      run_serial(session, { "stash", "clear" }, nil, "Cleared all stashes")
      return
    end

    choose_stash(session, "Choose stash:", function(stash)
      if choice.action == "apply" or choice.action == "pop" then
        transient.select("Restore index state as well?", {
          { label = "No (working tree only)", with_index = false },
          { label = "Yes (--index)", with_index = true },
        }, function(index_choice)
          if not index_choice then
            return
          end
          local args = { "stash", choice.action, stash.ref }
          if index_choice.with_index then
            table.insert(args, 3, "--index")
          end
          local verb = choice.action == "pop" and "Popped " or "Applied "
          run_serial(session, args, nil, verb .. stash.ref)
        end)
        return
      elseif choice.action == "branch" then
        local default_name = current_branch(session) .. "-stash"
        transient.input("Branch name for " .. stash.ref .. ": ", default_name, function(name)
          if name and name ~= "" then
            run_serial(session, { "stash", "branch", name, stash.ref }, nil, "Created branch " .. name .. " from " .. stash.ref)
          end
        end)
        return
      elseif choice.action == "show" then
        runner.run(session.context, { "stash", "show", "-p", stash.ref }, nil, function(res)
          if not res.ok then
            local stderr = trim(res.stderr)
            notify(stderr ~= "" and stderr or ("Failed to show " .. stash.ref), vim.log.levels.ERROR)
            return
          end
          local lines = split_lines(res.stdout)
          if #lines == 0 then
            lines = { "(empty stash patch)" }
          end
          open_readonly_buffer("Neomagit://stash/" .. stash.ref, "diff", lines)
        end)
        return
      elseif choice.action == "drop" then
        if not require_confirm("Drop " .. stash.ref .. "?") then
          return
        end
        run_serial(session, { "stash", "drop", stash.ref }, nil, "Dropped " .. stash.ref)
      end
    end)
  end)
end

function M.fetch()
  local session = current_session()
  if not session then
    return
  end

  transient.select("Fetch action:", {
    { label = "Fetch all remotes (--all --prune)", action = "all" },
    { label = "Fetch upstream remote (--prune)", action = "upstream" },
    { label = "Fetch selected remote (--prune)", action = "remote" },
    { label = "Fetch selected remote branch", action = "branch" },
    { label = "Fetch tags", action = "tags" },
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == "all" then
      run_serial(session, { "fetch", "--all", "--prune" }, nil, "Fetched all remotes")
      return
    end

    if choice.action == "tags" then
      run_serial(session, { "fetch", "--tags", "--prune" }, nil, "Fetched tags")
      return
    end

    if choice.action == "upstream" then
      local upstream = session.snapshot and session.snapshot.branch and session.snapshot.branch.upstream
      local remote = parse_remote_branch(upstream)
      if not remote then
        notify("No upstream remote configured", vim.log.levels.WARN)
        return
      end
      run_serial(session, { "fetch", "--prune", remote }, nil, "Fetched " .. remote)
      return
    end

    choose_remote(session, "Fetch from remote:", default_remote(session), function(remote)
      if choice.action == "remote" then
        run_serial(session, { "fetch", "--prune", remote }, nil, "Fetched " .. remote)
        return
      end

      choose_remote_branch(session, remote, "Fetch branch from " .. remote .. ":", current_branch(session), function(branch)
        run_serial(session, { "fetch", "--prune", remote, branch }, nil, "Fetched " .. remote .. "/" .. branch)
      end)
    end)
  end)
end

local function run_push(session, remote, refspec, opts)
  opts = opts or {}
  local args = { "push" }
  if opts.force_with_lease then
    table.insert(args, "--force-with-lease")
  end
  if opts.set_upstream then
    table.insert(args, "-u")
  end
  if opts.tags then
    table.insert(args, "--tags")
  end
  if remote and remote ~= "" then
    table.insert(args, remote)
  end
  if refspec and refspec ~= "" then
    table.insert(args, refspec)
  end
  run_serial(session, args, nil, "Push complete")
end

local function push_with_configured_target(session, opts)
  local branch = session.snapshot and session.snapshot.branch or {}
  if branch.upstream and branch.upstream ~= "" then
    run_push(session, nil, nil, opts)
    return true
  end

  local push_ref = session.snapshot and session.snapshot.header and session.snapshot.header.push and session.snapshot.header.push.ref
  local remote, remote_branch = parse_remote_branch(push_ref)
  if remote and remote_branch then
    local local_branch = current_branch(session)
    local refspec = local_branch
    if local_branch ~= "HEAD" and remote_branch ~= local_branch then
      refspec = local_branch .. ":" .. remote_branch
    end
    run_push(session, remote, refspec, opts)
    return true
  end

  return false
end

local function prompt_push_target(session, opts)
  choose_remote(session, "Push to remote:", default_remote(session), function(remote)
    choose_remote_branch(session, remote, "Remote branch on " .. remote .. ":", current_branch(session), function(remote_branch)
      local local_branch = current_branch(session)
      local refspec = local_branch
      if local_branch ~= "HEAD" and remote_branch ~= local_branch then
        refspec = local_branch .. ":" .. remote_branch
      end
      run_push(session, remote, refspec, opts)
    end)
  end)
end

function M.push()
  local session = current_session()
  if not session then
    return
  end

  if push_with_configured_target(session) then
    return
  end
  prompt_push_target(session, { set_upstream = true })
end

local function push_popup(session)
  transient.select("Push action:", {
    { label = "Push to configured target", action = "default" },
    { label = "Push to selected target", action = "target" },
    { label = "Push and set upstream", action = "set_upstream" },
    { label = "Force push with lease", action = "force_with_lease" },
    { label = "Push tags", action = "tags" },
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == "default" then
      if not push_with_configured_target(session) then
        prompt_push_target(session, { set_upstream = true })
      end
      return
    end

    if choice.action == "tags" then
      run_push(session, nil, nil, { tags = true })
      return
    end

    if choice.action == "force_with_lease" then
      if push_with_configured_target(session, { force_with_lease = true }) then
        return
      end
      prompt_push_target(session, { set_upstream = true, force_with_lease = true })
      return
    end

    prompt_push_target(session, { set_upstream = choice.action == "set_upstream" })
  end)
end

local function run_pull(session, mode, remote, branch)
  local args = { "pull" }
  if mode == "ff_only" then
    table.insert(args, "--ff-only")
  elseif mode == "rebase" then
    table.insert(args, "--rebase")
  elseif mode == "merge" then
    table.insert(args, "--no-rebase")
  end
  if remote and remote ~= "" then
    table.insert(args, remote)
  end
  if branch and branch ~= "" then
    table.insert(args, branch)
  end
  run_serial(session, args, nil, "Pull complete")
end

local function pull_from_upstream(session, mode)
  local branch = session.snapshot and session.snapshot.branch or {}
  if branch.upstream and branch.upstream ~= "" then
    run_pull(session, mode)
    return true
  end
  return false
end

local function pull_from_remote_target(session, mode)
  choose_remote(session, "Pull from remote:", default_remote(session), function(remote)
    choose_remote_branch(session, remote, "Branch on " .. remote .. ":", current_branch(session), function(name)
      run_pull(session, mode, remote, name)
    end)
  end)
end

function M.pull()
  local session = current_session()
  if not session then
    return
  end
  if not pull_from_upstream(session, "ff_only") then
    pull_from_remote_target(session, "ff_only")
  end
end

local function pull_popup(session)
  transient.select("Pull action:", {
    { label = "Pull from upstream (fast-forward only)", action = "upstream_ff" },
    { label = "Pull from upstream (rebase)", action = "upstream_rebase" },
    { label = "Pull from upstream (merge commit allowed)", action = "upstream_merge" },
    { label = "Pull from selected target (fast-forward only)", action = "target_ff" },
    { label = "Pull from selected target (rebase)", action = "target_rebase" },
  }, function(choice)
    if not choice then
      return
    end

    if choice.action == "upstream_ff" then
      if not pull_from_upstream(session, "ff_only") then
        notify("No upstream configured; choose a remote target instead", vim.log.levels.WARN)
      end
    elseif choice.action == "upstream_rebase" then
      if not pull_from_upstream(session, "rebase") then
        notify("No upstream configured; choose a remote target instead", vim.log.levels.WARN)
      end
    elseif choice.action == "upstream_merge" then
      if not pull_from_upstream(session, "merge") then
        notify("No upstream configured; choose a remote target instead", vim.log.levels.WARN)
      end
    elseif choice.action == "target_ff" then
      pull_from_remote_target(session, "ff_only")
    else
      pull_from_remote_target(session, "rebase")
    end
  end)
end

function M.push_pull_popup()
  local session = current_session()
  if not session then
    return
  end

  transient.select("Network action:", {
    { label = "Push", action = "push" },
    { label = "Pull", action = "pull" },
  }, function(choice)
    if not choice then
      return
    end
    if choice.action == "push" then
      push_popup(session)
    else
      pull_popup(session)
    end
  end)
end

function M.rebase_popup()
  local session = current_session()
  if not session then
    return
  end
  if session.snapshot and session.snapshot.operation == "rebase" then
    transient.select("Rebase in progress:", {
      { label = "Continue", action = "continue" },
      { label = "Skip", action = "skip" },
      { label = "Abort", action = "abort" },
    }, function(choice)
      if not choice then
        return
      end
      run_serial(session, { "rebase", "--" .. choice.action }, nil, "Rebase " .. choice.action)
    end)
    return
  end

  transient.select("Start rebase:", {
    { label = "Interactive onto upstream", action = "upstream" },
    { label = "Interactive onto target", action = "target" },
  }, function(choice)
    if not choice then
      return
    end
    if choice.action == "upstream" then
      local upstream = session.snapshot and session.snapshot.branch and session.snapshot.branch.upstream
      if not upstream or upstream == "" then
        notify("No upstream set for current branch", vim.log.levels.WARN)
        return
      end
      run_serial(session, { "rebase", "-i", upstream }, nil, "Started interactive rebase")
    else
      transient.input("Rebase onto: ", "", function(target)
        if target and target ~= "" then
          run_serial(session, { "rebase", "-i", target }, nil, "Started interactive rebase")
        end
      end)
    end
  end)
end

function M.cherry_pick_popup()
  local session = current_session()
  if not session then
    return
  end
  if session.snapshot and session.snapshot.operation == "cherry-pick" then
    transient.select("Cherry-pick in progress:", {
      { label = "Continue", action = "continue" },
      { label = "Abort", action = "abort" },
    }, function(choice)
      if choice then
        run_serial(session, { "cherry-pick", "--" .. choice.action }, nil, "Cherry-pick " .. choice.action)
      end
    end)
    return
  end

  choose_commit(session, "Cherry-pick commit:", function(hash)
    run_serial(session, { "cherry-pick", hash }, nil, "Cherry-pick complete")
  end)
end

function M.revert_popup()
  local session = current_session()
  if not session then
    return
  end
  if session.snapshot and session.snapshot.operation == "revert" then
    transient.select("Revert in progress:", {
      { label = "Continue", action = "continue" },
      { label = "Abort", action = "abort" },
    }, function(choice)
      if choice then
        run_serial(session, { "revert", "--" .. choice.action }, nil, "Revert " .. choice.action)
      end
    end)
    return
  end

  choose_commit(session, "Revert commit:", function(hash)
    run_serial(session, { "revert", hash }, nil, "Revert complete")
  end)
end

function M.reset_popup()
  local session = current_session()
  if not session then
    return
  end
  transient.select("Reset mode:", {
    { label = "Soft", mode = "soft" },
    { label = "Mixed", mode = "mixed" },
    { label = "Hard", mode = "hard" },
  }, function(choice)
    if not choice then
      return
    end
    transient.input("Reset target:", "HEAD~1", function(target)
      if not target or target == "" then
        return
      end
      if choice.mode == "hard" and not require_confirm("Hard reset to " .. target .. "?") then
        return
      end
      run_serial(session, { "reset", "--" .. choice.mode, target }, nil, "Reset " .. choice.mode .. " complete")
    end)
  end)
end

function M.show_log()
  local session = current_session()
  if not session then
    return
  end
  runner.run(session.context, { "log", "--graph", "--decorate", "--oneline", "-n", "200" }, nil, function(res)
    if not res.ok then
      notify(trim(res.stderr), vim.log.levels.ERROR)
      return
    end
    local lines = split_lines(res.stdout)
    open_readonly_buffer("Neomagit://log", "git", lines)
  end)
end

function M.open_branch_popup()
  M.branch_popup()
end

function M.open_remote_popup()
  M.remote_popup()
end

function M.open_stash_popup()
  M.stash_popup()
end

function M.open_rebase_popup()
  M.rebase_popup()
end

function M.open_cherry_pick_popup()
  M.cherry_pick_popup()
end

M._hunk_target_line = hunk_target_line

return M
