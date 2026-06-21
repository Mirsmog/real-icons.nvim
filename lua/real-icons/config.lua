local M = {}

M.defaults = {
  pack = "material",
  packs = {},
  overrides = {},
  backend = "ghostty",
  size = {
    cols = 2,
    rows = 1,
    pixels = 64,
    padding = 0,
    trim = false,
  },
  fallback = {
    enabled = true,
    provider = "auto",
  },
  integrations = {
    fzf_lua = false,
    bufferline = false,
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
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  return M.options
end

return M
