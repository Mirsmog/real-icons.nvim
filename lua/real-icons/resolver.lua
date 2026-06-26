local config = require("real-icons.config")
local fallback = require("real-icons.fallback")
local packs = require("real-icons.packs")
local pack_util = require("real-icons.packs.util")
local path_util = require("real-icons.path")

local M = {}
local RESOLVE_CACHE_LIMIT = 8192
local resolve_cache = {}
local resolve_cache_count = 0

local lazy_fallback = {}

function lazy_fallback.__index(icon, key)
  if key ~= "fallback" then
    return nil
  end

  local value = fallback.get(rawget(icon, "path"), {
    category = rawget(icon, "category"),
    filetype = rawget(icon, "filetype"),
    is_dir = rawget(icon, "kind") == "directory",
  })
  rawset(icon, "fallback", value or false)
  return value
end

local category_aliases = {
  dir = "directory",
  folder = "directory",
  directory = "directory",
  ext = "extension",
  extension = "extension",
  file = "file",
  ft = "filetype",
  filetype = "filetype",
  language = "filetype",
  language_id = "filetype",
}

local valid_categories = {
  directory = true,
  extension = true,
  file = true,
  filetype = true,
}

local function normalize_category(category)
  if type(category) ~= "string" or category == "" then
    return nil
  end
  local normalized = category_aliases[category]
  if normalized and valid_categories[normalized] then
    return normalized
  end
end

local function normalize_args(category, name, opts)
  opts = opts or {}
  category = normalize_category(category)

  if not category then
    error("real-icons category must be file, directory, extension, or filetype")
  end
  if name == nil then
    error("real-icons name is required")
  end

  return category, tostring(name), opts
end

local function normalize_key(key)
  if type(key) == "table" then
    return key.icon or key.name
  end
  return key
end

local function normalize_extension(value)
  value = tostring(value or "")
  value = value:gsub("^%.+", "")
  return value:lower()
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

local function resolve_override(category, path, opts, is_dir, name, lower_name, extension)
  local maps = override_maps()
  local value

  if category == "directory" or is_dir then
    value = map_value(maps.folder_names, lower_name, name)
  elseif category == "extension" then
    value = map_value(maps.file_extensions, extension)
  elseif category == "filetype" then
    value = map_value(maps.language_ids, opts.filetype or path)
  else
    value = map_value(maps.file_names, lower_name, name)
    if not value then
      value = map_value(maps.file_extensions, extension)
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

local function resolve_cache_key(category, name, opts)
  if category == "file" and opts.is_dir == nil then
    return nil
  end

  return table.concat({
    opts.pack or config.options.pack or "",
    category,
    name,
    tostring(opts.extension or ""),
    tostring(opts.filetype or ""),
    tostring(opts.is_dir),
    tostring(opts.fallback == false),
  }, "\31")
end

local function with_fallback(icon, enabled)
  if not enabled then
    return icon
  end
  return setmetatable(icon, lazy_fallback)
end

function M.resolve(category, name, opts)
  category, name, opts = normalize_args(category, name, opts)

  local cache_key = resolve_cache_key(category, name, opts)
  if cache_key and resolve_cache[cache_key] then
    return resolve_cache[cache_key]
  end

  local path = name
  local basename = path_util.basename(path)
  local lower_name = basename:lower()
  local is_dir
  if category == "directory" then
    is_dir = true
  elseif category == "file" then
    is_dir = opts.is_dir
  else
    is_dir = false
  end
  if category == "file" and is_dir == nil then
    is_dir = path_util.is_dir(path)
  end

  local extension = category == "extension"
      and normalize_extension(path)
      or normalize_extension(opts.extension or path_util.extension(path) or "")

  local pack = packs.get(opts.pack)
  local definitions = pack.definitions or {}
  local file_extensions = pack.file_extensions or {}
  local file_names = pack.file_names or {}
  local folder_names = pack.folder_names or {}
  local language_ids = pack.language_ids or {}
  local defaulted = false
  local key, source = resolve_override(category, path, opts, is_dir, basename, lower_name, extension)

  if category == "directory" or is_dir then
    key = key or normalize_key(folder_names[lower_name] or folder_names[basename])
    if not key then
      key = normalize_key(pack.folder)
      defaulted = true
    end
  elseif category == "extension" then
    key = key or normalize_key(file_extensions[extension])
    if not key then
      key = normalize_key(pack.file)
      defaulted = true
    end
  elseif category == "filetype" then
    key = key or normalize_key(language_ids[opts.filetype or path])
    if not key then
      key = normalize_key(pack.file)
      defaulted = true
    end
  else
    key = key or normalize_key(file_names[lower_name] or file_names[basename])
    if not key then
      key = normalize_key(file_extensions[extension])
    end
    if not key and opts.filetype then
      key = normalize_key(language_ids[opts.filetype])
    end
    if not key then
      key = normalize_key(pack.file)
      defaulted = true
    end
  end

  source = source or (key and definitions[key])
  if not source and is_dir then
    key = normalize_key(pack.folder)
    source = key and definitions[key]
    defaulted = true
  elseif not source then
    key = normalize_key(pack.file)
    source = key and definitions[key]
    defaulted = true
  end

  local icon = with_fallback({
    pack = pack.name,
    key = key,
    category = category,
    kind = is_dir and "directory" or "file",
    source = source,
    asset = source,
    path = path,
    name = basename,
    extension = extension,
    filetype = opts.filetype,
    is_default = defaulted,
  }, opts.fallback ~= false)

  if cache_key then
    if resolve_cache_count >= RESOLVE_CACHE_LIMIT then
      resolve_cache = {}
      resolve_cache_count = 0
    end
    resolve_cache[cache_key] = icon
    resolve_cache_count = resolve_cache_count + 1
  end
  return icon
end

function M.categories()
  return { "file", "directory", "extension", "filetype" }
end

function M.list(category, opts)
  category = category == nil and "file" or normalize_category(category)
  if not category then
    error("real-icons category must be file, directory, extension, or filetype")
  end
  opts = opts or {}

  local pack = packs.get(opts.pack)
  local source
  if category == "directory" then
    source = pack.folder_names
  elseif category == "extension" then
    source = pack.file_extensions
  elseif category == "filetype" then
    source = pack.language_ids
  else
    source = pack.file_names
  end

  local result = vim.tbl_keys(source or {})
  table.sort(result)
  return result
end

M.normalize_category = normalize_category

function M.clear_cache()
  resolve_cache = {}
  resolve_cache_count = 0
end

return M
