local config = require("real-icons.config")
local path_util = require("real-icons.path")

local M = {}

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

local function mini(path, opts)
  local ok, icons = pcall(require, "mini.icons")
  if not ok or not icons.get then
    return nil
  end

  local category = category_for(opts)
  local icon, hl = icons.get(category, path)
  if icon then
    return { icon = icon, hl = hl or "Normal" }
  end
end

local function devicons(path, opts)
  local ok, icons = pcall(require, "nvim-web-devicons")
  if not ok or not icons.get_icon then
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

function M.get(path, opts)
  opts = opts or {}
  local fallback = config.options.fallback
  if not fallback.enabled then
    return nil
  end

  if fallback.provider == "auto" or fallback.provider == "mini" then
    local icon = mini(path, opts)
    if icon then
      return icon
    end
  end

  if fallback.provider == "auto" or fallback.provider == "devicons" then
    local icon = devicons(path, opts)
    if icon then
      return icon
    end
  end

  return opts.is_dir and defaults.directory or defaults.default
end

return M
