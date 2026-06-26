local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local patched = false
local original_filename

local function item_path(item, picker)
  if not item then
    return nil
  end

  if picker and picker.opts and picker.opts.real_icons_path then
    local ok, path = pcall(picker.opts.real_icons_path, item, picker)
    if ok and path then
      return path
    end
  end

  return item.file or item.path or item.name
end

local function with_builtin_icons_disabled(picker, fn)
  local files = picker
    and picker.opts
    and picker.opts.icons
    and picker.opts.icons.files
  if type(files) ~= "table" then
    return fn()
  end

  local previous = files.enabled
  files.enabled = false
  local ok, ret = pcall(fn)
  files.enabled = previous
  if not ok then
    error(ret)
  end
  return ret
end

function M.icon(item, picker)
  local path = item_path(item, picker)
  if not path then
    return nil
  end

  local is_dir = item.dir or item.type == "directory"
  local icon = resolver.resolve(is_dir and "directory" or "file", path, {
    filetype = item.filetype or item.ft,
  })
  local segment = renderer.segment(icon)
  return { segment.text, segment.hl, virtual = true }
end

function M.filename(item, picker)
  local ret = {}
  local icon = M.icon(item, picker)
  if icon then
    ret[#ret + 1] = icon
    ret[#ret + 1] = { " ", virtual = true }
  end

  local chunks = with_builtin_icons_disabled(picker, function()
    return original_filename(item, picker)
  end)
  if type(chunks) == "table" then
    vim.list_extend(ret, chunks)
  elseif chunks ~= nil then
    ret[#ret + 1] = { tostring(chunks) }
  end
  return ret
end

function M.setup()
  if patched then
    return true
  end

  local ok, format = pcall(require, "snacks.picker.format")
  if not ok then
    return false, "snacks.nvim picker is not available"
  end

  if format._real_icons_patched then
    patched = true
    return true
  end

  original_filename = format.filename
  if type(original_filename) ~= "function" then
    return false, "snacks.nvim picker format API is not compatible"
  end

  format.filename = M.filename
  format._real_icons_patched = true
  patched = true
  return true
end

function M.is_patched()
  return patched
end

return M
