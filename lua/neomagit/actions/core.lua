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

local function list_branches(session, cb)
  runner.run(session.context, { "branch", "--format=%(refname:short)" }, nil, function(res)
    if not res.ok then
      notify(trim(res.stderr), vim.log.levels.ERROR)
      return
    end
    local branches = {}
    for _, line in ipairs(split_lines(res.stdout)) do
      table.insert(branches, line)
    end
    cb(branches)
  end)
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

function M.stage_from_cursor()
  local session, meta = extract_cursor_target()
  if not session then
    return
  end

  if meta.kind == "hunk" and meta.section == "unstaged" then
    run_serial(
      session,
      { "apply", "--cached", "--unidiff-zero", "-" },
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
      { "apply", "--cached", "-R", "--unidiff-zero", "-" },
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
      { "apply", "-R", "--unidiff-zero", "-" },
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

    list_branches(session, function(branches)
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

function M.stash_popup()
  local session = current_session()
  if not session then
    return
  end
  local items = {
    { label = "Create stash", action = "create" },
    { label = "Apply stash", action = "apply" },
    { label = "Pop stash", action = "pop" },
    { label = "Drop stash", action = "drop" },
  }

  transient.select("Stash action:", items, function(choice)
    if not choice then
      return
    end

    if choice.action == "create" then
      transient.input("Stash message (optional): ", "", function(message)
        local args = { "stash", "push" }
        if message and message ~= "" then
          table.insert(args, "-m")
          table.insert(args, message)
        end
        run_serial(session, args, nil, "Stash created")
      end)
      return
    end

    local stashes = (session.snapshot and session.snapshot.stashes) or {}
    if #stashes == 0 then
      notify("No stashes available", vim.log.levels.WARN)
      return
    end

    local items = {}
    for _, stash in ipairs(stashes) do
      table.insert(items, { label = stash.ref .. " " .. stash.subject, stash = stash })
    end

    transient.select("Choose stash:", items, function(selected)
      if not selected then
        return
      end
      local stash = selected.stash
      if choice.action == "apply" then
        run_serial(session, { "stash", "apply", stash.ref }, nil, "Applied " .. stash.ref)
      elseif choice.action == "pop" then
        run_serial(session, { "stash", "pop", stash.ref }, nil, "Popped " .. stash.ref)
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
  run_serial(session, { "fetch", "--all", "--prune" }, nil, "Fetched remotes")
end

local function do_push(session)
  local branch = session.snapshot and session.snapshot.branch or {}
  if branch.upstream and branch.upstream ~= "" then
    run_serial(session, { "push" }, nil, "Push complete")
    return
  end

  transient.input("Remote for upstream push: ", "origin", function(remote)
    if not remote or remote == "" then
      return
    end
    local head = branch.head or "HEAD"
    run_serial(session, { "push", "-u", remote, head }, nil, "Push complete")
  end)
end

local function do_pull(session)
  local branch = session.snapshot and session.snapshot.branch or {}
  if branch.upstream and branch.upstream ~= "" then
    run_serial(session, { "pull", "--ff-only" }, nil, "Pull complete")
    return
  end

  transient.input("Remote: ", "origin", function(remote)
    if not remote or remote == "" then
      return
    end
    transient.input("Branch: ", branch.head or "main", function(name)
      if not name or name == "" then
        return
      end
      run_serial(session, { "pull", "--ff-only", remote, name }, nil, "Pull complete")
    end)
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
      do_push(session)
    else
      do_pull(session)
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
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].filetype = "git"
    pcall(vim.api.nvim_buf_set_name, buf, "Neomagit://log")
    local lines = split_lines(res.stdout)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    vim.keymap.set("n", "q", function()
      vim.api.nvim_buf_delete(buf, { force = true })
    end, { buffer = buf, silent = true, desc = "Close log" })
  end)
end

function M.open_branch_popup()
  M.branch_popup()
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

return M
