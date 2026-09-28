local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local patched = false

local function path_for_current_buffer()
  local path = vim.api.nvim_buf_get_name(0)
  if path ~= "" then
    return path
  end
  return vim.bo.filetype ~= "" and vim.bo.filetype or "[No Name]"
end

local function statusline_hl(hl)
  return "%#" .. hl .. "#"
end

local function filesize()
  local size = math.max(vim.fn.line2byte(vim.fn.line("$") + 1) - 1, 0)
  if size < 1024 then
    return string.format("%dB", size)
  elseif size < 1048576 then
    return string.format("%.2fKiB", size / 1024)
  else
    return string.format("%.2fMiB", size / 1048576)
  end
end

function M.component(opts)
  opts = opts or {}
  -- Terminals, tree sidebars and picker prompts are not filenames. Explicit
  -- paths/filetypes still allow callers to render a chosen file's icon.
  if not opts.path and not opts.filetype then
    local name = vim.api.nvim_buf_get_name(0)
    if vim.bo.buftype ~= "" or name == "" or name:match("^%w[%w+.-]*://") then
      return ""
    end
  end
  local path = opts.path or path_for_current_buffer()
  local is_dir = opts.is_dir
  if is_dir == nil then
    is_dir = vim.fn.isdirectory(path) == 1
  end
  local icon = resolver.resolve(is_dir and "directory" or "file", path, {
    filetype = opts.filetype or vim.bo.filetype,
    is_dir = is_dir,
  })
  local segment = renderer.segment(icon, opts)
  return statusline_hl(segment.hl) .. segment.text .. "%*"
end

function M.section_fileinfo(args)
  args = args or {}
  local filetype = vim.bo.filetype
  local icon = M.component()
  if icon == "" and filetype ~= "" then
    icon = M.component({ filetype = filetype })
  end
  local label = filetype
  if icon ~= "" and label ~= "" then
    label = icon .. " " .. label
  elseif icon ~= "" then
    label = icon
  end

  local ok, statusline = pcall(require, "mini.statusline")
  local truncated = ok and statusline.is_truncated(args.trunc_width) or false
  if truncated or vim.bo.buftype ~= "" then
    return label
  end

  local encoding = vim.bo.fileencoding or vim.bo.encoding
  local format = vim.bo.fileformat
  return string.format("%s%s%s[%s] %s", label, label == "" and "" or " ", encoding, format, filesize())
end

local function patch(statusline)
  if statusline._real_icons_patched then
    return true
  end
  if type(statusline.section_fileinfo) ~= "function" then
    return false, "mini.statusline section_fileinfo API is not compatible"
  end
  statusline.section_fileinfo = function(args)
    return M.section_fileinfo(args)
  end
  statusline._real_icons_patched = true
  return true
end

function M.setup()
  local ok, statusline = pcall(require, "mini.statusline")
  if not ok then
    return false, "mini.statusline is not available"
  end

  -- Patch the live module table so default content picks up real icons
  -- regardless of whether mini.statusline was configured before real-icons.
  local patched_ok, patch_err = patch(statusline)
  if not patched_ok then
    return false, patch_err
  end

  if patched then
    return true
  end

  local original_setup = statusline.setup
  if type(original_setup) ~= "function" then
    return false, "mini.statusline setup API is not compatible"
  end

  statusline.setup = function(user_config)
    local result = original_setup(user_config)
    patch(statusline)
    return result
  end

  patched = true
  return true
end

function M.is_patched()
  return patched
end

return M
