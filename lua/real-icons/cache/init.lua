local config = require("real-icons.config")
local path_util = require("real-icons.path")

local M = {}

local uv = vim.uv or vim.loop

local function safe_name(value)
  return (value:gsub("[^%w%._%-]+", "_"))
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

function M.pack_dir(pack)
  return path_util.join(M.root(), pack)
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

local function variant(size)
  local dimensions = M.dimensions(size)
  local padding = size.padding or 0
  local trim = size.trim ~= false and "trim" or "raw"
  return string.format("%dx%d-p%d-%s", dimensions.width, dimensions.height, padding, trim)
end

function M.target(icon, size)
  size = size or config.options.size
  local name = safe_name(icon.pack .. "__" .. icon.key)
  return path_util.join(M.pack_dir(icon.pack), variant(size), name .. ".png")
end

local function convert_with_magick(source, target, size)
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
  if ext == "png" and png_signature(source) then
    return source
  end

  if ext ~= "svg" then
    return nil, "unsupported icon format: " .. ext
  end

  local size = opts.size or config.options.size
  local target = M.target(icon, size)
  local target_stat = uv.fs_stat(target)
  if target_stat and target_stat.mtime.sec >= file_mtime(source) then
    return target
  end

  if vim.fn.executable("magick") ~= 1 then
    return nil, "ImageMagick is required to convert SVG icons"
  end

  local ok, err = convert_with_magick(source, target, size)
  if not ok then
    return nil, err
  end
  return target
end

function M.clear(pack)
  local target = pack and M.pack_dir(pack) or path_util.cache_dir()
  if path_util.exists(target) then
    vim.fn.delete(target, "rf")
  end
end

return M
