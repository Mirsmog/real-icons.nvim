local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local patched = false
local original_icon_name_decorated

local function is_directory_node(node)
  return node
    and (node.type == "directory" or type(node.nodes) == "table" or node.has_children ~= nil)
end

function M.icon_for_node(node)
  if not node or not node.absolute_path then
    return nil
  end

  local icon = resolver.resolve(node.absolute_path, {
    is_dir = is_directory_node(node),
  })
  local segment = renderer.segment(icon)
  return {
    str = segment.text,
    hl = { segment.hl },
  }
end

function M.setup()
  if patched then
    return true
  end

  local ok, Builder = pcall(require, "nvim-tree.renderer.builder")
  if not ok then
    return false, "nvim-tree is not available"
  end

  if Builder._real_icons_patched then
    patched = true
    return true
  end

  original_icon_name_decorated = Builder.icon_name_decorated
  if type(original_icon_name_decorated) ~= "function" then
    return false, "nvim-tree renderer builder API is not compatible"
  end

  Builder.icon_name_decorated = function(builder, node)
    local icon, name = original_icon_name_decorated(builder, node)
    local ok_icon, real_icon = pcall(M.icon_for_node, node)
    if ok_icon and real_icon then
      icon = real_icon
    end
    return icon, name
  end

  Builder._real_icons_patched = true
  patched = true
  return true
end

function M.is_patched()
  return patched
end

return M
