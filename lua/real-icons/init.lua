local config = require("real-icons.config")
local cache = require("real-icons.cache")
local fallback = require("real-icons.fallback")
local log = require("real-icons.log")
local packs = require("real-icons.packs")
local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")
local backend = require("real-icons.backend.kitty")

local M = {}

local did_setup = false
local integration_order = {
  "oil",
  "bufferline",
  "lualine",
  "telescope",
  "telescope_file_browser",
  "mini_files",
  "neo_tree",
  "nvim_tree",
  "snacks_picker",
}
local integration_modules = {
  bufferline = "real-icons.integrations.bufferline",
  lualine = "real-icons.integrations.lualine",
  mini_files = "real-icons.integrations.mini_files",
  neo_tree = "real-icons.integrations.neo_tree",
  nvim_tree = "real-icons.integrations.nvim_tree",
  oil = "real-icons.integrations.oil",
  snacks_picker = "real-icons.integrations.snacks_picker",
  telescope = "real-icons.integrations.telescope",
  telescope_file_browser = "real-icons.integrations.telescope_file_browser",
}

local function resolve_icon(category, name, opts)
  if type(category) == "table" then
    return category, name or {}
  end
  return resolver.resolve(category, name, opts), opts or {}
end

local function setup_integration(name)
  local module = integration_modules[name]
  if not module then
    return false, "unknown integration: " .. tostring(name)
  end

  local ok, integration = pcall(require, module)
  if not ok then
    return false, integration
  end
  if type(integration.setup) ~= "function" then
    return true
  end

  local setup_ok, result, err = pcall(integration.setup)
  if not setup_ok then
    return false, result
  end
  if result == false then
    return false, err
  end
  return true
end

function M.setup(opts)
  config.setup(opts)
  packs.clear_cache()
  fallback.clear_cache()
  resolver.clear_cache()
  backend.clear_uploaded()
  renderer.reset_cache()
  did_setup = true

  for _, name in ipairs(integration_order) do
    if config.options.integrations[name] then
      setup_integration(name)
    end
  end
end

local function ensure_setup()
  if not did_setup then
    M.setup()
  end
end

function M.get(category, name, opts)
  ensure_setup()
  local segment = M.segment(category, name, opts)
  return segment.text, segment.hl, segment.is_default == true, {
    width = segment.width,
    source = segment.source,
    image = segment.image == true,
    fallback = segment.fallback == true,
    icon = segment.icon,
  }
end

M.icon = M.get
M.get_icon = M.get

function M.segment(category, name, opts)
  ensure_setup()
  local icon, render_opts = resolve_icon(category, name, opts)
  return renderer.segment(icon, render_opts)
end

function M.resolve(category, name, opts)
  ensure_setup()
  return resolver.resolve(category, name, opts)
end

function M.render(bufnr, row, col, category, name, opts)
  ensure_setup()
  local icon
  icon, opts = resolve_icon(category, name, opts)
  return renderer.render(bufnr, row, col, icon, opts)
end

function M.list(category, opts)
  ensure_setup()
  return resolver.list(category, opts)
end

function M.categories()
  return resolver.categories()
end

function M.clear(bufnr)
  renderer.clear(bufnr or vim.api.nvim_get_current_buf())
end

local function clear_rendered_icons()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      renderer.clear(bufnr)
    end
  end
end

local function refresh_known_integrations()
  local ok_oil, oil = pcall(require, "real-icons.integrations.oil")
  if ok_oil then
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "oil" then
        pcall(oil.refresh, bufnr)
      end
    end
  end

  local ok_lualine, lualine = pcall(require, "lualine")
  if ok_lualine and type(lualine.refresh) == "function" then
    pcall(lualine.refresh)
  end

  vim.cmd("redrawstatus")
  vim.cmd("redrawtabline")
  vim.cmd("redraw!")
end

function M.is_supported()
  ensure_setup()
  return backend.detect().supported and vim.o.termguicolors
end

function M.backend()
  ensure_setup()
  if M.is_supported() then
    return backend.in_tmux() and "kitty-placeholder-tmux" or "kitty-placeholder"
  end
  return "fallback"
end

function M.capabilities()
  ensure_setup()
  local detected = backend.detect()
  local images = detected.supported and vim.o.termguicolors
  local reason
  if not images then
    reason = not vim.o.termguicolors and "termguicolors disabled" or detected.reason
  end
  return {
    images = images,
    renderer = M.backend(),
    terminal = detected.terminal,
    protocol = detected.protocol,
    tmux = detected.tmux,
    tmux_client_term = detected.tmux_client_term,
    placeholders = true,
    fallback = config.options.fallback.enabled,
    pack = packs.get().name,
    reason = reason,
  }
end

function M.pack()
  ensure_setup()
  return config.options.pack
end

function M.available_packs()
  ensure_setup()
  return packs.names()
end

function M.discover_packs(opts)
  ensure_setup()
  local candidates = require("real-icons.packs.discovery").discover(opts)
  for _, candidate in ipairs(candidates) do
    packs.register(candidate.name, candidate.spec)
  end
  return candidates
end

function M.select_pack()
  ensure_setup()
  require("real-icons.ui.select_pack").open()
end

function M.enable_integration(name)
  ensure_setup()
  if not integration_modules[name] then
    return false, "unknown integration: " .. tostring(name)
  end
  config.enable_integration(name)
  return setup_integration(name)
end

function M.use_pack(name, opts)
  ensure_setup()
  opts = opts or {}
  name = name and vim.trim(name) or ""

  if name == "" then
    return false, "pack name is required"
  end
  if not packs.source(name) then
    return false, "unknown icon pack: " .. name
  end

  config.options.pack = name
  packs.clear_cache()
  fallback.clear_cache()
  resolver.clear_cache()
  backend.clear_uploaded()
  renderer.reset_cache()
  clear_rendered_icons()
  refresh_known_integrations()

  vim.api.nvim_exec_autocmds("User", {
    pattern = "RealIconsPackChanged",
    data = {
      pack = name,
    },
  })

  if opts.notify ~= false then
    local suffix = packs.installed(name) and "" or " (using bundled fallback until installed)"
    log.info("Using icon pack: " .. name .. suffix)
  end

  return true
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
  local ok, err = cache.clear(pack)
  if not ok then
    log.error(err)
    return false, err
  end
  backend.clear_uploaded()
  renderer.reset_cache()
  log.info("Icon cache cleared")
  return true
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
    "real-icons.nvim terminal image placeholder demo",
    "",
  }
  for _, item in ipairs(items) do
    table.insert(lines, item[1])
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  for index, item in ipairs(items) do
    local row = index + 1
    local icon = resolver.resolve(item[2] and "directory" or "file", item[1])
    renderer.render(bufnr, row, 0, icon)
  end
end

return M
