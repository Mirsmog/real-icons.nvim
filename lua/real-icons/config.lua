local M = {}

M.defaults = {
  pack = "material",
  packs = {},
  overrides = {},
  rules = {
    directories = {},
  },
  backend = "auto",
  size = {
    cols = 2,
    rows = 1,
    pixels = 64,
    padding = 0,
    trim = false,
    density = "auto",
    oversample = 1.25,
  },
  color = {
    tint = nil,
    saturation = 0,
    brightness = 0,
    hue = 0,
    monochrome = false,
  },
  fallback = {
    enabled = true,
    provider = "auto",
  },
  integrations = {
    bufferline = false,
    fzf_lua = false,
    lualine = false,
    mini_files = false,
    neo_tree = false,
    nvim_tree = false,
    oil = false,
    snacks_picker = false,
    telescope = false,
    telescope_file_browser = false,
  },
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  local options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  require("real-icons.rules").validate(options.rules)
  M.options = options
  return M.options
end

function M.enable_integration(name)
  M.options.integrations = M.options.integrations or {}
  M.options.integrations[name] = true
  return M.options
end

return M
