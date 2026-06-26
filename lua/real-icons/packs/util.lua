local path_util = require("real-icons.path")
local bit = require("bit")

local M = {}

local function path_hash(path)
  local hash = 2166136261
  path = tostring(path or "")
  for index = 1, #path do
    hash = bit.bxor(hash, path:byte(index))
    hash = (hash * 16777619) % 4294967296
  end
  return string.format("%08x", hash)
end

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

  if path:sub(1, 1) == "/" or path:sub(1, 1) == "~" then
    return M.expand(path)
  end

  local expanded_root = M.expand(root)
  local joined = vim.fs.normalize(path_util.join(expanded_root, path))
  local root_prefix = expanded_root:gsub("/$", "") .. "/"
  if joined ~= expanded_root and joined:sub(1, #root_prefix) ~= root_prefix then
    error("icon pack path escapes root: " .. path)
  end
  return joined
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
  name = name:gsub("[^%w%._%-]+", "_")
  return string.format("%s-%s", name, path_hash(path):sub(1, 8))
end

function M.looks_like_asset(value)
  return type(value) == "string" and value:match("%.(svg|png|jpe?g|webp)$") ~= nil
end

return M
