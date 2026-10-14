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

-- Buffers that are not filenames: terminals, sidebars, prompts, unnamed
-- buffers, and URIs. Shared by component() and section_fileinfo() so the
-- guard cannot be bypassed through the filetype fallback.
local function is_guarded_buffer()
  local name = vim.api.nvim_buf_get_name(0)
  return vim.bo.buftype ~= "" or name == "" or name:match("^%w[%w+.-]*://") ~= nil
end

-- Merged mini.statusline icon setting: buffer-local wins, default on.
-- Fail open: an unreadable config keeps icons.
local function icons_enabled()
  local buffer_config = vim.b.ministatusline_config
  if type(buffer_config) == "table" and buffer_config.use_icons ~= nil then
    return buffer_config.use_icons and true or false
  end
  local ok, statusline = pcall(require, "mini.statusline")
  if ok and type(statusline) == "table" and type(statusline.config) == "table" then
    local use_icons = statusline.config.use_icons
    if use_icons ~= nil then
      return use_icons and true or false
    end
  end
  return true
end

-- Explicit component opts for special buffers the guard rejects. Oil
-- resolves its browsed directory so themed folder icons apply; fugitive
-- views resolve the synthetic .git directory so the pack's git folder icon
-- applies; other fugitive:// blobs resolve by their underlying filetype.
-- Returns nil when there is nothing special to render.
local function special_opts(filetype)
  local name = vim.api.nvim_buf_get_name(0)
  local scheme = name:match("^(%w[%w+.-]*)://")
  if filetype == "oil" then
    local dir = name:match("^oil://(.*)$")
    if dir ~= nil and dir ~= "" then
      return { path = dir, is_dir = true }
    end
    return nil
  end
  -- Blame uses a temporary file, and status can also use the index path.
  if filetype == "fugitive" or filetype == "fugitiveblame" then
    return { path = ".git", is_dir = true }
  end
  if scheme == "fugitive" and filetype ~= "" then
    return { filetype = filetype }
  end
  return nil
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
  -- Explicit paths/filetypes allow callers to render a chosen file's icon
  -- and override both the guard and the use_icons setting below.
  if opts.path == nil and opts.filetype == nil then
    if is_guarded_buffer() or not icons_enabled() then
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
  -- Restore the ambient group highlight instead of %*: %* would reset to
  -- the default StatusLine colors and repaint the rest of the fileinfo
  -- section (filetype, encoding) in the wrong colors.
  local restore = opts.restore_hl or "MiniStatuslineFileinfo"
  return statusline_hl(segment.hl) .. segment.text .. statusline_hl(restore)
end

function M.section_fileinfo(args, opts)
  args = args or {}
  opts = opts or {}
  local filetype = vim.bo.filetype
  local icon = ""
  if icons_enabled() then
    icon = M.component(vim.tbl_extend("force", special_opts(filetype) or {}, opts))
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
  statusline.section_fileinfo = function(...)
    return M.section_fileinfo(...)
  end
  statusline._real_icons_patched = true
  return true
end

function M.setup()
  local ok, statusline = pcall(require, "mini.statusline")
  if not ok then
    return false, "mini.statusline is not available"
  end
  -- Validate the required APIs before modifying the module so a
  -- compatibility failure cannot leave a partial patch applied.
  if type(statusline.section_fileinfo) ~= "function" then
    return false, "mini.statusline section_fileinfo API is not compatible"
  end
  if type(statusline.setup) ~= "function" then
    return false, "mini.statusline setup API is not compatible"
  end

  -- Patch the live module table so default content picks up real icons
  -- regardless of whether mini.statusline was configured before real-icons.
  -- Upstream setup() never replaces section_fileinfo, so no wrapper is
  -- needed to survive re-configuration.
  local patched_ok, patch_err = patch(statusline)
  if not patched_ok then
    return false, patch_err
  end

  patched = true
  return true
end

function M.is_patched()
  return patched
end

return M
