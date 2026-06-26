local assets = require("real-icons.assets")
local backend = require("real-icons.backend.kitty")
local cache = require("real-icons.cache")
local config = require("real-icons.config")
local packs = require("real-icons.packs")
local path_util = require("real-icons.path")

local M = {}

local integrations = {
  { "bufferline", { "bufferline" } },
  { "fzf_lua", { "fzf-lua" } },
  { "lualine", { "lualine" } },
  { "mini_files", { "mini.files" } },
  { "neo_tree", { "neo-tree.defaults" } },
  { "nvim_tree", { "nvim-tree.renderer.builder" } },
  { "oil", { "oil" } },
  { "snacks_picker", { "snacks.picker.format" } },
  { "telescope", { "telescope.make_entry" } },
  {
    "telescope_file_browser",
    {
      "telescope",
      "telescope._extensions.file_browser.make_entry_utils",
    },
  },
}

local function health()
  if vim.health then
    return {
      start = vim.health.start,
      ok = vim.health.ok,
      warn = vim.health.warn,
      error = vim.health.error,
      info = vim.health.info,
    }
  end
  return {
    start = vim.fn["health#report_start"],
    ok = vim.fn["health#report_ok"],
    warn = vim.fn["health#report_warn"],
    error = vim.fn["health#report_error"],
    info = vim.fn["health#report_info"],
  }
end

local function cache_writable()
  local dir = cache.root()
  if not path_util.ensure_dir(dir) then
    return false, "unable to create " .. dir
  end

  local probe = path_util.join(dir, ".healthcheck")
  local ok, result = pcall(vim.fn.writefile, { "ok" }, probe)
  if not ok then
    return false, result
  end
  if result ~= 0 then
    return false, "writefile returned " .. tostring(result)
  end

  vim.fn.delete(probe)
  return true
end

function M.check()
  local h = health()
  h.start("real-icons.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim 0.10+")
  else
    h.error("Neovim 0.10+ is required")
  end

  if vim.o.termguicolors then
    h.ok("termguicolors is enabled")
  else
    h.warn("termguicolors is disabled; image ids need exact foreground colors")
  end

  local detected = backend.detect({ refresh = true })
  if detected.supported then
    h.ok("Terminal detected: " .. detected.terminal .. " via " .. detected.protocol .. " protocol")
  else
    h.warn("No supported terminal detected; real image rendering will use fallback glyphs")
    if detected.reason then
      h.info(detected.reason)
    end
  end

  if detected.tmux then
    h.info("tmux detected")
    local client_term = detected.tmux_client_term or backend.tmux_client_term()
    if client_term and detected.supported then
      h.ok("tmux client terminal is " .. client_term)
    else
      h.warn("tmux client terminal is not recognized: " .. (client_term or "unknown"))
    end

    local passthrough = backend.tmux_passthrough()
    if passthrough == "on" or passthrough == "all" then
      h.ok("tmux allow-passthrough is " .. passthrough)
    else
      h.warn("tmux allow-passthrough is " .. (passthrough or "unknown"))
    end
  end

  for _, integration in ipairs(integrations) do
    local name = integration[1]
    local modules = integration[2]
    if config.options.integrations[name] then
      local missing = {}
      for _, module in ipairs(modules) do
        local ok = pcall(require, module)
        if not ok then
          missing[#missing + 1] = module
        end
      end
      if #missing == 0 then
        h.ok("Integration dependency available: " .. name)
      else
        h.warn(
          "Integration enabled but dependencies are not available: "
            .. name
            .. " ("
            .. table.concat(missing, ", ")
            .. ")"
        )
      end
    end
  end

  local pack = packs.get()
  h.info("Active pack: " .. pack.name)
  local pack_error = packs.last_error(config.options.pack)
  if packs.installed(config.options.pack) then
    if pack_error then
      h.warn("Configured icon pack failed to load; using builtin fallback pack")
      h.info(pack_error)
    else
      h.ok("Active icon pack is available")
    end
  elseif config.options.pack == "material" then
    h.warn("Material icon pack is not installed; using builtin fallback pack")
    h.info("Run :RealIconsInstallPack material")
  else
    h.warn("Configured icon pack is not available; using builtin fallback pack")
  end

  if config.options.pack == "material" and packs.installed("material") then
    h.ok("Material icon pack installed")
  end

  if vim.fn.executable("magick") == 1 then
    h.ok("ImageMagick available for icon conversion")
  else
    h.warn("ImageMagick is not available; SVG icon packs and color transforms cannot be rendered")
  end

  local writable, writable_err = cache_writable()
  if writable then
    h.ok("Icon cache is writable")
  else
    h.warn("Icon cache is not writable: " .. (writable_err or "unknown error"))
  end

  local default_icon = require("real-icons.resolver").resolve("file", "README.md")
  local render_path, cache_err = cache.ensure(default_icon)
  if render_path then
    h.ok("Sample icon can be prepared")
  else
    h.warn("Sample icon cannot be prepared: " .. (cache_err or "unknown error"))
  end

  if assets.exists(assets.file("filetypes", "default")) then
    h.ok("Default file asset found")
  else
    h.error("Missing default file asset at " .. assets.file("filetypes", "default"))
  end

  if assets.exists(assets.file("folders", "default")) then
    h.ok("Default folder asset found")
  else
    h.error("Missing default folder asset at " .. assets.file("folders", "default"))
  end
end

return M
