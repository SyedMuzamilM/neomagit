if vim.g.loaded_neomagit == 1 then
  return
end
vim.g.loaded_neomagit = 1

vim.api.nvim_create_user_command("Neomagit", function()
  require("neomagit").open()
end, {})

vim.api.nvim_create_user_command("NeomagitLog", function()
  require("neomagit").run("log", { open = true })
end, {})

vim.api.nvim_create_user_command("NeomagitBranch", function()
  require("neomagit").run("branch", { open = true })
end, {})

vim.api.nvim_create_user_command("NeomagitStash", function()
  require("neomagit").run("stash", { open = true })
end, {})

vim.api.nvim_create_user_command("NeomagitRebase", function()
  require("neomagit").run("rebase", { open = true })
end, {})

vim.api.nvim_create_user_command("NeomagitCherryPick", function()
  require("neomagit").run("cherry_pick", { open = true })
end, {})

vim.api.nvim_create_user_command("NeomagitRefresh", function()
  require("neomagit").refresh()
end, {})
