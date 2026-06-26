local config = require("real-icons.config")
local path_util = require("real-icons.path")
local bit = require("bit")

local M = {}

local uv = vim.uv or vim.loop
local supported_formats = {
  svg = true,
  png = true,
  jpg = true,
  jpeg = true,
  webp = true,
}

local function safe_name(value)
  return (value:gsub("[^%w%._%-]+", "_"))
end

local function path_key(value)
  value = tostring(value or "")
  if value == "" then
    return nil, "invalid pack name: " .. value
  end
  if value:match("^[%w_%-]+$") then
    return value
  end

  local key = value:gsub("[^%w_%-]+", "_")
  key = key:gsub("^_+", ""):gsub("_+$", "")
  if key == "" then
    key = "pack"
  end

  local hash = 2166136261
  for index = 1, #value do
    hash = bit.bxor(hash, value:byte(index))
    hash = (hash * 16777619) % 4294967296
  end
  return string.format("%s-%08x", key, hash)
end

local function file_mtime(path)
  local stat = uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or 0
end

local function png_signature(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return false
  end
  local data = uv.fs_read(fd, 8, 0)
  uv.fs_close(fd)
  return data == "\137PNG\r\n\026\n"
end

function M.root()
  return path_util.join(path_util.cache_dir(), "packs")
end

function M.pack_key(pack)
  return path_key(pack)
end

function M.pack_dir(pack)
  local key, err = M.pack_key(pack)
  if not key then
    return nil, err
  end
  return path_util.join(M.root(), key)
end

function M.dimensions(size)
  size = size or config.options.size

  if type(size.pixels) == "table" then
    return {
      width = size.pixels.width or size.pixels[1] or 20,
      height = size.pixels.height or size.pixels[2] or size.pixels.width or size.pixels[1] or 20,
    }
  end

  return {
    width = size.pixel_width or size.width or size.pixels or 20,
    height = size.pixel_height or size.height or size.pixels or 20,
  }
end

local function normalize_color(color)
  if color == nil then
    color = config.options.color
  end

  if color == false or color == nil then
    color = {}
  elseif type(color) == "string" then
    color = { tint = color }
  elseif type(color) ~= "table" then
    color = {}
  end

  return {
    tint = color.tint or color.mask or color.mask_color,
    saturation = tonumber(color.saturation) or 0,
    brightness = tonumber(color.brightness or color.lightness) or 0,
    hue = tonumber(color.hue) or 0,
    monochrome = color.monochrome == true or color.grayscale == true,
  }
end

function M.has_color_transform(color)
  color = normalize_color(color)
  return color.tint ~= nil
    or color.monochrome
    or color.saturation ~= 0
    or color.brightness ~= 0
    or color.hue ~= 0
end

function M.color_key(color)
  color = normalize_color(color)
  if not M.has_color_transform(color) then
    return "native"
  end

  return safe_name(table.concat({
    color.tint or "none",
    color.monochrome and "mono" or "color",
    "s" .. color.saturation,
    "b" .. color.brightness,
    "h" .. color.hue,
  }, "_"))
end

local function variant(size, color)
  local dimensions = M.dimensions(size)
  local padding = size.padding or 0
  local trim = size.trim ~= false and "trim" or "raw"
  return string.format(
    "%dx%d-p%d-%s-%s",
    dimensions.width,
    dimensions.height,
    padding,
    trim,
    M.color_key(color)
  )
end

function M.target(icon, size, color)
  size = size or config.options.size
  local pack_dir, err = M.pack_dir(icon.pack)
  if not pack_dir then
    return nil, err
  end
  local name = safe_name(tostring(icon.pack) .. "__" .. tostring(icon.key))
  return path_util.join(pack_dir, variant(size, color), name .. ".png")
end

local function append_color_transform(command, color)
  color = normalize_color(color)

  if color.monochrome then
    vim.list_extend(command, {
      "-colorspace",
      "Gray",
      "-colorspace",
      "sRGB",
    })
  end

  if color.tint then
    vim.list_extend(command, {
      "-fill",
      tostring(color.tint),
      "-colorize",
      "100",
    })
  end

  if color.saturation ~= 0 or color.brightness ~= 0 or color.hue ~= 0 then
    vim.list_extend(command, {
      "-modulate",
      string.format(
        "%d,%d,%d",
        math.max(0, 100 + color.brightness),
        math.max(0, 100 + color.saturation),
        math.max(0, 100 + color.hue)
      ),
    })
  end
end

local function convert_with_magick(source, target, size, color)
  local dimensions = M.dimensions(size)
  local padding = size.padding or 0
  local inner_width = math.max(1, dimensions.width - padding * 2)
  local inner_height = math.max(1, dimensions.height - padding * 2)

  path_util.ensure_dir(vim.fs.dirname(target))
  local command = {
    "magick",
    "-background",
    "none",
    "-density",
    "384",
    source,
    "-alpha",
    "on",
  }

  append_color_transform(command, color)

  if size.trim ~= false then
    vim.list_extend(command, {
      "-trim",
      "+repage",
    })
  end

  vim.list_extend(command, {
    "-filter",
    "Lanczos",
    "-resize",
    inner_width .. "x" .. inner_height,
    "-gravity",
    "center",
    "-background",
    "none",
    "-extent",
    dimensions.width .. "x" .. dimensions.height,
    "-strip",
    target,
  })

  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    return false, path_util.shell_error(command, output)
  end
  return true
end

function M.ensure(icon, opts)
  opts = opts or {}
  local source = icon.source or icon.asset
  if not source then
    return nil, "icon has no source"
  end

  local ext = source:match("%.([^.]+)$")
  ext = ext and ext:lower() or ""

  local size = opts.size or config.options.size
  local color = opts.color
  if color == nil then
    color = config.options.color
  end
  local color_transform = M.has_color_transform(color)
  if ext == "png" and png_signature(source) and not color_transform then
    return source
  end

  if not supported_formats[ext] then
    return nil, "unsupported icon format: " .. ext
  end

  local target, target_err = M.target(icon, size, color)
  if not target then
    return nil, target_err
  end
  local target_stat = uv.fs_stat(target)
  if target_stat and target_stat.mtime.sec >= file_mtime(source) then
    return target
  end

  if vim.fn.executable("magick") ~= 1 then
    return nil, "ImageMagick is required to convert icons"
  end

  local ok, err = convert_with_magick(source, target, size, color)
  if not ok then
    return nil, err
  end
  return target
end

function M.clear(pack)
  local target, err
  if pack then
    target, err = M.pack_dir(pack)
  else
    target = path_util.cache_dir()
  end
  if not target then
    return false, err
  end
  if path_util.exists(target) then
    vim.fn.delete(target, "rf")
  end
  return true
end

return M
