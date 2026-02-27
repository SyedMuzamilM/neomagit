local config = require("neomagit.config")

local M = {}

local function normalize_cwd(context)
  if type(context) == "table" then
    return context.cwd or context.root or vim.loop.cwd()
  end
  return context or vim.loop.cwd()
end

local function finalize(cb, result)
  vim.schedule(function()
    cb(result)
  end)
end

local function as_job_result(code, stdout, stderr)
  return {
    code = code or 1,
    stdout = stdout or "",
    stderr = stderr or "",
    ok = code == 0,
  }
end

function M.run(context, args, opts, cb)
  opts = opts or {}
  cb = cb or function() end

  local cwd = normalize_cwd(context)
  local cmd = { config.values.git.bin }
  vim.list_extend(cmd, args or {})

  if vim.system then
    local stdin = opts.stdin
    local timeout = opts.timeout_ms or config.values.git.timeout_ms
    vim.system(cmd, { cwd = cwd, text = true, stdin = stdin, timeout = timeout }, function(out)
      finalize(cb, as_job_result(out.code, out.stdout, out.stderr))
    end)
    return
  end

  local stdout_chunks = {}
  local stderr_chunks = {}
  local job = vim.fn.jobstart(cmd, {
    cwd = cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        table.insert(stdout_chunks, table.concat(data, "\n"))
      end
    end,
    on_stderr = function(_, data)
      if data then
        table.insert(stderr_chunks, table.concat(data, "\n"))
      end
    end,
    on_exit = function(_, code)
      finalize(cb, as_job_result(code, table.concat(stdout_chunks, "\n"), table.concat(stderr_chunks, "\n")))
    end,
  })

  if job <= 0 then
    finalize(cb, as_job_result(1, "", "failed to start git job"))
    return
  end

  if opts.stdin and opts.stdin ~= "" then
    vim.fn.chansend(job, opts.stdin)
  end
  vim.fn.chanclose(job, "stdin")
end

function M.run_sync(context, args, opts)
  opts = opts or {}
  local cwd = normalize_cwd(context)
  local cmd = { config.values.git.bin }
  vim.list_extend(cmd, args or {})

  if vim.system then
    local out = vim.system(cmd, {
      cwd = cwd,
      text = true,
      stdin = opts.stdin,
      timeout = opts.timeout_ms or config.values.git.timeout_ms,
    }):wait()
    return as_job_result(out.code, out.stdout, out.stderr)
  end

  local old_cwd = vim.loop.cwd()
  local changed, chdir_err = pcall(vim.fn.chdir, cwd)
  if not changed then
    return as_job_result(1, "", "failed to chdir for sync git command: " .. tostring(chdir_err))
  end

  local shell_cmd = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
  local stdout = vim.fn.system(shell_cmd)
  local code = vim.v.shell_error
  pcall(vim.fn.chdir, old_cwd)
  return as_job_result(code, stdout, "")
end

return M
