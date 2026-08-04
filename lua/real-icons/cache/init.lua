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
local svg_dimensions_cache = {}

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

local function svg_dimensions(path)
  local stat = uv.fs_stat(path)
  local mtime = stat and stat.mtime and stat.mtime.sec or 0
  local cached = svg_dimensions_cache[path]
  if cached and cached.mtime == mtime then
    return cached.width, cached.height
  end

  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil, nil
  end
  local data = uv.fs_read(fd, 16384, 0) or ""
  uv.fs_close(fd)

  local tag = data:match("<svg[%s%S]->")
  local viewbox = tag and (
    tag:match('viewBox%s*=%s*"([^"]+)"')
    or tag:match("viewBox%s*=%s*'([^']+)'")
  )
  local values = {}
  for value in (viewbox or ""):gmatch("[^,%s]+") do
    values[#values + 1] = tonumber(value)
  end

  local width = values[3] and math.abs(values[3]) or nil
  local height = values[4] and math.abs(values[4]) or nil
  if width == 0 then
    width = nil
  end
  if height == 0 then
    height = nil
  end
  svg_dimensions_cache[path] = {
    height = height,
    mtime = mtime,
    width = width,
  }
  return width, height
end

local function density_key(size)
  local density = tonumber(size.density)
  if density then
    return "d" .. density
  end
  return "dauto-o" .. (tonumber(size.oversample) or 1.25)
end

function M.density(size, source)
  size = size or config.options.size
  local fixed = tonumber(size.density)
  if fixed then
    return math.max(1, math.min(4096, math.floor(fixed + 0.5)))
  end

  local dimensions = M.dimensions(size)
  local padding = tonumber(size.padding) or 0
  local target_width = math.max(1, dimensions.width - padding * 2)
  local target_height = math.max(1, dimensions.height - padding * 2)
  local source_width, source_height = svg_dimensions(source)
  if not source_width or not source_height then
    return 384
  end

  local oversample = math.max(1, tonumber(size.oversample) or 1.25)
  local density = math.ceil(math.max(
    target_width / source_width,
    target_height / source_height
  ) * 96 * oversample)
  return math.max(1, math.min(4096, density))
end

function M.density_key(size)
  return density_key(size or config.options.size)
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
    "%dx%d-p%d-%s-%s-%s",
    dimensions.width,
    dimensions.height,
    padding,
    trim,
    density_key(size),
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

local function conversion_prefix()
  return {
    "magick",
    "-limit",
    "thread",
    "1",
  }
end

local function conversion_arguments(source, size, color)
  local dimensions = M.dimensions(size)
  local padding = size.padding or 0
  local inner_width = math.max(1, dimensions.width - padding * 2)
  local inner_height = math.max(1, dimensions.height - padding * 2)
  local arguments = {
    "-background",
    "none",
  }
  if source:lower():match("%.svg$") then
    vim.list_extend(arguments, {
      "-density",
      tostring(M.density(size, source)),
    })
  end
  vim.list_extend(arguments, {
    source,
    "-alpha",
    "on",
  })

  append_color_transform(arguments, color)

  if size.trim ~= false then
    vim.list_extend(arguments, {
      "-trim",
      "+repage",
    })
  end

  vim.list_extend(arguments, {
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
  })
  return arguments
end

local function conversion_command(source, target, size, color)
  if not path_util.ensure_dir(vim.fs.dirname(target)) then
    return nil, nil, "unable to create icon cache directory: " .. vim.fs.dirname(target)
  end

  local arguments = conversion_arguments(source, size, color)
  local command = conversion_prefix()
  vim.list_extend(command, arguments)
  command[#command + 1] = target

  local batch_arguments = vim.list_extend({}, arguments)
  vim.list_extend(batch_arguments, {
    "-write",
    target,
    "+delete",
  })
  return command, batch_arguments
end

local function run_conversion(command)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    return false, path_util.shell_error(command, output)
  end
  return true
end

local function prepare(icon, opts)
  opts = opts or {}
  local source = icon.source or icon.asset
  if not source then
    return nil, "icon has no source"
  end
  if not uv.fs_stat(source) then
    return nil, "icon source does not exist: " .. source
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
    return { path = source }
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
    return { path = target }
  end

  if vim.fn.executable("magick") ~= 1 then
    return nil, "ImageMagick is required to convert icons"
  end

  local command, batch_arguments, command_err = conversion_command(source, target, size, color)
  if not command then
    return nil, command_err
  end
  return {
    batch_arguments = batch_arguments,
    path = target,
    command = command,
  }
end

function M.ensure(icon, opts)
  opts = opts or {}
  local prepared, prepare_err = prepare(icon, opts)
  if not prepared then
    return nil, prepare_err
  end
  if not prepared.command then
    return prepared.path
  end

  local ok, err = run_conversion(prepared.command)
  if not ok then
    return nil, err
  end
  return prepared.path
end

local function parallelism(opts)
  local available = 1
  if type(uv.available_parallelism) == "function" then
    available = tonumber(uv.available_parallelism()) or available
  end
  local jobs = tonumber(opts.jobs or opts.concurrency) or available
  return math.max(1, math.min(8, math.floor(jobs)))
end

local function batch_size(opts)
  local value = tonumber(opts.batch_size) or 32
  return math.max(1, math.min(128, math.floor(value)))
end

local function batch_command(tasks)
  local command = conversion_prefix()
  for _, task in ipairs(tasks) do
    vim.list_extend(command, task.batch_arguments)
  end
  command[#command + 1] = "null:"
  return command
end

function M.ensure_many(icons, opts)
  opts = opts or {}
  local count = 0
  local failed = 0
  local errors = {}
  local tasks = {}
  local tasks_by_path = {}

  for _, icon in ipairs(icons or {}) do
    local prepared, err = prepare(icon, opts)
    if not prepared then
      failed = failed + 1
      errors[#errors + 1] = { icon = icon, error = err }
    elseif not prepared.command then
      count = count + 1
    else
      local task = tasks_by_path[prepared.path]
      if task then
        task.count = task.count + 1
      else
        task = {
          command = prepared.command,
          batch_arguments = prepared.batch_arguments,
          count = 1,
          icon = icon,
          path = prepared.path,
        }
        tasks[#tasks + 1] = task
        tasks_by_path[prepared.path] = task
      end
    end
  end

  local jobs = parallelism(opts)
  local function record_success(task)
    count = count + task.count
  end

  local function record_failure(task, err)
    failed = failed + task.count
    errors[#errors + 1] = { icon = task.icon, error = err }
  end

  local function run_individually(group)
    for _, task in ipairs(group) do
      local ok, err = run_conversion(task.command)
      if ok then
        record_success(task)
      else
        record_failure(task, err)
      end
    end
  end

  if type(vim.system) ~= "function" then
    run_individually(tasks)
    return count, failed, errors
  end

  local wave_size = jobs * batch_size(opts)
  for first = 1, #tasks, wave_size do
    local last = math.min(first + wave_size - 1, #tasks)
    local groups = {}
    for index = first, last do
      local group_index = ((index - first) % jobs) + 1
      groups[group_index] = groups[group_index] or {}
      groups[group_index][#groups[group_index] + 1] = tasks[index]
    end

    local running = {}
    for _, group in pairs(groups) do
      local command = batch_command(group)
      local ok, process = pcall(vim.system, command, { text = true })
      if ok then
        running[#running + 1] = {
          command = command,
          group = group,
          process = process,
        }
      else
        run_individually(group)
      end
    end

    for _, item in ipairs(running) do
      local result = item.process:wait()
      if result.code == 0 then
        for _, task in ipairs(item.group) do
          record_success(task)
        end
      else
        run_individually(item.group)
      end
    end
  end

  return count, failed, errors
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
