local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local patched = false

function M.prefix(fs_entry)
  if not fs_entry or not fs_entry.path then
    return "", ""
  end

  local icon = resolver.resolve(fs_entry.path, {
    is_dir = fs_entry.fs_type == "directory",
  })
  local segment = renderer.segment(icon)
  return segment.text .. " ", segment.hl
end

function M.opts(opts)
  opts = opts or {}
  return vim.tbl_deep_extend("force", {
    content = {
      prefix = M.prefix,
    },
  }, opts)
end

local function apply_config(files, opts)
  if not files.config then
    return false
  end

  files.config = vim.tbl_deep_extend("force", files.config, M.opts(opts))
  return true
end

function M.setup(opts)
  local ok, files = pcall(require, "mini.files")
  if not ok then
    return false, "mini.files is not available"
  end

  apply_config(files, opts)

  if patched or files._real_icons_patched then
    patched = true
    return true
  end

  local original_setup = files.setup
  files.setup = function(user_config)
    return original_setup(M.opts(vim.tbl_deep_extend("force", opts or {}, user_config or {})))
  end

  files._real_icons_patched = true
  patched = true
  return true
end

function M.is_patched()
  return patched
end

return M
