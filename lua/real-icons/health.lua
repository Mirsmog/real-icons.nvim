local assets = require("real-icons.assets")
local backend = require("real-icons.backend.kitty")
local cache = require("real-icons.cache")
local config = require("real-icons.config")
local packs = require("real-icons.packs")

local M = {}

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

  if backend.supports_terminal() then
    h.ok("Ghostty-like environment detected")
  else
    h.warn("Ghostty was not detected; real image rendering will use fallback glyphs")
  end

  if backend.in_tmux() then
    h.info("tmux detected")
    local client_term = backend.tmux_client_term()
    if client_term and client_term:find("ghostty", 1, true) then
      h.ok("tmux client terminal is " .. client_term)
    else
      h.warn("tmux client terminal is not Ghostty: " .. (client_term or "unknown"))
    end

    local passthrough = backend.tmux_passthrough()
    if passthrough == "on" or passthrough == "all" then
      h.ok("tmux allow-passthrough is " .. passthrough)
    else
      h.warn("tmux allow-passthrough is " .. (passthrough or "unknown"))
    end
  end

  local pack = packs.get()
  h.info("Active pack: " .. pack.name)
  if packs.installed(config.options.pack) then
    h.ok("Active icon pack is available")
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
    h.ok("ImageMagick available for SVG conversion")
  else
    h.warn("ImageMagick is not available; SVG icon packs cannot be rendered")
  end

  local default_icon = require("real-icons.resolver").resolve("README.md", { is_dir = false })
  local render_path, cache_err = cache.ensure(default_icon)
  if render_path then
    h.ok("Icon cache is writable")
  else
    h.warn("Icon cache is not ready: " .. (cache_err or "unknown error"))
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
