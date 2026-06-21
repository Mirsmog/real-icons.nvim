local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local group = vim.api.nvim_create_augroup("real-icons-oil", { clear = true })
local attached = {}

local function join(dir, name)
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ok, oil = pcall(require, "oil")
  if not ok then
    return
  end

  local dir = oil.get_current_dir(bufnr)
  if not dir then
    return
  end

  renderer.clear(bufnr)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for lnum = 1, line_count do
    local entry = oil.get_entry_on_line(bufnr, lnum)
    if entry and entry.name and entry.name ~= ".." then
      local is_dir = entry.type == "directory"
      local icon = resolver.resolve(join(dir, entry.name), { is_dir = is_dir })
      renderer.render(bufnr, lnum - 1, 0, icon, { priority = 250 })
    end
  end
end

function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if attached[bufnr] then
    M.refresh(bufnr)
    return
  end
  attached[bufnr] = true

  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      vim.schedule(function()
        M.refresh(bufnr)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      attached[bufnr] = nil
    end,
  })

  vim.schedule(function()
    M.refresh(bufnr)
  end)
end

function M.attach_current()
  M.attach(vim.api.nvim_get_current_buf())
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "oil",
    callback = function(args)
      M.attach(args.buf)
    end,
  })
end

return M
