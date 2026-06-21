local config = require("real-icons.config")
local cache = require("real-icons.cache")
local log = require("real-icons.log")
local packs = require("real-icons.packs")
local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")
local backend = require("real-icons.backend.kitty")

local M = {}

local did_setup = false

function M.setup(opts)
  config.setup(opts)
  packs.clear_cache()
  did_setup = true

  if config.options.integrations.oil then
    require("real-icons.integrations.oil").setup()
  end
  if config.options.integrations.telescope then
    require("real-icons.integrations.telescope").setup()
  end
  if config.options.integrations.telescope_file_browser then
    require("real-icons.integrations.telescope_file_browser").setup()
  end
  if config.options.integrations.fzf_lua then
    require("real-icons.integrations.fzf_lua").setup()
  end
end

local function ensure_setup()
  if not did_setup then
    M.setup()
  end
end

function M.get(path, opts)
  ensure_setup()
  return resolver.resolve(path, opts)
end

function M.resolve(path, opts)
  return M.get(path, opts)
end

function M.render(bufnr, row, col, icon, opts)
  ensure_setup()
  return renderer.render(bufnr, row, col, icon, opts)
end

function M.clear(bufnr)
  renderer.clear(bufnr or vim.api.nvim_get_current_buf())
end

function M.is_supported()
  ensure_setup()
  return backend.supports_terminal() and vim.o.termguicolors
end

function M.backend()
  ensure_setup()
  if backend.supports_terminal() then
    return backend.in_tmux() and "kitty-placeholder-tmux" or "kitty-placeholder"
  end
  return "fallback"
end

function M.capabilities()
  ensure_setup()
  return {
    images = backend.supports_terminal() and vim.o.termguicolors,
    renderer = M.backend(),
    terminal = backend.supports_terminal() and "ghostty" or "unknown",
    tmux = backend.in_tmux(),
    placeholders = true,
    fallback = config.options.fallback.enabled,
    pack = packs.get().name,
  }
end

function M.install_pack(name, opts)
  ensure_setup()
  local ok, err = packs.install(name or config.options.pack, opts)
  if not ok then
    log.error(err)
  end
  return ok, err
end

function M.clear_cache(pack)
  cache.clear(pack)
  backend.clear_uploaded()
  log.info("Icon cache cleared")
end

function M.build_cache(opts)
  ensure_setup()
  opts = opts or {}
  local pack = packs.get(opts.pack)
  local count = 0
  local failed = 0
  for key, source in pairs(pack.definitions) do
    local icon = {
      pack = pack.name,
      key = key,
      source = source,
    }
    local ok = cache.ensure(icon, opts)
    if ok then
      count = count + 1
    else
      failed = failed + 1
    end
  end
  log.info(string.format("Built %d cached icons%s", count, failed > 0 and ("; failed " .. failed) or ""))
  return count, failed
end

function M.demo()
  ensure_setup()

  local items = {
    { "src", true },
    { "test", true },
    { "init.lua", false },
    { "README.md", false },
    { "package.json", false },
    { "main.ts", false },
    { "app.js", false },
    { "Cargo.toml", false },
    { "notes.txt", false },
  }

  vim.cmd("enew")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_name(bufnr, "real-icons-demo")

  local lines = {
    "real-icons.nvim Ghostty placeholder demo",
    "",
  }
  for _, item in ipairs(items) do
    table.insert(lines, item[1])
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  for index, item in ipairs(items) do
    local row = index + 1
    local icon = resolver.resolve(item[1], { is_dir = item[2] })
    renderer.render(bufnr, row, 0, icon)
  end
end

return M
