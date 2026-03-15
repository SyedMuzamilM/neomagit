package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

local parsers = require("neomagit.git.parsers")

local function assert_eq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. string.format(" (expected=%s, actual=%s)", tostring(expected), tostring(actual)))
  end
end

local function test_parse_status()
  local input = table.concat({
    "## main...origin/main [ahead 2, behind 1]",
    " M lua/file_a.lua",
    "M  lua/file_b.lua",
    "MM lua/file_c.lua",
    "R  old_name.lua -> new_name.lua",
    "?? new_file.lua",
  }, "\n")

  local out = parsers.parse_status_porcelain(input)
  assert_eq(out.branch.head, "main", "branch head")
  assert_eq(out.branch.upstream, "origin/main", "branch upstream")
  assert_eq(out.branch.ahead, 2, "ahead count")
  assert_eq(out.branch.behind, 1, "behind count")
  assert_eq(#out.sections.unstaged, 2, "unstaged files")
  assert_eq(#out.sections.staged, 3, "staged files")
  assert_eq(#out.sections.untracked, 1, "untracked files")
end

local function test_parse_diff()
  local input = table.concat({
    "diff --git a/lua/test.lua b/lua/test.lua",
    "index e69de29..4b825dc 100644",
    "--- a/lua/test.lua",
    "+++ b/lua/test.lua",
    "@@ -1,3 +1,4 @@",
    " local a = 1",
    "+print('hello')",
    " local b = 2",
    " local c = 3",
    "@@ -5,3 +6,3 @@",
    " keep_before()",
    "-old",
    "+new",
    " keep_after()",
  }, "\n")

  local files = parsers.parse_unified_diff(input)
  local file = files["lua/test.lua"]
  assert_eq(type(file), "table", "file parsed")
  assert_eq(#file.hunks, 2, "hunk count")
  assert_eq(file.hunks[1].meta.new_start, 1, "first hunk new start")
  assert_eq(file.hunks[1].lines[2], " local a = 1", "leading context line preserved")
  assert_eq(file.hunks[2].lines[#file.hunks[2].lines], " keep_after()", "trailing context line preserved")
end

local function test_parse_stash()
  local input = "stash@{0}: WIP on main: deadbee message\nstash@{1}: On main: second"
  local out = parsers.parse_stash_list(input)
  assert_eq(#out, 2, "stash count")
  assert_eq(out[1].ref, "stash@{0}", "stash ref")
end

test_parse_status()
test_parse_diff()
test_parse_stash()

print("parser tests passed")
