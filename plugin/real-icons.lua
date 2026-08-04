if vim.g.loaded_real_icons == 1 then
  return
end
vim.g.loaded_real_icons = 1

require("real-icons.command").setup()
