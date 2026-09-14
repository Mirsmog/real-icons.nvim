local backend = require("real-icons.backend.kitty")
local cache = require("real-icons.cache")
local config = require("real-icons.config")
local events = require("real-icons.events")

local M = {}
M.generation = 0

M.ns = vim.api.nvim_create_namespace("real-icons")

local placeholder_char
local diacritics
local placeholder_cache = {}
local segment_cache = {}
local hl_cache = {}
local rendered = {}

local function asset_ready()
  M.generation = M.generation + 1
  events.changed("cache")
end

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
    cache.density_key(size),
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

local function with_icon_meta(segment, icon)
  return vim.tbl_extend("force", {}, segment, {
    generation = M.generation,
    icon = icon,
    is_default = icon.is_default == true,
  })
end

local function image_segment(icon, size, cols, rows, opts)
  local key = segment_key(icon, size, cols, rows, opts)
  if segment_cache[key] then
    return segment_cache[key]
  end

  local prepare = opts.async == false and cache.ensure or cache.ensure_async
  local render_path, cache_err = prepare(icon, { size = size, color = opts.color }, asset_ready)
  if not render_path then
    return nil, cache_err
  end

  local render_icon = vim.tbl_extend("force", icon, { asset = render_path })
  local image_id, upload_err = backend.upload(render_icon, {
    cols = cols,
    rows = rows,
    size = size,
  })
  if not image_id then
    return nil, upload_err or cache_err
  end

  local segment = {
    text = M.placeholder(cols, rows)[1],
    hl = hl_for_image(image_id, opts),
    width = cols,
    source = "image",
    image = true,
    fallback = false,
  }
  segment_cache[key] = segment
  return segment
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
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local segment = M.segment(icon, opts)
  local id = vim.api.nvim_buf_set_extmark(bufnr, M.ns, row, col, {
    id = opts.id,
    virt_text = { { segment.text .. " ", segment.hl } },
    virt_text_pos = "inline",
    priority = opts.priority or 200,
  })
  rendered[bufnr] = rendered[bufnr] or {}
  rendered[bufnr][id] = { icon = icon, opts = vim.tbl_extend("force", {}, opts, { id = id }) }
  return id
end

function M.segment(icon, opts)
  opts = opts or {}
  local size = opts.size or config.options.size
  local cols = opts.cols or size.cols
  local rows = opts.rows or size.rows
  cols, rows = normalize_cells(cols, rows)
  local use_images = opts.image ~= false and backend.supports_terminal() and vim.o.termguicolors

  local image_error
  if use_images then
    local segment, err = image_segment(icon, size, cols, rows, opts)
    image_error = err
    if segment then
      return with_icon_meta(segment, icon)
    end
  end

  if icon.fallback then
    local text = icon.fallback.icon
    local width = vim.fn.strdisplaywidth(text)
    if image_error == "pending" then
      text = text .. string.rep(" ", math.max(0, cols - width))
      width = math.max(cols, width)
    end
    return {
      generation = M.generation,
      pending = image_error == "pending",
      text = text,
      hl = icon.fallback.hl or "Normal",
      width = width,
      source = "fallback",
      image = false,
      fallback = true,
      is_default = icon.is_default == true,
      icon = icon,
    }
  end

  return {
    generation = M.generation,
    pending = image_error == "pending",
    text = string.rep(" ", cols),
    hl = "Normal",
    width = cols,
    source = "empty",
    image = false,
    fallback = true,
    is_default = true,
    icon = icon,
  }
end

function M.clear(bufnr)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  rendered[bufnr] = nil
end

function M.refresh()
  for bufnr, marks in pairs(rendered) do
    if not vim.api.nvim_buf_is_valid(bufnr) then
      rendered[bufnr] = nil
    else
      for id, request in pairs(marks) do
        local position = vim.api.nvim_buf_get_extmark_by_id(bufnr, M.ns, id, {})
        if #position == 0 then
          marks[id] = nil
        else
          local icon = request.icon
          if icon.category and icon.path then
            icon = require("real-icons.resolver").resolve(
              icon.category,
              icon.path,
              vim.tbl_extend("force", {}, request.opts, {
                is_dir = icon.kind == "directory",
                filetype = icon.filetype,
              })
            )
          end
          M.render(bufnr, position[1], position[2], icon, request.opts)
        end
      end
    end
  end
end

function M.reset_cache()
  M.generation = M.generation + 1
  segment_cache = {}
  hl_cache = {}
end

local group = vim.api.nvim_create_augroup("RealIconsRenderer", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function()
    M.reset_cache()
    events.changed("colorscheme")
  end,
})
vim.api.nvim_create_autocmd("OptionSet", {
  group = group,
  pattern = { "background", "termguicolors" },
  callback = function()
    M.reset_cache()
    events.changed("colorscheme")
  end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(args)
    rendered[args.buf] = nil
  end,
})

return M
