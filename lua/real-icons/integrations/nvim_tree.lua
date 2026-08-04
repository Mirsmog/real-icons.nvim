local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local default_decorators = {
  "Git",
  "Open",
  "Hidden",
  "Modified",
  "Bookmark",
  "Diagnostics",
  "Copied",
  "Cut",
}

local patched = false
local integration_mode
local RealIconsDecorator
local original_setup
local original_icon_name_decorated

local function copy_list(values)
  local copy = {}
  for index, value in ipairs(values or {}) do
    copy[index] = value
  end
  return copy
end

local function is_directory_node(node)
  return node
    and (node.type == "directory" or type(node.nodes) == "table" or node.has_children ~= nil)
end

local function icons_enabled(is_dir)
  local ok, config = pcall(require, "nvim-tree.config")
  if not ok then
    return true
  end

  local renderer_config = (config.g or config.d or {}).renderer or {}
  local show = (renderer_config.icons or {}).show or {}
  return show[is_dir and "folder" or "file"] ~= false
end

function M.icon_for_node(node)
  if not node or not node.absolute_path then
    return nil
  end

  local is_dir = is_directory_node(node)
  if not icons_enabled(is_dir) then
    return nil
  end

  local icon = resolver.resolve(is_dir and "directory" or "file", node.absolute_path, {
    is_dir = is_dir,
  })
  local segment = renderer.segment(icon)
  return {
    str = segment.text,
    hl = { segment.hl },
  }
end

local function decorator_defaults()
  local ok, config = pcall(require, "nvim-tree.config")
  local configured = ok
    and config.d
    and config.d.renderer
    and config.d.renderer.decorators
  if type(configured) == "table" then
    return copy_list(configured)
  end
  return copy_list(default_decorators)
end

local function contains_decorator(decorators, target)
  for _, decorator in ipairs(decorators) do
    if decorator == target
        or (type(decorator) == "table" and decorator._real_icons_decorator == true) then
      return true
    end
  end
  return false
end

function M.decorator()
  return RealIconsDecorator
end

function M.mode()
  return integration_mode
end

function M.opts(opts)
  local configured = vim.tbl_deep_extend("force", {}, opts or {})
  configured.renderer = configured.renderer or {}

  local decorators = configured.renderer.decorators
  if type(decorators) ~= "table" then
    decorators = decorator_defaults()
  else
    decorators = copy_list(decorators)
  end

  if RealIconsDecorator and not contains_decorator(decorators, RealIconsDecorator) then
    decorators[#decorators + 1] = RealIconsDecorator
  end
  configured.renderer.decorators = decorators
  return configured
end

local function make_decorator(Decorator)
  if RealIconsDecorator then
    return RealIconsDecorator
  end

  RealIconsDecorator = Decorator:extend()
  RealIconsDecorator._real_icons_decorator = true

  function RealIconsDecorator:new()
    self.enabled = true
    self.highlight_range = "none"
    self.icon_placement = "none"
  end

  function RealIconsDecorator:icon_node(node)
    local ok, icon = pcall(M.icon_for_node, node)
    return ok and icon or nil
  end

  return RealIconsDecorator
end

local function setup_decorator(api)
  if type(api) ~= "table" or type(api.Decorator) ~= "table" or type(api.Decorator.extend) ~= "function" then
    return false
  end

  local ok_tree, nvim_tree = pcall(require, "nvim-tree")
  if not ok_tree or type(nvim_tree.setup) ~= "function" then
    return false
  end

  local existing_patch = nvim_tree._real_icons_setup_patch
  if type(existing_patch) == "table"
      and type(existing_patch.original_setup) == "function"
      and existing_patch.decorator then
    original_setup = existing_patch.original_setup
    RealIconsDecorator = existing_patch.decorator
    integration_mode = "decorator"
    return true
  end

  local ok_decorator = pcall(make_decorator, api.Decorator)
  if not ok_decorator then
    return false
  end

  original_setup = nvim_tree.setup
  nvim_tree.setup = function(user_config)
    return original_setup(M.opts(user_config))
  end
  nvim_tree._real_icons_setup_patch = {
    decorator = RealIconsDecorator,
    original_setup = original_setup,
  }

  if vim.g.NvimTreeSetup == 1 then
    local ok_config, config = pcall(require, "nvim-tree.config")
    local user_config
    if ok_config and type(config.u_clone) == "function" then
      user_config = config.u_clone()
    elseif ok_config then
      user_config = config.u
    end
    original_setup(M.opts(user_config))
  end

  integration_mode = "decorator"
  return true
end

local function setup_legacy()
  local ok, Builder = pcall(require, "nvim-tree.renderer.builder")
  if not ok then
    return false, "nvim-tree is not available"
  end

  if Builder._real_icons_patched then
    integration_mode = "legacy"
    return true
  end

  original_icon_name_decorated = Builder.icon_name_decorated
  if type(original_icon_name_decorated) ~= "function" then
    return false, "nvim-tree renderer builder API is not compatible"
  end

  Builder.icon_name_decorated = function(builder, node)
    local icon, name = original_icon_name_decorated(builder, node)
    if icon and icon.str ~= "" then
      local ok_icon, real_icon = pcall(M.icon_for_node, node)
      if ok_icon and real_icon then
        icon = real_icon
      end
    end
    return icon, name
  end

  Builder._real_icons_patched = true
  integration_mode = "legacy"
  return true
end

function M.setup()
  if patched then
    return true
  end

  local ok_api, api = pcall(require, "nvim-tree.api")
  if ok_api and setup_decorator(api) then
    patched = true
    return true
  end

  local ok, err = setup_legacy()
  if ok then
    patched = true
  end
  return ok, err
end

function M.is_patched()
  return patched
end

return M
