local config = require("real-icons.config")
local path_util = require("real-icons.path")

local M = {}

local RESULT_CACHE_LIMIT = 4096
local provider_cache = {}
local result_cache = {}
local result_cache_count = 0

local defaults = {
  default = { icon = "", hl = "Normal" },
  directory = { icon = "", hl = "Directory" },
}

local function category_for(opts)
  if opts and (opts.category == "directory" or opts.is_dir) then
    return "directory"
  end
  if opts and (opts.category == "extension" or opts.category == "filetype") then
    return opts.category
  end
  return "file"
end

local function provider_module(name, module)
  local cached = provider_cache[name]
  if cached ~= nil then
    if cached ~= false or not package.loaded[module] then
      return cached ~= false and cached or nil
    end
  end

  local ok, value = pcall(require, module)
  if not ok then
    provider_cache[name] = false
    return nil
  end

  provider_cache[name] = value
  return value
end

local function mini(path, opts)
  local icons = provider_module("mini", "mini.icons")
  if not icons or not icons.get then
    return nil
  end

  local category = category_for(opts)
  local icon, hl = icons.get(category, path)
  if icon then
    return { icon = icon, hl = hl or "Normal" }
  end
end

local function devicons(path, opts)
  local icons = provider_module("devicons", "nvim-web-devicons")
  if not icons or not icons.get_icon then
    return nil
  end

  if opts and opts.category == "filetype" and type(icons.get_icon_by_filetype) == "function" then
    local icon, hl = icons.get_icon_by_filetype(path, { default = true })
    if icon then
      return { icon = icon, hl = hl or "Normal" }
    end
  end

  local name = path_util.basename(path)
  local ext = opts and opts.category == "extension" and path or path_util.extension(path)
  local icon, hl = icons.get_icon(name, ext, { default = true })
  if icon then
    return { icon = icon, hl = hl or "Normal" }
  end
end

local function cache_key(path, opts, fallback)
  opts = opts or {}
  return table.concat({
    fallback.provider or "auto",
    tostring(package.loaded["mini.icons"] ~= nil),
    tostring(package.loaded["nvim-web-devicons"] ~= nil),
    category_for(opts),
    tostring(path or ""),
    tostring(opts.is_dir == true),
    tostring(opts.filetype or ""),
  }, "\31")
end

function M.get(path, opts)
  opts = opts or {}
  local fallback = config.options.fallback
  if not fallback.enabled then
    return nil
  end

  local key = cache_key(path, opts, fallback)
  if result_cache[key] ~= nil then
    return result_cache[key] ~= false and result_cache[key] or nil
  end

  if fallback.provider == "auto" or fallback.provider == "mini" then
    local icon = mini(path, opts)
    if icon then
      if result_cache_count >= RESULT_CACHE_LIMIT then
        result_cache = {}
        result_cache_count = 0
      end
      result_cache[key] = icon
      result_cache_count = result_cache_count + 1
      return icon
    end
  end

  if fallback.provider == "auto" or fallback.provider == "devicons" then
    local icon = devicons(path, opts)
    if icon then
      if result_cache_count >= RESULT_CACHE_LIMIT then
        result_cache = {}
        result_cache_count = 0
      end
      result_cache[key] = icon
      result_cache_count = result_cache_count + 1
      return icon
    end
  end

  if result_cache_count >= RESULT_CACHE_LIMIT then
    result_cache = {}
    result_cache_count = 0
  end
  result_cache[key] = opts.is_dir and defaults.directory or defaults.default
  result_cache_count = result_cache_count + 1
  return result_cache[key]
end

function M.clear_cache()
  provider_cache = {}
  result_cache = {}
  result_cache_count = 0
end

return M
