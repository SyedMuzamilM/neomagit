local config = require("neomagit.config")
local state = require("neomagit.state.session")

local M = {}
local ns = vim.api.nvim_create_namespace("neomagit_status")
local highlights_defined = false

local function ensure_highlights()
  if highlights_defined then
    return
  end

  vim.api.nvim_set_hl(0, "NeomagitTitle", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "NeomagitMeta", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "NeomagitSection", { default = true, link = "Function" })
  vim.api.nvim_set_hl(0, "NeomagitHint", { default = true, link = "SpecialComment" })
  vim.api.nvim_set_hl(0, "NeomagitHelp", { default = true, link = "String" })
  vim.api.nvim_set_hl(0, "NeomagitHunk", { default = true, link = "DiffText" })
  vim.api.nvim_set_hl(0, "NeomagitStash", { default = true, link = "Identifier" })
  vim.api.nvim_set_hl(0, "NeomagitCommit", { default = true, link = "Number" })
  vim.api.nvim_set_hl(0, "NeomagitWorktree", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "NeomagitSubmodule", { default = true, link = "Type" })

  vim.api.nvim_set_hl(0, "NeomagitSignStaged", { default = true, link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "NeomagitSignUnstaged", { default = true, link = "DiffChange" })
  vim.api.nvim_set_hl(0, "NeomagitSignUntracked", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "NeomagitSignConflicted", { default = true, link = "DiagnosticError" })

  vim.api.nvim_set_hl(0, "NeomagitFileStaged", { default = true, link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "NeomagitFileUnstaged", { default = true, link = "DiffChange" })
  vim.api.nvim_set_hl(0, "NeomagitFileUntracked", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "NeomagitFileConflicted", { default = true, link = "DiagnosticError" })

  highlights_defined = true
end

local function notify(msg, level)
  vim.notify("[neomagit] " .. msg, level or vim.log.levels.INFO)
end

local function line_group(meta)
  if not meta then
    return nil
  end

  if meta.kind == "title" then
    return "NeomagitTitle"
  end
  if meta.kind == "meta" then
    return "NeomagitMeta"
  end
  if meta.kind == "section" then
    return "NeomagitSection"
  end
  if meta.kind == "hint" then
    return "NeomagitHint"
  end
  if meta.kind == "help" then
    return "NeomagitHelp"
  end
  if meta.kind == "hunk" then
    return "NeomagitHunk"
  end
  if meta.kind == "stash" then
    return "NeomagitStash"
  end
  if meta.kind == "commit" then
    return "NeomagitCommit"
  end
  if meta.kind == "worktree" then
    return "NeomagitWorktree"
  end
  if meta.kind == "submodule" then
    return "NeomagitSubmodule"
  end
  if meta.kind == "file" then
    local map = {
      staged = "NeomagitFileStaged",
      unstaged = "NeomagitFileUnstaged",
      untracked = "NeomagitFileUntracked",
      conflicted = "NeomagitFileConflicted",
    }
    return map[meta.section]
  end

  return nil
end

local function file_sign_group(meta)
  if not meta or meta.kind ~= "file" then
    return nil
  end
  local map = {
    staged = "NeomagitSignStaged",
    unstaged = "NeomagitSignUnstaged",
    untracked = "NeomagitSignUntracked",
    conflicted = "NeomagitSignConflicted",
  }
  return map[meta.section]
end

local function apply_highlights(session, lines)
  if config.values.ui.highlights == false then
    vim.api.nvim_buf_clear_namespace(session.buf, ns, 0, -1)
    return
  end

  ensure_highlights()
  vim.api.nvim_buf_clear_namespace(session.buf, ns, 0, -1)

  for lnum = 1, #lines do
    local meta = session.line_map[lnum]
    local group = line_group(meta)
    if group then
      vim.api.nvim_buf_add_highlight(session.buf, ns, group, lnum - 1, 0, -1)
    end

    if meta and meta.kind == "section" then
      vim.api.nvim_buf_add_highlight(session.buf, ns, "NeomagitMeta", lnum - 1, 0, 3)
    end

    local sign_group = file_sign_group(meta)
    if sign_group then
      vim.api.nvim_buf_add_highlight(session.buf, ns, sign_group, lnum - 1, 2, 3)
    end
  end
end

local function push(lines, line_map, text, meta)
  table.insert(lines, text)
  line_map[#lines] = meta
end

local function sorted_entries(entries)
  local list = {}
  for _, item in ipairs(entries or {}) do
    table.insert(list, item)
  end
  table.sort(list, function(a, b)
    return (a.path or "") < (b.path or "")
  end)
  return list
end

local function render_section(session, lines, line_map, key, title, entries, hunk_map, sign)
  local folded = session.ui.folded[key]
  local icon = folded and "+" or "-"
  push(lines, line_map, string.format("[%s] %s (%d)", icon, title, #entries), {
    kind = "section",
    section = key,
  })

  if folded then
    return
  end

  for _, entry in ipairs(sorted_entries(entries)) do
    push(lines, line_map, string.format("  %s %s", sign or entry.code or " ", entry.path), {
      kind = "file",
      section = key,
      path = entry.path,
      entry = entry,
    })
    local file_hunks = hunk_map and hunk_map[entry.path]
    if file_hunks then
      for idx, hunk in ipairs(file_hunks.hunks or {}) do
        push(lines, line_map, string.format("    %s", hunk.header), {
          kind = "hunk",
          section = key,
          path = entry.path,
          hunk_index = idx,
          hunk = hunk,
        })
      end
    end
  end
end

local function render_header(session, lines, line_map, key, title, count)
  local folded = session.ui.folded[key]
  local icon = folded and "+" or "-"
  push(lines, line_map, string.format("[%s] %s (%d)", icon, title, count), {
    kind = "section",
    section = key,
  })
  return folded
end

local function ensure_buffer(session)
  if session.buf and vim.api.nvim_buf_is_valid(session.buf) then
    return session.buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "neomagit"
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  pcall(vim.api.nvim_buf_set_name, buf, "Neomagit://" .. session.context.root)

  state.bind_buffer(session, buf)
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
      state.unbind_buffer(buf)
      if session.buf == buf then
        session.buf = nil
      end
    end,
  })

  return buf
end

local function current_meta(session)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return session.line_map[row]
end

function M.cursor_meta(session)
  session = session or state.current()
  if not session then
    return nil
  end
  return current_meta(session)
end

function M.toggle_help(session)
  session = session or state.current()
  if not session then
    return
  end
  session.ui.help_open = not session.ui.help_open
  M.render(session)
end

function M.toggle_fold_under_cursor(session)
  session = session or state.current()
  if not session then
    return
  end
  local meta = current_meta(session)
  if meta and meta.kind == "section" then
    session.ui.folded[meta.section] = not session.ui.folded[meta.section]
    M.render(session)
  end
end

function M.render(session)
  if not session or not session.buf or not vim.api.nvim_buf_is_valid(session.buf) then
    return
  end

  local snapshot = session.snapshot
  local lines = {}
  local line_map = {}

  if not snapshot then
    push(lines, line_map, "Neomagit", { kind = "title" })
    push(lines, line_map, "", { kind = "blank" })
    push(lines, line_map, "Loading...", { kind = "info" })
  else
    local branch = snapshot.branch or {}
    local ahead = tonumber(branch.ahead or 0)
    local behind = tonumber(branch.behind or 0)
    local upstream = branch.upstream and (" -> " .. branch.upstream) or ""
    local head = branch.detached and "DETACHED" or (branch.head or "HEAD")

    push(lines, line_map, "Neomagit", { kind = "title" })
    push(lines, line_map, "Repo: " .. session.context.root, { kind = "meta" })
    push(lines, line_map, string.format("Branch: %s%s [ahead %d, behind %d]", head, upstream, ahead, behind), {
      kind = "meta",
    })
    if snapshot.operation then
      push(lines, line_map, "Operation: " .. snapshot.operation, { kind = "meta" })
    end
    push(lines, line_map, "", { kind = "blank" })

    local s = snapshot.sections or {}
    render_section(
      session,
      lines,
      line_map,
      "conflicted",
      "Conflicted",
      s.conflicted or {},
      nil,
      config.values.signs.conflicted
    )
    render_section(
      session,
      lines,
      line_map,
      "staged",
      "Staged",
      s.staged or {},
      snapshot.hunks and snapshot.hunks.staged,
      config.values.signs.staged
    )
    render_section(
      session,
      lines,
      line_map,
      "unstaged",
      "Unstaged",
      s.unstaged or {},
      snapshot.hunks and snapshot.hunks.unstaged,
      config.values.signs.unstaged
    )
    render_section(
      session,
      lines,
      line_map,
      "untracked",
      "Untracked",
      s.untracked or {},
      nil,
      config.values.signs.untracked
    )

    push(lines, line_map, "", { kind = "blank" })
    if not render_header(session, lines, line_map, "stashes", "Stashes", #(snapshot.stashes or {})) then
      for idx, stash in ipairs(snapshot.stashes or {}) do
        push(lines, line_map, string.format("  %d. %s %s", idx, stash.ref, stash.subject), {
          kind = "stash",
          stash = stash,
          index = idx,
        })
      end
    end

    if not render_header(session, lines, line_map, "recent", "Recent Commits", #(snapshot.recent or {})) then
      for idx, c in ipairs(snapshot.recent or {}) do
        push(lines, line_map, string.format("  %d. %s %s", idx, c.hash, c.subject), {
          kind = "commit",
          commit = c,
          index = idx,
        })
      end
    end

    if not render_header(session, lines, line_map, "worktrees", "Worktrees", #(snapshot.worktrees or {})) then
      for idx, wt in ipairs(snapshot.worktrees or {}) do
        push(lines, line_map, string.format("  %d. %s [%s]", idx, wt.path, wt.branch or (wt.head or "detached")), {
          kind = "worktree",
          worktree = wt,
          index = idx,
        })
      end
    end

    if not render_header(session, lines, line_map, "submodules", "Submodules", #(snapshot.submodules or {})) then
      for idx, sm in ipairs(snapshot.submodules or {}) do
        push(lines, line_map, string.format("  %d. %s %s %s", idx, sm.state, sm.path, sm.desc or ""), {
          kind = "submodule",
          submodule = sm,
          index = idx,
        })
      end
    end

    push(lines, line_map, "", { kind = "blank" })
    push(lines, line_map, "Press ? for keymap help.", { kind = "hint" })
    if session.ui.help_open then
      push(lines, line_map, "q close  g refresh  <Tab> fold/unfold  ? toggle help", { kind = "help" })
      push(lines, line_map, "s stage  u unstage  x discard", { kind = "help" })
      push(lines, line_map, "c commit  b branch  z stash", { kind = "help" })
      push(lines, line_map, "f fetch  p push/pull", { kind = "help" })
      push(lines, line_map, "r rebase  A cherry-pick  v revert  R reset", { kind = "help" })
      push(lines, line_map, "l open full log", { kind = "help" })
    end
  end

  vim.bo[session.buf].modifiable = true
  vim.bo[session.buf].readonly = false
  vim.api.nvim_buf_set_lines(session.buf, 0, -1, false, lines)
  vim.bo[session.buf].modifiable = false
  vim.bo[session.buf].readonly = true
  session.line_map = line_map
  apply_highlights(session, lines)
end

function M.refresh(session)
  session = session or state.current()
  if not session then
    notify("No active neomagit session", vim.log.levels.WARN)
    return
  end

  state.refresh(session, function(err)
    if err then
      notify(err, vim.log.levels.ERROR)
      return
    end
    M.render(session)
  end)
end

local function attach_keymaps(buf)
  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = desc })
  end

  map("q", function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end, "Close neomagit")
  map("g", function()
    M.refresh()
  end, "Refresh status")
  map("<Tab>", function()
    M.toggle_fold_under_cursor()
  end, "Toggle section fold")
  map("?", function()
    M.toggle_help()
  end, "Toggle help")

  map("s", function()
    require("neomagit.actions.core").stage_from_cursor()
  end, "Stage item")
  map("u", function()
    require("neomagit.actions.core").unstage_from_cursor()
  end, "Unstage item")
  map("x", function()
    require("neomagit.actions.core").discard_from_cursor()
  end, "Discard item")
  map("c", function()
    require("neomagit.actions.core").commit_popup()
  end, "Commit popup")
  map("b", function()
    require("neomagit.actions.core").branch_popup()
  end, "Branch popup")
  map("z", function()
    require("neomagit.actions.core").stash_popup()
  end, "Stash popup")
  map("f", function()
    require("neomagit.actions.core").fetch()
  end, "Fetch")
  map("p", function()
    require("neomagit.actions.core").push_pull_popup()
  end, "Push/Pull popup")
  map("r", function()
    require("neomagit.actions.core").rebase_popup()
  end, "Rebase popup")
  map("A", function()
    require("neomagit.actions.core").cherry_pick_popup()
  end, "Cherry-pick popup")
  map("v", function()
    require("neomagit.actions.core").revert_popup()
  end, "Revert popup")
  map("R", function()
    require("neomagit.actions.core").reset_popup()
  end, "Reset popup")
  map("l", function()
    require("neomagit.actions.core").show_log()
  end, "Show log")
end

function M.open(session)
  local buf = ensure_buffer(session)
  if config.values.ui.float then
    local width = math.min(vim.o.columns - 6, config.values.ui.max_width)
    local height = math.min(vim.o.lines - 6, vim.o.lines - 6)
    vim.api.nvim_open_win(buf, true, {
      relative = "editor",
      row = 3,
      col = math.floor((vim.o.columns - width) / 2),
      width = width,
      height = height,
      border = config.values.ui.border,
      style = "minimal",
    })
  else
    vim.api.nvim_set_current_buf(buf)
  end
  attach_keymaps(buf)
  M.render(session)
  M.refresh(session)
end

return M
