local backend = require("real-icons.backend.kitty")
local cache = require("real-icons.cache")
local config = require("real-icons.config")
local packs = require("real-icons.packs")
local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local state_cache = {}
local originals = {}

local function table_count(tbl)
  local count = 0
  for _ in pairs(tbl or {}) do
    count = count + 1
  end
  return count
end

local function normalize_key(value)
  if type(value) == "table" then
    return value.icon or value.name
  end
  return value
end

local function icon_entry(category, name)
  local ok_icon, icon = pcall(resolver.resolve, category, name, { fallback = false })
  if not ok_icon or type(icon) ~= "table" then
    return nil
  end

  local ok_segment, segment = pcall(renderer.segment, icon)
  if not ok_segment or type(segment) ~= "table" or segment.source ~= "image" then
    return nil
  end

  local ok_hl, hl = pcall(vim.api.nvim_get_hl, 0, {
    name = segment.hl,
    link = false,
  })
  if not ok_hl or type(hl) ~= "table" or not hl.fg then
    return nil
  end

  return {
    icon = segment.text,
    color = string.format("#%06x", hl.fg),
  }
end

local function last_extension(ext)
  return ext:match("([^.]+)$")
end

local function add_extension(state, ext, entry)
  ext = tostring(ext or ""):gsub("^%.+", ""):lower()
  if ext == "" or not entry then
    return
  end

  if ext:find(".", 1, true) then
    state.icons.by_ext_2part[ext] = entry
    local tail = last_extension(ext)
    if tail then
      state.icons.ext_has_2part[tail] = true
    end
  else
    state.icons.by_ext[ext] = entry
  end
end

local function state_key(pack, opts)
  local size = config.options.size or {}
  opts = opts or {}
  return table.concat({
    pack.name or "",
    vim.o.background or "",
    tostring(vim.o.termguicolors),
    tostring(size.cols or ""),
    tostring(size.rows or ""),
    vim.inspect(size.pixels or ""),
    tostring(size.padding or ""),
    tostring(size.trim ~= false),
    cache.color_key(config.options.color),
    tostring(opts.icon_padding or ""),
  }, "|")
end

local function add_map(target, source, category, entry_cache, normalize)
  for name, value in pairs(source or {}) do
    local key = normalize_key(value)
    if key then
      local entry = entry_cache[key]
      if entry == nil then
        entry = icon_entry(category, name)
        entry_cache[key] = entry or false
      end
      if entry then
        target[normalize and normalize(name) or name] = entry
      end
    end
  end
end

local function build_state(opts)
  opts = opts or {}
  if not vim.o.termguicolors or not backend.supports_terminal() then
    return nil
  end

  local pack = packs.get()
  local key = state_key(pack, opts)
  if state_cache[key] then
    return state_cache[key]
  end

  local default_icon = icon_entry("file", "")
  local dir_icon = icon_entry("directory", "")
  if not default_icon or not dir_icon then
    return nil
  end

  local state = {
    icon_padding = type(opts.icon_padding) == "string" and opts.icon_padding or nil,
    dir_icon = dir_icon,
    default_icon = default_icon,
    icons = {
      by_filename_case_sensitive = false,
      by_filename = {},
      by_filetype = {},
      by_ext = {},
      by_ext_2part = {},
      ext_has_2part = {},
    },
    bg = vim.o.bg,
    termguicolors = vim.o.termguicolors,
    real_icons = {
      pack = pack.name,
      files = table_count(pack.file_names),
      extensions = table_count(pack.file_extensions),
      filetypes = table_count(pack.language_ids),
    },
  }

  local entries = {}

  add_map(state.icons.by_filename, pack.file_names, "file", entries, function(name)
    return tostring(name):lower()
  end)

  for ext, value in pairs(pack.file_extensions or {}) do
    local key_name = normalize_key(value)
    if key_name then
      local entry = entries[key_name]
      if entry == nil then
        entry = icon_entry("extension", ext)
        entries[key_name] = entry or false
      end
      add_extension(state, ext, entry)
    end
  end

  add_map(state.icons.by_filetype, pack.language_ids, "filetype", entries)

  state_cache[key] = state
  return state
end

local function clear_state_cache()
  state_cache = {}
end

local function load_real_icons(devicons, opts)
  local state = build_state(opts)
  if not state then
    return false
  end

  devicons.set_state(nil, state)
  return true
end

local function patch_devicons(devicons)
  if devicons._real_icons_patched then
    return true
  end
  if type(devicons.load) ~= "function" or type(devicons.set_state) ~= "function" then
    return false, "fzf-lua devicons API is not compatible"
  end

  originals.load = devicons.load
  originals.unload = devicons.unload

  devicons.load = function(opts)
    opts = opts or {}
    local original_ok = originals.load(opts)
    local real_ok = load_real_icons(devicons, opts)
    return real_ok or original_ok
  end

  if type(devicons.unload) == "function" then
    devicons.unload = function(...)
      clear_state_cache()
      return originals.unload(...)
    end
  end

  devicons._real_icons_patched = true

  vim.api.nvim_create_autocmd({ "ColorScheme" }, {
    group = vim.api.nvim_create_augroup("RealIconsFzfLua", { clear = true }),
    callback = clear_state_cache,
  })

  vim.api.nvim_create_autocmd("User", {
    group = "RealIconsFzfLua",
    pattern = "RealIconsPackChanged",
    callback = clear_state_cache,
  })

  return true
end

function M.opts(opts)
  M.setup()
  return opts or {}
end

function M.setup()
  local ok, devicons = pcall(require, "fzf-lua.devicons")
  if not ok then
    return false, "fzf-lua is not available"
  end

  return patch_devicons(devicons)
end

return M
