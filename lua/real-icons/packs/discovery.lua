local path_util = require("real-icons.path")
local util = require("real-icons.packs.util")

local M = {}

local uv = vim.uv or vim.loop

local default_roots = {
  "~/.vscode/extensions",
  "~/.vscode-oss/extensions",
  "~/.vscodium/extensions",
  "~/.cursor/extensions",
  "~/.windsurf/extensions",
}

local function path_hash(path)
  local bit = require("bit")
  local hash = 2166136261
  path = tostring(path or "")
  for index = 1, #path do
    hash = bit.bxor(hash, path:byte(index))
    hash = (hash * 16777619) % 4294967296
  end
  return string.format("%08x", hash)
end

local function slug(value)
  value = tostring(value or ""):lower()
  value = value:gsub("[^%w]+", "-")
  value = value:gsub("^-+", ""):gsub("-+$", "")
  return value ~= "" and value or "theme"
end

local function expand(path)
  local expanded = vim.fn.expand(path)
  if expanded == "" then
    return nil
  end
  return vim.fs.normalize(expanded)
end

local function existing_roots(extra)
  local roots = {}
  local seen = {}
  for _, root in ipairs(extra or default_roots) do
    local expanded = expand(root)
    if expanded and not seen[expanded] and path_util.exists(expanded) then
      roots[#roots + 1] = expanded
      seen[expanded] = true
    end
  end
  return roots
end

local function child_dirs(root)
  local dirs = {}
  local scanner = uv.fs_scandir(root)
  if not scanner then
    return dirs
  end

  while true do
    local name, kind = uv.fs_scandir_next(scanner)
    if not name then
      break
    end
    if kind == "directory" then
      dirs[#dirs + 1] = path_util.join(root, name)
    end
  end
  table.sort(dirs)
  return dirs
end

local function read_package(root)
  local package_file = path_util.join(root, "package.json")
  if not path_util.exists(package_file) then
    return nil
  end
  return util.read_json(package_file)
end

local function manifest_exists(root, theme)
  if type(theme.path) ~= "string" or theme.path == "" then
    return false
  end

  local ok, manifest = pcall(util.join, root, theme.path)
  return ok and path_util.exists(manifest)
end

local function candidate_name(package, theme, root)
  local raw = table.concat({
    package.name or vim.fs.basename(root),
    theme.id or theme.label or theme.path,
  }, "-")
  return table.concat({
    "vscode",
    slug(raw),
    path_hash(root .. "|" .. tostring(theme.path)):sub(1, 6),
  }, "-")
end

local function extension_label(package, root)
  return package.displayName or package.name or vim.fs.basename(root)
end

local function theme_label(theme)
  return theme.label or theme.id or theme.path
end

local function scan_extension(root)
  local package = read_package(root)
  local icon_themes = package
    and package.contributes
    and package.contributes.iconThemes
    or {}
  local result = {}

  for _, theme in ipairs(icon_themes) do
    if manifest_exists(root, theme) then
      local name = candidate_name(package, theme, root)
      result[#result + 1] = {
        name = name,
        label = theme_label(theme),
        extension = extension_label(package, root),
        source = root,
        theme = theme.id or theme.label,
        manifest = theme.path,
        kind = "vscode",
        spec = {
          type = "vscode",
          path = root,
          manifest = theme.path,
        },
      }
    end
  end

  return result
end

function M.discover(opts)
  opts = opts or {}
  local roots = existing_roots(opts.roots)
  local candidates = {}

  for _, root in ipairs(roots) do
    for _, extension in ipairs(child_dirs(root)) do
      vim.list_extend(candidates, scan_extension(extension))
    end
  end

  table.sort(candidates, function(a, b)
    return a.label:lower() < b.label:lower()
  end)
  return candidates
end

return M
