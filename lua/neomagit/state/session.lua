local status = require("neomagit.git.status")

local M = {}

local sessions_by_repo = {}
local sessions_by_buf = {}

local function new_session(context)
  return {
    context = context,
    snapshot = nil,
    buf = nil,
    line_map = {},
    running = false,
    queue = {},
    ui = {
      folded = {
        branches = false,
        conflicted = false,
        staged = true,
        unstaged = true,
        untracked = false,
        unpulled_upstream = true,
        unmerged_upstream = true,
        unpulled_push = true,
        unmerged_push = true,
        stashes = true,
        recent = true,
        worktrees = true,
        submodules = true,
      },
      file_folded = {},
      commit_expanded = {},
      commit_diff_cache = {},
      commit_diff_loading = {},
      help_open = false,
      auto_refresh = {
        running = false,
        last_ns = 0,
      },
    },
  }
end

function M.get_or_create(context)
  local key = context.root
  if not sessions_by_repo[key] then
    sessions_by_repo[key] = new_session(context)
  end
  return sessions_by_repo[key]
end

function M.bind_buffer(session, buf)
  session.buf = buf
  sessions_by_buf[buf] = session
end

function M.unbind_buffer(buf)
  sessions_by_buf[buf] = nil
end

function M.by_buffer(buf)
  return sessions_by_buf[buf]
end

function M.current()
  return M.by_buffer(vim.api.nvim_get_current_buf())
end

function M.enqueue(session, fn)
  if session.running then
    table.insert(session.queue, fn)
    return
  end
  session.running = true
  fn(function()
    session.running = false
    local next_fn = table.remove(session.queue, 1)
    if next_fn then
      M.enqueue(session, next_fn)
    end
  end)
end

function M.refresh(session, cb)
  status.collect(session.context, function(err, snapshot)
    if not err then
      session.snapshot = snapshot
    end
    if cb then
      cb(err, snapshot)
    end
  end)
end

return M
