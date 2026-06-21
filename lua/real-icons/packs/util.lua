local path_util = require("real-icons.path")

local M = {}

function M.expand(path)
  if not path then
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

function M.join(root, path)
  if not path or path == "" then
    return root
  end
  path = path:gsub("^%./", "")
  path = path:gsub("^%.%./", "")
  if path:sub(1, 1) == "/" then
    return path
  end
  return path_util.join(root, path)
end

function M.read_json(file)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or not lines then
    return nil, "unable to read " .. file
  end

  local ok_decode, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not ok_decode then
    return nil, "unable to parse " .. file
  end

  return data
end

function M.icon_key(path)
  local name = vim.fn.fnamemodify(path, ":t:r")
  return name:gsub("[^%w%._%-]+", "_")
end

function M.looks_like_asset(value)
  return type(value) == "string" and value:match("%.(svg|png|jpe?g|webp)$") ~= nil
end

return M
