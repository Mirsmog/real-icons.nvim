local M = {}
local uv = vim.uv or vim.loop

local function source_path()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    return vim.fn.fnamemodify(source:sub(2), ":p")
  end
  return nil
end

function M.root()
  local source = source_path()
  if not source then
    return vim.fn.getcwd()
  end
  return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
end

function M.dir()
  return M.root() .. "/assets"
end

function M.file(kind, key)
  return string.format("%s/%s/%s.png", M.dir(), kind, key)
end

function M.exists(path)
  return uv.fs_stat(path) ~= nil
end

return M
