local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local patched = false

local section_names = {
  "sections",
  "inactive_sections",
  "tabline",
  "winbar",
  "inactive_winbar",
}

local function component_name(component)
  if type(component) == "string" then
    return component
  end
  if type(component) == "table" then
    return component[1]
  end
end

local function is_target_component(component)
  local name = component_name(component)
  return name == "filename" or name == "filetype"
end

local function has_real_icon(section)
  for _, component in ipairs(section or {}) do
    if type(component) == "table" and component.real_icons_lualine then
      return true
    end
  end
  return false
end

local function icon_component(opts)
  return vim.tbl_deep_extend("force", {
    M.component,
    color = nil,
    padding = { left = 0, right = 1 },
    separator = "",
    real_icons_lualine = true,
  }, opts or {})
end

local function insert_icon(section, opts)
  if type(section) ~= "table" or has_real_icon(section) then
    return false
  end

  for index, component in ipairs(section) do
    if is_target_component(component) then
      table.insert(section, index, icon_component(opts))
      return true
    end
  end

  return false
end

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

function M.component(opts)
  opts = opts or {}
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

function M.apply_config(user_config, opts)
  local config = vim.deepcopy(user_config or {})
  opts = opts or {}
  if opts.auto_insert == false then
    return config
  end

  local inserted = false
  for _, section_name in ipairs(section_names) do
    local section_group = config[section_name]
    if type(section_group) == "table" then
      for _, section in pairs(section_group) do
        inserted = insert_icon(section, opts.component) or inserted
      end
    end
  end

  if not inserted and opts.default_section ~= false then
    config = vim.tbl_deep_extend("force", M.opts(opts), config)
  end

  return config
end

function M.opts(opts)
  opts = opts or {}
  return {
    sections = {
      lualine_c = {
        icon_component(opts.component),
        "filename",
      },
    },
  }
end

function M.setup(opts)
  local ok, lualine = pcall(require, "lualine")
  if not ok then
    return false, "lualine.nvim is not available"
  end

  if patched or lualine._real_icons_patched then
    patched = true
    return true
  end

  local original_setup = lualine.setup
  if type(original_setup) ~= "function" then
    return false, "lualine.nvim setup API is not compatible"
  end

  lualine.setup = function(user_config)
    return original_setup(M.apply_config(user_config, opts))
  end

  lualine._real_icons_patched = true
  patched = true
  return true
end

function M.is_patched()
  return patched
end

return M
