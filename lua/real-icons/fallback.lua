local config = require("real-icons.config")
local path_util = require("real-icons.path")

local M = {}

local defaults = {
  default = { icon = "", hl = "Normal" },
  directory = { icon = "", hl = "Directory" },
}

local function mini(path, opts)
  local ok, icons = pcall(require, "mini.icons")
  if not ok or not icons.get then
    return nil
  end

  local category = opts and opts.is_dir and "directory" or "file"
  local icon, hl = icons.get(category, path)
  if icon then
    return { icon = icon, hl = hl or "Normal" }
  end
end

local function devicons(path)
  local ok, icons = pcall(require, "nvim-web-devicons")
  if not ok or not icons.get_icon then
    return nil
  end

  local name = path_util.basename(path)
  local ext = path_util.extension(path)
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
    local icon = devicons(path)
    if icon then
      return icon
    end
  end

  return opts.is_dir and defaults.directory or defaults.default
end

return M
