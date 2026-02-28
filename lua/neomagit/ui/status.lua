local config = require("neomagit.config")
local state = require("neomagit.state.session")

local M = {}
local ns = vim.api.nvim_create_namespace("neomagit_status")
local highlights_defined = false
local colorscheme_autocmd_set = false

local function ensure_highlights()
  if highlights_defined then
    return
  end

  if not colorscheme_autocmd_set then
    vim.api.nvim_create_autocmd("ColorScheme", {
      callback = function()
        highlights_defined = false
      end,
    })
    colorscheme_autocmd_set = true
  end

  local function source_fg(source_name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = source_name, link = false })
    if ok and type(hl) == "table" then
      return hl.fg
    end
    return nil
  end

  local function set_fg_group(name, source_name, fallback_link, opts)
    opts = opts or {}
    local spec = { default = true }
    local fg = source_fg(source_name)
    if fg then
      spec.fg = fg
      spec.bold = opts.bold or false
      spec.italic = opts.italic or false
      spec.underline = opts.underline or false
      spec.nocombine = true
      vim.api.nvim_set_hl(0, name, spec)
      return
    end
    vim.api.nvim_set_hl(0, name, { default = true, link = fallback_link })
  end

  vim.api.nvim_set_hl(0, "NeomagitTitle", { default = true, link = "Title" })
  vim.api.nvim_set_hl(0, "NeomagitMeta", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "NeomagitSection", { default = true, link = "Keyword" })
  vim.api.nvim_set_hl(0, "NeomagitSectionMarker", { default = true, link = "Special" })
  vim.api.nvim_set_hl(0, "NeomagitSectionCount", { default = true, link = "Number" })
  vim.api.nvim_set_hl(0, "NeomagitSectionTitle", { default = true, link = "Keyword" })
  vim.api.nvim_set_hl(0, "NeomagitHeaderLabel", { default = true, link = "Keyword" })
  vim.api.nvim_set_hl(0, "NeomagitHeaderRef", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "NeomagitHeaderSubject", { default = true, link = "Normal" })
  vim.api.nvim_set_hl(0, "NeomagitHint", { default = true, link = "SpecialComment" })
  vim.api.nvim_set_hl(0, "NeomagitHelp", { default = true, link = "String" })
  vim.api.nvim_set_hl(0, "NeomagitHunk", { default = true, link = "DiffText" })
  vim.api.nvim_set_hl(0, "NeomagitHunkMarker", { default = true, link = "Special" })
  vim.api.nvim_set_hl(0, "NeomagitDiffAdd", { default = true, link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "NeomagitDiffDelete", { default = true, link = "DiffDelete" })
  vim.api.nvim_set_hl(0, "NeomagitDiffContext", { default = true, link = "Normal" })
  vim.api.nvim_set_hl(0, "NeomagitDiffNote", { default = true, link = "Comment" })
  vim.api.nvim_set_hl(0, "NeomagitStash", { default = true, link = "Identifier" })
  vim.api.nvim_set_hl(0, "NeomagitHash", { default = true, link = "Number" })
  vim.api.nvim_set_hl(0, "NeomagitCommit", { default = true, link = "Number" })
  vim.api.nvim_set_hl(0, "NeomagitWorktree", { default = true, link = "Directory" })
  vim.api.nvim_set_hl(0, "NeomagitSubmodule", { default = true, link = "Type" })

  set_fg_group("NeomagitSignStaged", "DiffAdd", "DiffAdd", { bold = true })
  set_fg_group("NeomagitSignUnstaged", "DiffChange", "DiffChange", { bold = true })
  set_fg_group("NeomagitSignUntracked", "Directory", "Directory", { bold = true })
  set_fg_group("NeomagitSignConflicted", "DiagnosticError", "DiagnosticError", { bold = true })

  set_fg_group("NeomagitFileStaged", "DiffAdd", "String")
  set_fg_group("NeomagitFileUnstaged", "DiffChange", "Identifier")
  set_fg_group("NeomagitFileUntracked", "Directory", "Directory")
  set_fg_group("NeomagitFileConflicted", "DiagnosticError", "Error")
  set_fg_group("NeomagitItemStatusStaged", "DiffAdd", "NeomagitFileStaged", { bold = true })
  set_fg_group("NeomagitItemStatusUnstaged", "DiffChange", "NeomagitFileUnstaged", { bold = true })
  set_fg_group("NeomagitItemStatusUntracked", "Directory", "NeomagitFileUntracked", { bold = true })
  set_fg_group("NeomagitItemStatusConflicted", "DiagnosticError", "NeomagitFileConflicted", { bold = true })
  set_fg_group("NeomagitItemPath", "Normal", "Identifier")
  set_fg_group("NeomagitSectionTitle", "Keyword", "Keyword", { bold = true })
  set_fg_group("NeomagitHeaderLabel", "Keyword", "Keyword", { bold = true })
  set_fg_group("NeomagitHeaderRef", "Directory", "Directory", { bold = true })
  set_fg_group("NeomagitHeaderSubject", "Comment", "Comment")

  highlights_defined = true
end

local function notify(msg, level)
  vim.notify("[neomagit] " .. msg, level or vim.log.levels.INFO)
end

local function file_path_group(meta)
  if not meta or meta.kind ~= "file" then
    return nil
  end
  local map = {
    staged = "NeomagitFileStaged",
    unstaged = "NeomagitFileUnstaged",
    untracked = "NeomagitFileUntracked",
    conflicted = "NeomagitFileConflicted",
  }
  return map[meta.section]
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

local function item_status_group(meta)
  if not meta or meta.kind ~= "file" then
    return nil
  end
  local map = {
    staged = "NeomagitItemStatusStaged",
    unstaged = "NeomagitItemStatusUnstaged",
    untracked = "NeomagitItemStatusUntracked",
    conflicted = "NeomagitItemStatusConflicted",
  }
  return map[meta.section]
end

local function add_hl(buf, group, row, start_col, end_col)
  if not group then
    return
  end
  if start_col and end_col and end_col ~= -1 and start_col >= end_col then
    return
  end
  pcall(vim.api.nvim_buf_add_highlight, buf, ns, group, row, start_col or 0, end_col or -1)
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
    local line = lines[lnum] or ""
    local row = lnum - 1

    if meta then
      if meta.kind == "title" then
        add_hl(session.buf, "NeomagitTitle", row, 0, -1)
      elseif meta.kind == "meta" then
        add_hl(session.buf, "NeomagitMeta", row, 0, -1)
      elseif meta.kind == "header" then
        add_hl(session.buf, "NeomagitHeaderLabel", row, 0, meta.label_end)
        if meta.ref_start and meta.ref_end then
          add_hl(session.buf, "NeomagitHeaderRef", row, meta.ref_start, meta.ref_end)
        end
        if meta.subject_start then
          add_hl(session.buf, "NeomagitHeaderSubject", row, meta.subject_start, -1)
        end
      elseif meta.kind == "section" then
        add_hl(session.buf, "NeomagitSection", row, 0, -1)
        if meta.title_start then
          add_hl(session.buf, "NeomagitSectionTitle", row, meta.title_start, meta.title_end or -1)
        end
        if meta.marker_start and meta.marker_end then
          add_hl(session.buf, "NeomagitSectionMarker", row, meta.marker_start, meta.marker_end)
        elseif meta.style ~= "magit" then
          add_hl(session.buf, "NeomagitSectionMarker", row, 0, 3)
        end
        local count_start = line:find("%(%d+%)$")
        if count_start then
          add_hl(session.buf, "NeomagitSectionCount", row, count_start - 1, -1)
        end
      elseif meta.kind == "file" then
        if meta.style == "magit" then
          if meta.status_start and meta.status_end then
            add_hl(session.buf, item_status_group(meta), row, meta.status_start, meta.status_end)
          end
          if meta.path_start then
            add_hl(session.buf, "NeomagitItemPath", row, meta.path_start, -1)
          end
        else
          add_hl(session.buf, file_sign_group(meta), row, 2, 3)
          add_hl(session.buf, file_path_group(meta), row, 4, -1)
        end
      elseif meta.kind == "hunk" then
        if meta.hunk_line_type then
          local offset = meta.style == "magit" and 4 or 6
          local group = "NeomagitDiffContext"
          if meta.hunk_line_type == "+" then
            group = "NeomagitDiffAdd"
          elseif meta.hunk_line_type == "-" then
            group = "NeomagitDiffDelete"
          elseif meta.hunk_line_type == "\\" then
            group = "NeomagitDiffNote"
          end
          add_hl(session.buf, group, row, offset, -1)
        else
          local marker_start = line:find("@@")
          if marker_start then
            local marker_end = line:find("@@", marker_start + 2, true)
            if marker_end then
              add_hl(session.buf, "NeomagitHunkMarker", row, marker_start - 1, marker_end + 1)
            end
          end
          add_hl(session.buf, "NeomagitHunk", row, meta.style == "magit" and 2 or 4, -1)
        end
      elseif meta.kind == "hint" then
        add_hl(session.buf, "NeomagitHint", row, 0, -1)
      elseif meta.kind == "info" then
        add_hl(session.buf, "NeomagitMeta", row, 0, -1)
      elseif meta.kind == "help" then
        add_hl(session.buf, "NeomagitHelp", row, 0, -1)
      elseif meta.kind == "stash" then
        add_hl(session.buf, "NeomagitMeta", row, 0, 5)
        local ref_start, ref_end = line:find("stash@{%d+}")
        if ref_start and ref_end then
          add_hl(session.buf, "NeomagitStash", row, ref_start - 1, ref_end)
        end
      elseif meta.kind == "commit" then
        add_hl(session.buf, "NeomagitMeta", row, 0, 5)
        local hash_start, hash_end = line:find("%x%x%x%x%x%x%x+")
        if hash_start and hash_end then
          add_hl(session.buf, "NeomagitHash", row, hash_start - 1, hash_end)
        end
      elseif meta.kind == "worktree" then
        add_hl(session.buf, "NeomagitMeta", row, 0, 5)
        local bracket_start = line:find("%[", 1, true)
        if bracket_start then
          add_hl(session.buf, "NeomagitWorktree", row, 5, bracket_start - 2)
          add_hl(session.buf, "NeomagitMeta", row, bracket_start - 1, -1)
        else
          add_hl(session.buf, "NeomagitWorktree", row, 5, -1)
        end
      elseif meta.kind == "submodule" then
        add_hl(session.buf, "NeomagitMeta", row, 0, 5)
        add_hl(session.buf, "NeomagitSignUntracked", row, 5, 6)
        add_hl(session.buf, "NeomagitSubmodule", row, 7, -1)
      end
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

local function hunk_line_type(line)
  if not line or line == "" then
    return " "
  end
  return line:sub(1, 1)
end

local function render_section_classic(session, lines, line_map, key, title, entries, hunk_map, sign)
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
        for line_idx = 2, #(hunk.lines or {}) do
          local hline = hunk.lines[line_idx]
          push(lines, line_map, string.format("      %s", hline), {
            kind = "hunk",
            section = key,
            path = entry.path,
            hunk_index = idx,
            hunk = hunk,
            hunk_line = line_idx,
            hunk_line_type = hunk_line_type(hline),
          })
        end
      end
    end
  end
end

local function render_header_classic(session, lines, line_map, key, title, count)
  local folded = session.ui.folded[key]
  local icon = folded and "+" or "-"
  push(lines, line_map, string.format("[%s] %s (%d)", icon, title, count), {
    kind = "section",
    section = key,
  })
  return folded
end

local status_words = {
  M = "modified",
  A = "new file",
  D = "deleted",
  R = "renamed",
  C = "copied",
  U = "unmerged",
  T = "typechange",
}

local function file_status_word(section, entry)
  if section == "untracked" then
    return "untracked"
  end
  if section == "conflicted" then
    return "unmerged"
  end
  local code = tostring(entry and entry.code or "")
  local letter = code:sub(1, 1)
  return status_words[letter] or "modified"
end

local function render_section_header_magit(session, lines, line_map, key, title, count)
  local folded = session.ui.folded[key]
  local marker = folded and "[+] " or ""
  local text = string.format("%s%s (%d)", marker, title, count)
  push(lines, line_map, text, {
    kind = "section",
    section = key,
    style = "magit",
    marker_start = folded and 0 or nil,
    marker_end = folded and #marker or nil,
    title_start = folded and #marker or 0,
    title_end = (folded and #marker or 0) + #title,
  })
  return folded
end

local function render_section_magit(session, lines, line_map, key, title, entries, hunk_map, status_width)
  local folded = render_section_header_magit(session, lines, line_map, key, title, #entries)
  if folded then
    return
  end

  for _, entry in ipairs(sorted_entries(entries)) do
    local status = file_status_word(key, entry)
    local text = string.format("%-" .. status_width .. "s  %s", status, entry.path)
    push(lines, line_map, text, {
      kind = "file",
      style = "magit",
      section = key,
      path = entry.path,
      entry = entry,
      status_start = 0,
      status_end = status_width,
      path_start = status_width + 2,
    })
    local file_hunks = hunk_map and hunk_map[entry.path]
    if file_hunks then
      for idx, hunk in ipairs(file_hunks.hunks or {}) do
        push(lines, line_map, string.format("  %s", hunk.header), {
          kind = "hunk",
          style = "magit",
          section = key,
          path = entry.path,
          hunk_index = idx,
          hunk = hunk,
        })
        for line_idx = 2, #(hunk.lines or {}) do
          local hline = hunk.lines[line_idx]
          push(lines, line_map, string.format("    %s", hline), {
            kind = "hunk",
            style = "magit",
            section = key,
            path = entry.path,
            hunk_index = idx,
            hunk = hunk,
            hunk_line = line_idx,
            hunk_line_type = hunk_line_type(hline),
          })
        end
      end
    end
  end
end

local function render_header_magit(session, lines, line_map, key, title, count)
  return render_section_header_magit(session, lines, line_map, key, title, count)
end

local function push_header_line(lines, line_map, label, ref, subject, sep)
  local label_text = string.format("%-7s", label .. ":")
  local text = label_text
  local meta = {
    kind = "header",
    label_end = #label_text,
  }

  if ref and ref ~= "" then
    meta.ref_start = #text
    text = text .. ref
    meta.ref_end = #text
  end

  if subject and subject ~= "" then
    local separator = sep or " "
    text = text .. separator
    meta.subject_start = #text
    text = text .. subject
  end

  push(lines, line_map, text, meta)
end

local function ensure_buffer(session)
  if session.buf and vim.api.nvim_buf_is_valid(session.buf) then
    return session.buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buflisted = false
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

local function render_tail_sections_classic(session, lines, line_map, snapshot)
  push(lines, line_map, "", { kind = "blank" })
  if not render_header_classic(session, lines, line_map, "stashes", "Stashes", #(snapshot.stashes or {})) then
    for idx, stash in ipairs(snapshot.stashes or {}) do
      push(lines, line_map, string.format("  %d. %s %s", idx, stash.ref, stash.subject), {
        kind = "stash",
        stash = stash,
        index = idx,
      })
    end
  end

  if not render_header_classic(session, lines, line_map, "recent", "Recent Commits", #(snapshot.recent or {})) then
    for idx, c in ipairs(snapshot.recent or {}) do
      push(lines, line_map, string.format("  %d. %s %s", idx, c.hash, c.subject), {
        kind = "commit",
        commit = c,
        index = idx,
      })
    end
  end

  if not render_header_classic(session, lines, line_map, "worktrees", "Worktrees", #(snapshot.worktrees or {})) then
    for idx, wt in ipairs(snapshot.worktrees or {}) do
      push(lines, line_map, string.format("  %d. %s [%s]", idx, wt.path, wt.branch or (wt.head or "detached")), {
        kind = "worktree",
        worktree = wt,
        index = idx,
      })
    end
  end

  if not render_header_classic(session, lines, line_map, "submodules", "Submodules", #(snapshot.submodules or {})) then
    for idx, sm in ipairs(snapshot.submodules or {}) do
      push(lines, line_map, string.format("  %d. %s %s %s", idx, sm.state, sm.path, sm.desc or ""), {
        kind = "submodule",
        submodule = sm,
        index = idx,
      })
    end
  end
end

local function render_tail_sections_magit(session, lines, line_map, snapshot)
  push(lines, line_map, "", { kind = "blank" })
  if not render_header_magit(session, lines, line_map, "stashes", "Stashes", #(snapshot.stashes or {})) then
    for idx, stash in ipairs(snapshot.stashes or {}) do
      push(lines, line_map, string.format("  %d. %s %s", idx, stash.ref, stash.subject), {
        kind = "stash",
        stash = stash,
        index = idx,
      })
    end
  end

  if not render_header_magit(session, lines, line_map, "recent", "Recent commits", #(snapshot.recent or {})) then
    for idx, c in ipairs(snapshot.recent or {}) do
      push(lines, line_map, string.format("  %d. %s %s", idx, c.hash, c.subject), {
        kind = "commit",
        commit = c,
        index = idx,
      })
    end
  end

  if not render_header_magit(session, lines, line_map, "worktrees", "Worktrees", #(snapshot.worktrees or {})) then
    for idx, wt in ipairs(snapshot.worktrees or {}) do
      push(lines, line_map, string.format("  %d. %s [%s]", idx, wt.path, wt.branch or (wt.head or "detached")), {
        kind = "worktree",
        worktree = wt,
        index = idx,
      })
    end
  end

  if not render_header_magit(session, lines, line_map, "submodules", "Submodules", #(snapshot.submodules or {})) then
    for idx, sm in ipairs(snapshot.submodules or {}) do
      push(lines, line_map, string.format("  %d. %s %s %s", idx, sm.state, sm.path, sm.desc or ""), {
        kind = "submodule",
        submodule = sm,
        index = idx,
      })
    end
  end
end

local function render_help(lines, line_map, help_open)
  push(lines, line_map, "", { kind = "blank" })
  push(lines, line_map, "Press ? for keymap help.", { kind = "hint" })
  if help_open then
    push(lines, line_map, "q close  g refresh  <Tab> fold/unfold  ? toggle help", { kind = "help" })
    push(lines, line_map, "s stage  u unstage  x discard", { kind = "help" })
    push(lines, line_map, "c commit  b branch  z stash", { kind = "help" })
    push(lines, line_map, "f fetch popup  p push/pull popup", { kind = "help" })
    push(lines, line_map, "r rebase  A cherry-pick  v revert  R reset", { kind = "help" })
    push(lines, line_map, "l open full log", { kind = "help" })
  end
end

local function render_snapshot_classic(session, lines, line_map, snapshot)
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
  render_section_classic(
    session,
    lines,
    line_map,
    "conflicted",
    "Conflicted",
    s.conflicted or {},
    nil,
    config.values.signs.conflicted
  )
  render_section_classic(
    session,
    lines,
    line_map,
    "staged",
    "Staged",
    s.staged or {},
    snapshot.hunks and snapshot.hunks.staged,
    config.values.signs.staged
  )
  render_section_classic(
    session,
    lines,
    line_map,
    "unstaged",
    "Unstaged",
    s.unstaged or {},
    snapshot.hunks and snapshot.hunks.unstaged,
    config.values.signs.unstaged
  )
  render_section_classic(
    session,
    lines,
    line_map,
    "untracked",
    "Untracked",
    s.untracked or {},
    nil,
    config.values.signs.untracked
  )

  render_tail_sections_classic(session, lines, line_map, snapshot)
  render_help(lines, line_map, session.ui.help_open)
end

local function render_snapshot_magit(session, lines, line_map, snapshot)
  local magit_opts = config.values.ui.magit or {}
  local branch = snapshot.branch or {}
  local header = snapshot.header or {}
  local head = header.head or {}
  local merge = header.merge or {}
  local push_head = header.push or {}
  local show_header = magit_opts.show_header ~= false

  if show_header then
    local head_ref = head.ref or (branch.detached and "HEAD" or branch.head or "HEAD")
    push_header_line(lines, line_map, "Head", head_ref, head.subject, " ")

    local merge_ref = merge.ref or branch.upstream
    if merge_ref and merge_ref ~= "" then
      push_header_line(lines, line_map, "Merge", merge_ref, merge.subject, " ; ")
    end

    if push_head.ref and push_head.ref ~= "" then
      push_header_line(lines, line_map, "Push", push_head.ref, push_head.subject, " ; ")
    end

    if magit_opts.show_tag_line ~= false then
      local tag = header.tag
      if tag and tag.name and tag.name ~= "" then
        local suffix = tag.short_hash and tag.short_hash ~= "" and ("(" .. tag.short_hash .. ")") or ""
        push_header_line(lines, line_map, "Tag", tag.name, suffix, " ")
      else
        push_header_line(lines, line_map, "Tag", "none", nil)
      end
    end

    if snapshot.operation and snapshot.operation ~= "" then
      push_header_line(lines, line_map, "Op", snapshot.operation, nil)
    end

    push(lines, line_map, "", { kind = "blank" })
  end

  local s = snapshot.sections or {}
  local status_width = 12
  local section_specs = {
    { key = "unstaged", title = "Unstaged changes", entries = s.unstaged or {}, hunks = snapshot.hunks and snapshot.hunks.unstaged },
    { key = "untracked", title = "Untracked files", entries = s.untracked or {}, hunks = nil },
    { key = "staged", title = "Staged changes", entries = s.staged or {}, hunks = snapshot.hunks and snapshot.hunks.staged },
    { key = "conflicted", title = "Unmerged paths", entries = s.conflicted or {}, hunks = nil },
  }

  for idx, spec in ipairs(section_specs) do
    render_section_magit(session, lines, line_map, spec.key, spec.title, spec.entries, spec.hunks, status_width)
    if magit_opts.compact_sections ~= true and idx < #section_specs then
      push(lines, line_map, "", { kind = "blank" })
    end
  end

  render_tail_sections_magit(session, lines, line_map, snapshot)
  render_help(lines, line_map, session.ui.help_open)
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
    local style = (config.values.ui and config.values.ui.style) or "magit"
    if style == "classic" then
      render_snapshot_classic(session, lines, line_map, snapshot)
    else
      render_snapshot_magit(session, lines, line_map, snapshot)
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
  end, "Fetch popup")
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
  local win
  if config.values.ui.float then
    local width = math.min(vim.o.columns - 6, config.values.ui.max_width)
    local height = math.min(vim.o.lines - 6, vim.o.lines - 6)
    win = vim.api.nvim_open_win(buf, true, {
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
    win = vim.api.nvim_get_current_win()
  end

  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].list = false
    vim.wo[win].spell = false
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
  end

  attach_keymaps(buf)
  M.render(session)
  M.refresh(session)
end

return M
