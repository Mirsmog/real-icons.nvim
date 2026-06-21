local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local function node_path(node)
  if not node then
    return nil
  end
  if node.path and node.path ~= "" then
    return node.path
  end
  if type(node.get_id) == "function" then
    local ok, id = pcall(node.get_id, node)
    if ok and id and id ~= "" then
      return id
    end
  end
  return node.name
end

local function is_directory(node)
  return node and node.type == "directory"
end

function M.provider(icon, node)
  local path = node_path(node)
  if not path or node.type == "message" then
    return icon
  end

  local resolved = resolver.resolve(path, {
    is_dir = is_directory(node),
  })
  local segment = renderer.segment(resolved)
  return {
    text = segment.text,
    highlight = segment.hl,
  }
end

function M.opts(opts)
  opts = opts or {}
  return {
    default_component_configs = {
      icon = vim.tbl_deep_extend("force", {
        provider = M.provider,
        use_filtered_colors = false,
      }, opts.icon or {}),
    },
  }
end

local function apply_icon_config(config, opts)
  if not config or not config.default_component_configs then
    return false
  end

  config.default_component_configs.icon = vim.tbl_deep_extend(
    "force",
    config.default_component_configs.icon or {},
    M.opts(opts).default_component_configs.icon
  )
  return true
end

function M.setup(opts)
  local ok_defaults, defaults = pcall(require, "neo-tree.defaults")
  if not ok_defaults then
    return false, "neo-tree is not available"
  end

  apply_icon_config(defaults, opts)

  local ok_neo_tree, neo_tree = pcall(require, "neo-tree")
  if ok_neo_tree and neo_tree.config then
    apply_icon_config(neo_tree.config, opts)
  end

  return true
end

return M
