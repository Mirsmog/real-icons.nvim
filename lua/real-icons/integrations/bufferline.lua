local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local patched = false

function M.get_element_icon(element)
  if not element or not element.path then
    return nil
  end

  local icon = resolver.resolve(element.path, {
    filetype = element.filetype,
    is_dir = element.directory,
  })
  local segment = renderer.segment(icon)
  return segment.text, segment.hl
end

function M.opts(opts)
  opts = opts or {}
  return vim.tbl_deep_extend("force", {
    options = {
      color_icons = true,
      get_element_icon = M.get_element_icon,
    },
  }, opts)
end

function M.setup(opts)
  local ok, bufferline = pcall(require, "bufferline")
  if not ok then
    return false, "bufferline.nvim is not available"
  end

  if patched or bufferline._real_icons_patched then
    patched = true
    return true
  end

  local original_setup = bufferline.setup
  bufferline.setup = function(user_config)
    return original_setup(vim.tbl_deep_extend("force", M.opts(opts), user_config or {}))
  end

  bufferline._real_icons_patched = true
  patched = true
  return true
end

function M.is_patched()
  return patched
end

return M
