local M = {}

local uv = vim.uv or vim.loop

function M.join(...)
  local parts = { ... }
  local result = table.concat(parts, "/")
  result = result:gsub("/+", "/")
  return result
end

function M.normalize(path)
  if not path or path == "" then
    return path
  end
  return vim.fn.fnamemodify(path, ":p")
end

function M.basename(path)
  if not path or path == "" then
    return ""
  end
  return vim.fs.basename(path:gsub("/$", ""))
end

function M.extension(path)
  local name = M.basename(path):lower()
  return name:match("%.([^.]+)$")
end

function M.exists(path)
  return path ~= nil and uv.fs_stat(path) ~= nil
end

function M.is_dir(path)
  local stat = path and uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

function M.ensure_dir(path)
  if M.exists(path) then
    return true
  end
  local ok = vim.fn.mkdir(path, "p")
  return ok == 1 or M.exists(path)
end

function M.data_dir()
  return M.join(vim.fn.stdpath("data"), "real-icons")
end

function M.cache_dir()
  return M.join(vim.fn.stdpath("cache"), "real-icons")
end

function M.project_root()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    return vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source:sub(2))))
  end
  return vim.fn.getcwd()
end

function M.shell_error(command, output)
  local text = table.concat(command, " ")
  output = vim.trim(output or "")
  if output ~= "" then
    return text .. "\n" .. output
  end
  return text
end

return M
