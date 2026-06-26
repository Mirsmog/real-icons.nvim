local M = {}

function M.opts(opts)
  return opts or {}
end

function M.setup()
  return false, "fzf-lua integration is currently disabled"
end

return M
