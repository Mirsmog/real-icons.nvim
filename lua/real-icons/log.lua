local M = {}

function M.info(message)
  vim.notify(message, vim.log.levels.INFO, { title = "real-icons.nvim" })
end

function M.warn(message)
  vim.notify(message, vim.log.levels.WARN, { title = "real-icons.nvim" })
end

function M.error(message)
  vim.notify(message, vim.log.levels.ERROR, { title = "real-icons.nvim" })
end

return M
