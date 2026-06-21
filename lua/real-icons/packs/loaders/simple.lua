local util = require("real-icons.packs.util")

local M = {}

local function add_asset(root, definitions, map, from, key)
  if type(from) ~= "string" then
    map[key] = from
    return
  end

  if util.looks_like_asset(from) or from:find("/", 1, true) then
    local icon_key = util.icon_key(from)
    definitions[icon_key] = util.join(root, from)
    map[key] = icon_key
  else
    map[key] = from
  end
end

local function normalize_map(root, definitions, input)
  local output = {}
  for key, value in pairs(input or {}) do
    add_asset(root, definitions, output, value, key)
  end
  return output
end

function M.load(name, spec)
  local root = util.expand(assert(spec.path, "simple icon pack requires path"))
  local definitions = {}

  for key, value in pairs(spec.definitions or {}) do
    definitions[key] = util.join(root, value)
  end

  local file = spec.file or "file.svg"
  local folder = spec.folder or "folder.svg"
  local file_key = util.looks_like_asset(file) and util.icon_key(file) or file
  local folder_key = util.looks_like_asset(folder) and util.icon_key(folder) or folder

  if util.looks_like_asset(file) then
    definitions[file_key] = util.join(root, file)
  end
  if util.looks_like_asset(folder) then
    definitions[folder_key] = util.join(root, folder)
  end

  return {
    name = name,
    root = root,
    license = spec.license,
    definitions = definitions,
    file = file_key,
    folder = folder_key,
    file_extensions = normalize_map(root, definitions, spec.extensions or spec.file_extensions),
    file_names = normalize_map(root, definitions, spec.filenames or spec.file_names),
    folder_names = normalize_map(root, definitions, spec.folders or spec.folder_names),
    language_ids = normalize_map(root, definitions, spec.languages or spec.language_ids),
  }
end

return M
