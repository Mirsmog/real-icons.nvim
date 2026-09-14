local M = {}
local scheduled = false
local reasons = {}

function M.changed(reason)
  reasons[reason or "refresh"] = true
  if scheduled then
    return
  end
  scheduled = true
  vim.defer_fn(function()
    scheduled = false
    local changes = reasons
    reasons = {}
    vim.api.nvim_exec_autocmds("User", {
      pattern = "RealIconsUpdated",
      data = { reasons = changes },
      modeline = false,
    })
  end, 30)
end

return M
