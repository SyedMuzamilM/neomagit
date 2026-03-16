package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

if not _G.vim then
  local function deepcopy(value)
    if type(value) ~= "table" then
      return value
    end
    local out = {}
    for k, v in pairs(value) do
      out[deepcopy(k)] = deepcopy(v)
    end
    return out
  end

  _G.vim = {
    deepcopy = deepcopy,
    api = {
      nvim_buf_is_valid = function(buf)
        return type(buf) == "number" and buf > 0
      end,
      nvim_create_namespace = function()
        return 1
      end,
    },
    loop = {
      cwd = function()
        return "."
      end,
      fs_stat = function()
        return nil
      end,
    },
    log = {
      levels = {
        INFO = 1,
        WARN = 2,
        ERROR = 3,
      },
    },
  }
end

local status = require("neomagit.git.status")
local state = require("neomagit.state.session")
local actions = require("neomagit.actions.core")
local ui_status = require("neomagit.ui.status")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. string.format(" (expected=%s, actual=%s)", tostring(expected), tostring(actual)))
  end
end

local function test_build_header_full()
  local header = status._build_header({
    detached = false,
    head = "master",
    upstream = "origin/master",
  }, {
    head_subject = { stdout = "Prevent SelectionNotify etc from reaching GTK 3\n" },
    upstream_ref = { stdout = "origin/master\n" },
    upstream_subject = { stdout = "Fix documentation of 'loaddefs-generate'\n" },
    push_ref = { stdout = "origin/master\n" },
    push_subject = { stdout = "Fix documentation of 'loaddefs-generate'\n" },
    head_tag = { stdout = "emacs-28.1.91\n" },
    head_short = { stdout = "158209\n" },
  })

  assert_eq(header.head.ref, "master", "head ref")
  assert_eq(header.head.subject, "Prevent SelectionNotify etc from reaching GTK 3", "head subject")
  assert_eq(header.merge.ref, "origin/master", "merge ref")
  assert_eq(header.push.ref, "origin/master", "push ref")
  assert_eq(header.tag.name, "emacs-28.1.91", "tag name")
  assert_eq(header.tag.short_hash, "158209", "tag short hash")
end

local function test_build_header_fallbacks()
  local header = status._build_header({
    detached = true,
    head = "ignored",
    upstream = "origin/main",
  }, {
    head_subject = { stdout = "" },
    upstream_ref = { stdout = "" },
    upstream_subject = { stdout = "" },
    push_ref = { stdout = "" },
    push_subject = { stdout = "" },
    head_tag = { stdout = "" },
    head_short = { stdout = "abc1234\n" },
  })

  assert_eq(header.head.ref, "HEAD", "detached head ref")
  assert_eq(header.merge.ref, "origin/main", "upstream fallback")
  assert_eq(header.push.ref, "", "empty push ref")
  assert_eq(header.tag, nil, "no tag when describe fails")
end

local function test_build_tracking_sections()
  local sections = status._build_tracking_sections({
    upstream = "origin/main",
  }, {
    merge = { ref = "origin/main" },
    push = { ref = "fork/main" },
  }, {
    unpulled_upstream = { ok = true, stdout = "a1b2c3d upstream behind\n" },
    unmerged_upstream = { ok = true, stdout = "b2c3d4e local ahead\n" },
    unpulled_push = { ok = true, stdout = "c3d4e5f push behind\n" },
    unmerged_push = { ok = true, stdout = "d4e5f6a push ahead\n" },
  })

  assert_eq(#sections, 4, "tracking section count")
  assert_eq(sections[1].title, "Unpulled from origin/main", "upstream unpulled title")
  assert_eq(sections[2].title, "Unmerged into origin/main", "upstream unmerged title")
  assert_eq(sections[3].title, "Unpulled from fork/main", "push unpulled title")
  assert_eq(sections[4].title, "Unmerged into fork/main", "push unmerged title")
  assert_eq(sections[1].commits[1].hash, "a1b2c3d", "first unpulled hash")
end

local function test_build_tracking_sections_dedup_push_remote()
  local sections = status._build_tracking_sections({
    upstream = "origin/main",
  }, {
    merge = { ref = "origin/main" },
    push = { ref = "origin/main" },
  }, {
    unpulled_upstream = { ok = true, stdout = "a1b2c3d upstream behind\n" },
    unmerged_upstream = { ok = true, stdout = "b2c3d4e local ahead\n" },
    unpulled_push = { ok = true, stdout = "c3d4e5f push behind\n" },
    unmerged_push = { ok = true, stdout = "d4e5f6a push ahead\n" },
  })

  assert_eq(#sections, 2, "push tracking deduped when same as upstream")
end

local function test_should_auto_refresh_only_active_valid_status_buffer()
  local session = {
    buf = 5,
    ui = {
      auto_refresh = {
        running = false,
        last_ns = 0,
      },
    },
  }

  assert_eq(ui_status._should_auto_refresh(session, 5, 1), true, "refreshes active neomagit buffer")
  assert_eq(ui_status._should_auto_refresh(session, 6, 1), false, "skips other buffers")
  assert_eq(ui_status._should_auto_refresh(nil, 5, 1), false, "skips missing session")
  assert_eq(ui_status._should_auto_refresh({ buf = -1, ui = session.ui }, -1, 1), false, "skips invalid buffers")
end

local function test_should_auto_refresh_debounces_while_running_or_recent()
  local session = {
    buf = 7,
    ui = {
      auto_refresh = {
        running = true,
        last_ns = 0,
      },
    },
  }

  assert_eq(ui_status._should_auto_refresh(session, 7, 1), false, "skips while refresh is running")

  session.ui.auto_refresh.running = false
  session.ui.auto_refresh.last_ns = 100
  assert_eq(ui_status._should_auto_refresh(session, 7, 100 + 50 * 1000 * 1000), false, "skips within debounce window")
  assert_eq(ui_status._should_auto_refresh(session, 7, 100 + 200 * 1000 * 1000), true, "allows refresh after debounce")
end

local function test_default_modified_sections_start_folded()
  local session = state.get_or_create({ root = "__test__/fold-defaults" })

  assert_eq(session.ui.folded.staged, true, "staged section starts folded")
  assert_eq(session.ui.folded.unstaged, true, "unstaged section starts folded")
  assert_eq(session.ui.folded.untracked, false, "untracked section stays open")
  assert_eq(type(session.ui.file_folded), "table", "file fold state is tracked")
end

local function test_hunk_target_line_tracks_new_file_lines()
  local line = actions._hunk_target_line({
    hunk = {
      meta = { new_start = 12 },
      lines = {
        "@@ -10,2 +12,3 @@",
        " context",
        "-removed",
        "+added",
        " trailing",
      },
    },
    hunk_line = 4,
  })

  assert_eq(line, 13, "added line maps to current file line")
end

test_build_header_full()
test_build_header_fallbacks()
test_build_tracking_sections()
test_build_tracking_sections_dedup_push_remote()
test_should_auto_refresh_only_active_valid_status_buffer()
test_should_auto_refresh_debounces_while_running_or_recent()
test_default_modified_sections_start_folded()
test_hunk_target_line_tracks_new_file_lines()

print("status tests passed")
