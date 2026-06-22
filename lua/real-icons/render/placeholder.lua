local backend = require("real-icons.backend.kitty")
local cache = require("real-icons.cache")
local config = require("real-icons.config")

local M = {}

M.ns = vim.api.nvim_create_namespace("real-icons")

local placeholder_char
local diacritics
local placeholder_cache = {}
local segment_cache = {}
local hl_cache = {}

local function init_chars()
  if placeholder_char then
    return
  end
  placeholder_char = vim.fn.nr2char(0x10eeee)
  diacritics = {
    [0] = vim.fn.nr2char(0x0305),
    [1] = vim.fn.nr2char(0x030d),
    [2] = vim.fn.nr2char(0x030e),
  }
end

local function diacritic(n)
  init_chars()
  if not diacritics[n] then
    error("real-icons placeholder renderer supports size.cols from 1 to 3")
  end
  return diacritics[n]
end

local function normalize_cells(cols, rows)
  cols = tonumber(cols) or 1
  rows = tonumber(rows) or 1

  if cols < 1 or cols > 3 or cols % 1 ~= 0 then
    error("real-icons placeholder renderer supports size.cols from 1 to 3")
  end
  if rows ~= 1 then
    error("real-icons placeholder renderer currently supports size.rows = 1")
  end

  return cols, rows
end

local function hl_for_image(image_id, opts)
  opts = opts or {}
  local background = opts.background or opts.bg
  local suffix = ""
  if type(background) == "string" and background ~= "" then
    suffix = background:gsub("[^%w]", "")
  end

  local name = string.format("RealIconsImage%06x%s", image_id, suffix)
  local cache_key = name .. "|" .. tostring(background)
  if hl_cache[cache_key] then
    return name
  end

  local hl = {
    fg = string.format("#%06x", image_id % 0x1000000),
  }
  if background ~= nil then
    hl.bg = background
  end
  vim.api.nvim_set_hl(0, name, hl)
  hl_cache[cache_key] = true
  return name
end

local function size_key(size, color)
  local dimensions = cache.dimensions(size)
  return table.concat({
    dimensions.width,
    dimensions.height,
    size.padding or 0,
    tostring(size.trim ~= false),
    cache.color_key(color),
  }, "x")
end

local function segment_key(icon, size, cols, rows, opts)
  return table.concat({
    icon.pack or "",
    icon.key or "",
    icon.source or icon.asset or "",
    size_key(size, opts.color),
    cols,
    rows,
    opts.background or opts.bg or "",
  }, "|")
end

function M.placeholder(cols, rows)
  cols, rows = normalize_cells(cols, rows)
  local key = cols .. "x" .. rows
  if placeholder_cache[key] then
    return placeholder_cache[key]
  end

  init_chars()
  local lines = {}
  for row = 0, rows - 1 do
    local text = {}
    for col = 0, cols - 1 do
      table.insert(text, placeholder_char .. diacritic(row) .. diacritic(col))
    end
    table.insert(lines, table.concat(text))
  end
  placeholder_cache[key] = lines
  return lines
end

function M.render(bufnr, row, col, icon, opts)
  opts = opts or {}
  local size = opts.size or config.options.size
  local cols = opts.cols or size.cols
  local rows = opts.rows or size.rows
  cols, rows = normalize_cells(cols, rows)
  local use_images = opts.image ~= false and backend.supports_terminal() and vim.o.termguicolors

  if use_images then
    local render_path, cache_err = cache.ensure(icon, { size = size, color = opts.color })
    if render_path then
      icon = vim.tbl_extend("force", icon, { asset = render_path })

      local image_id, err = backend.upload(icon, {
        cols = cols,
        rows = rows,
        size = size,
      })
      if image_id then
        local lines = M.placeholder(cols, rows)
        return vim.api.nvim_buf_set_extmark(bufnr, M.ns, row, col, {
          virt_text = { { lines[1] .. " ", hl_for_image(image_id) } },
          virt_text_pos = "inline",
          priority = opts.priority or 200,
        })
      elseif not config.options.fallback.enabled then
        error(err or cache_err)
      end
    elseif not config.options.fallback.enabled then
      error(cache_err)
    end
  end

  if icon.fallback then
    return vim.api.nvim_buf_set_extmark(bufnr, M.ns, row, col, {
      virt_text = { { icon.fallback.icon .. " ", icon.fallback.hl or "Normal" } },
      virt_text_pos = "inline",
      priority = opts.priority or 200,
    })
  end
end

function M.segment(icon, opts)
  opts = opts or {}
  local size = opts.size or config.options.size
  local cols = opts.cols or size.cols
  local rows = opts.rows or size.rows
  cols, rows = normalize_cells(cols, rows)
  local use_images = opts.image ~= false and backend.supports_terminal() and vim.o.termguicolors

  if use_images then
    local key = segment_key(icon, size, cols, rows, opts)
    if segment_cache[key] then
      return segment_cache[key]
    end

    local render_path = cache.ensure(icon, { size = size, color = opts.color })
    if render_path then
      local render_icon = vim.tbl_extend("force", icon, { asset = render_path })
      local image_id = backend.upload(render_icon, {
        cols = cols,
        rows = rows,
        size = size,
      })
      if image_id then
        local segment = {
          text = M.placeholder(cols, rows)[1],
          hl = hl_for_image(image_id, opts),
          width = cols,
        }
        segment_cache[key] = segment
        return segment
      end
    end
  end

  if icon.fallback then
    return {
      text = icon.fallback.icon,
      hl = icon.fallback.hl or "Normal",
      width = vim.fn.strdisplaywidth(icon.fallback.icon),
    }
  end

  return {
    text = " ",
    hl = "Normal",
    width = 1,
  }
end

function M.clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
end

function M.reset_cache()
  segment_cache = {}
  hl_cache = {}
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("RealIconsRenderer", { clear = true }),
  callback = M.reset_cache,
})

return M
