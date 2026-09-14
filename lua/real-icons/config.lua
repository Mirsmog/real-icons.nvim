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
M.explicit_pack = false

function M.setup(opts)
  opts = opts or {}
  local saved = require("real-icons.preferences").read()
  local defaults = vim.deepcopy(M.defaults)
  if saved and opts.pack == nil then
    defaults.pack = saved.pack
    if saved.spec then
      defaults.packs[saved.pack] = saved.spec
    end
  end
  local options = vim.tbl_deep_extend("force", defaults, opts)
  if type(options.pack) ~= "string" or options.pack == "" then
    error("real-icons pack must be a non-empty string")
  end
  if type(options.integrations) ~= "table" then
    error("real-icons integrations must be a table")
  end
  for name, enabled in pairs(options.integrations) do
    if M.defaults.integrations[name] == nil then
      error("real-icons unknown integration: " .. tostring(name))
    end
    if type(enabled) ~= "boolean" then
      error("real-icons integrations." .. name .. " must be true or false")
    end
  end
  require("real-icons.rules").validate(options.rules)
  M.options = options
  M.explicit_pack = opts.pack ~= nil
  return M.options
end

function M.enable_integration(name)
  M.options.integrations = M.options.integrations or {}
  M.options.integrations[name] = true
  return M.options
end

return M
