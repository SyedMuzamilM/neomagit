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
    loop = {
      cwd = function()
        return "."
      end,
      fs_stat = function()
        return nil
      end,
    },
  }
end

local status = require("neomagit.git.status")

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

test_build_header_full()
test_build_header_fallbacks()

print("status tests passed")
