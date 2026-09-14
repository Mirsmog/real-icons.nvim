local M = {}

M.labels = {
  bufferline = "Bufferline",
  fzf_lua = "fzf-lua",
  lualine = "Lualine",
  mini_files = "mini.files",
  neo_tree = "Neo-tree",
  nvim_tree = "nvim-tree",
  oil = "Oil",
  snacks_picker = "Snacks picker",
  telescope = "Telescope",
  telescope_file_browser = "Telescope file browser",
}

function M.snapshot()
  local icons = require("real-icons")
  local packs = require("real-icons.packs")
  local capabilities = icons.capabilities()
  local selected = icons.pack()
  return {
    capabilities = capabilities,
    selected_pack = selected,
    active_pack = packs.get().name,
    pack_error = packs.last_error(selected),
    integrations = icons.integration_status(),
    conversion = vim.fn.executable("magick") == 1,
    installing = packs.installing(),
    cache = require("real-icons.cache").status(),
  }
end

function M.report()
  local status = M.snapshot()
  local caps = status.capabilities
  local version = vim.version()
  local lines = {
    "real-icons.nvim diagnostics",
    string.format("Neovim: %d.%d.%d", version.major, version.minor, version.patch),
    "Renderer: " .. caps.renderer,
    "Terminal: " .. caps.terminal,
    "tmux: " .. tostring(caps.tmux),
    "termguicolors: " .. tostring(vim.o.termguicolors),
    "Selected pack: " .. status.selected_pack,
    "Active pack: " .. status.active_pack,
    "ImageMagick: " .. (status.conversion and "available" or "missing"),
    string.format("Cache: %d pending, %d failed", status.cache.pending, status.cache.failed),
  }
  if caps.reason then
    lines[#lines + 1] = "Renderer note: " .. caps.reason
  end
  if status.pack_error then
    lines[#lines + 1] = "Pack note: " .. status.pack_error
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Integrations:"
  for _, name in ipairs(vim.fn.sort(vim.tbl_keys(status.integrations))) do
    local item = status.integrations[name]
    if item.enabled then
      lines[#lines + 1] = "  "
        .. name
        .. ": "
        .. item.status
        .. (item.error and " (" .. item.error .. ")" or "")
    end
  end
  return table.concat(lines, "\n")
end

return M
