local config = require("real-icons.config")
local fallback = require("real-icons.fallback")
local packs = require("real-icons.packs")
local pack_util = require("real-icons.packs.util")
local path_util = require("real-icons.path")

local M = {}

local function normalize_key(key)
  if type(key) == "table" then
    return key.icon or key.name
  end
  return key
end

local function map_value(map, ...)
  if not map then
    return nil
  end
  for _, key in ipairs({ ... }) do
    if key and map[key] ~= nil then
      return map[key]
    end
  end
  return nil
end

local function override_maps()
  local overrides = config.options.overrides or {}
  return {
    file_names = overrides.file_names or overrides.filenames or overrides.files,
    file_extensions = overrides.file_extensions or overrides.extensions,
    folder_names = overrides.folder_names or overrides.folders,
    language_ids = overrides.language_ids or overrides.languages,
    definitions = overrides.definitions or {},
  }
end

local function override_source(value, definitions)
  value = normalize_key(value)
  if not value then
    return nil, nil
  end

  if definitions[value] then
    return value, vim.fn.fnamemodify(definitions[value], ":p")
  end

  if pack_util.looks_like_asset(value) or value:find("/", 1, true) then
    return "override-" .. pack_util.icon_key(value), vim.fn.fnamemodify(value, ":p")
  end

  return value, nil
end

local function resolve_override(path, opts, is_dir, name, lower_name)
  local maps = override_maps()
  local value

  if is_dir then
    value = map_value(maps.folder_names, lower_name, name)
  else
    value = map_value(maps.file_names, lower_name, name)
    if not value then
      value = map_value(maps.file_extensions, path_util.extension(path) or "")
    end
    if not value and opts.filetype then
      value = map_value(maps.language_ids, opts.filetype)
    end
  end

  local key, source = override_source(value, maps.definitions)
  if source then
    return key, source
  end
  return key, nil
end

function M.resolve(path, opts)
  opts = opts or {}
  local name = path_util.basename(path)
  local lower_name = name:lower()
  local is_dir = opts.is_dir
  if is_dir == nil then
    is_dir = path_util.is_dir(path)
  end

  local pack = packs.get(opts.pack)
  local key, source = resolve_override(path, opts, is_dir, name, lower_name)
  if is_dir then
    key = key or normalize_key(pack.folder_names[lower_name] or pack.folder_names[name] or pack.folder)
  else
    key = key or normalize_key(pack.file_names[lower_name] or pack.file_names[name])
    if not key then
      key = normalize_key(pack.file_extensions[path_util.extension(path) or ""])
    end
    if not key and opts.filetype then
      key = normalize_key(pack.language_ids[opts.filetype])
    end
    key = key or normalize_key(pack.file)
  end

  source = source or (key and pack.definitions[key])
  if not source and is_dir then
    key = normalize_key(pack.folder)
    source = key and pack.definitions[key]
  elseif not source then
    key = normalize_key(pack.file)
    source = key and pack.definitions[key]
  end

  return {
    pack = pack.name,
    key = key,
    kind = is_dir and "directory" or "file",
    source = source,
    asset = source,
    path = path,
    fallback = fallback.get(path, { is_dir = is_dir }),
  }
end

return M
