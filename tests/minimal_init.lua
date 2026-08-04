local source = debug.getinfo(1, "S").source:gsub("^@", "")
local root = vim.fs.dirname(vim.fs.dirname(source))

vim.opt.runtimepath:prepend(root)
vim.o.swapfile = false
vim.o.termguicolors = true
