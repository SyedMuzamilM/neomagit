local config = require("neomagit.config")
local context = require("neomagit.git.context")
local state = require("neomagit.state.session")
local ui = require("neomagit.ui.status")
local actions = require("neomagit.actions.core")

local M = {}

local function notify(msg, level)
  vim.notify("[neomagit] " .. msg, level or vim.log.levels.INFO)
end

function M.setup(opts)
  config.setup(opts)
  if config.values.keymaps == "default" then
    vim.keymap.set("n", "<leader>gg", function()
      require("neomagit").open()
    end, { silent = true, desc = "Open neomagit" })
  end
end

function M.open(opts)
  opts = opts or {}
  local from = opts.cwd or vim.api.nvim_buf_get_name(0)
  local ctx, err = context.discover(from)
  if not ctx then
    notify(err or "Could not resolve repository", vim.log.levels.ERROR)
    return
  end
  local session = state.get_or_create(ctx)
  ui.open(session)
end

function M.refresh()
  ui.refresh()
end

function M.run(action, opts)
  if type(action) ~= "string" then
    notify("run(action, opts) requires a string action", vim.log.levels.ERROR)
    return
  end

  local dispatch = {
    stage = actions.stage_from_cursor,
    unstage = actions.unstage_from_cursor,
    discard = actions.discard_from_cursor,
    commit = actions.commit_popup,
    branch = actions.branch_popup,
    stash = actions.stash_popup,
    fetch = actions.fetch,
    push = actions.push,
    pull = actions.pull,
    pushpull = actions.push_pull_popup,
    rebase = actions.rebase_popup,
    cherry_pick = actions.cherry_pick_popup,
    revert = actions.revert_popup,
    reset = actions.reset_popup,
    log = actions.show_log,
  }

  local fn = dispatch[action]
  if not fn then
    notify("Unknown action: " .. action, vim.log.levels.ERROR)
    return
  end

  if opts and opts.open and not state.current() then
    M.open(opts)
  end
  fn()
end

return M
