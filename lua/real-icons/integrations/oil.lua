local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local api = vim.api
local group = api.nvim_create_augroup("RealIconsOil", { clear = true })
local patched = false
local setup_done = false
local oil_api
local oil_constants
local oil_util

local function join(dir, name)
  if dir == "" then
    return name
  end
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

local function export_entry(entry)
  if oil_util and type(oil_util.export_entry) == "function" then
    local ok, item = pcall(oil_util.export_entry, entry)
    if ok and type(item) == "table" then
      return item
    end
  end

  local fields = oil_constants or {}
  return {
    id = entry[fields.FIELD_ID or 1],
    name = entry[fields.FIELD_NAME or 2],
    type = entry[fields.FIELD_TYPE or 3],
    meta = entry[fields.FIELD_META or 4],
  }
end

local function entry_kind(item)
  local kind = item.type
  if kind == "link" and item.meta and item.meta.link_stat then
    kind = item.meta.link_stat.type
  end
  return kind == "directory" and "directory" or "file"
end

local function lookup_name(item)
  local meta = item.meta or {}
  return meta.display_name or meta.link or item.name
end

local function is_absolute(path)
  return path:sub(1, 1) == "/"
    or path:match("^%a:[/\\]") ~= nil
    or path:sub(1, 2) == "\\\\"
end

local function entry_path(item, bufnr)
  local name = lookup_name(item)
  if type(name) ~= "string" or name == "" then
    return item.name
  end
  if is_absolute(name) or name:match("^[%a%-]+://") then
    return name
  end

  if oil_api and type(oil_api.get_current_dir) == "function" then
    local ok, dir = pcall(oil_api.get_current_dir, bufnr)
    if ok and type(dir) == "string" and dir ~= "" then
      return join(dir, name)
    end
  end

  local bufname = api.nvim_buf_is_valid(bufnr) and api.nvim_buf_get_name(bufnr) or ""
  return join(bufname, name)
end

local function configured_highlight(conf, text, segment)
  if segment.image or not conf or conf.highlight == nil then
    return segment.hl
  end
  if type(conf.highlight) == "function" then
    local ok, hl = pcall(conf.highlight, text)
    return ok and hl or segment.hl
  end
  return conf.highlight
end

function M.render(entry, conf, bufnr)
  local item = export_entry(entry)
  if type(item.name) ~= "string" or item.name == "" then
    return nil
  end

  local kind = entry_kind(item)
  local path = entry_path(item, bufnr)
  local icon = resolver.resolve(kind, path, {
    is_dir = kind == "directory",
  })
  local segment = renderer.segment(icon)
  local text = segment.text
  if not conf or conf.add_padding ~= false then
    text = text .. " "
  end
  return { text, configured_highlight(conf, text, segment) }
end

local function parse(line)
  return line:match("^(%S+)%s+(.*)$")
end

local function install_column()
  if patched then
    return true
  end

  local ok_columns, columns = pcall(require, "oil.columns")
  if not ok_columns then
    return false, "oil.nvim is not available"
  end
  if type(columns.register) ~= "function" then
    return false, "oil.nvim columns API is not compatible"
  end

  local ok_constants, constants = pcall(require, "oil.constants")
  local ok_util, util = pcall(require, "oil.util")
  local ok_oil, oil = pcall(require, "oil")
  oil_constants = ok_constants and constants or nil
  oil_util = ok_util and util or nil
  oil_api = ok_oil and oil or nil

  columns.register("icon", {
    render = M.render,
    parse = parse,
  })
  patched = true
  return true
end

function M.refresh(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  if not api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].filetype ~= "oil" then
    return false, "not an Oil buffer"
  end
  if vim.bo[bufnr].modified then
    return false, "Oil buffer has unsaved changes"
  end

  local ok, view = pcall(require, "oil.view")
  if not ok or type(view.render_buffer_async) ~= "function" then
    return false, "oil.nvim view API is not compatible"
  end
  view.render_buffer_async(bufnr, { refetch = false })
  return true
end

local function schedule_refresh(bufnr)
  vim.schedule(function()
    if api.nvim_buf_is_valid(bufnr) and not vim.bo[bufnr].modified then
      pcall(M.refresh, bufnr)
    end
  end)
end

function M.attach(bufnr)
  local ok, err = install_column()
  if not ok then
    return false, err
  end
  bufnr = bufnr or api.nvim_get_current_buf()
  if api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].filetype == "oil" then
    schedule_refresh(bufnr)
  end
  return true
end

function M.attach_current()
  return M.attach(api.nvim_get_current_buf())
end

function M.setup()
  if not setup_done then
    api.nvim_create_autocmd("FileType", {
      group = group,
      pattern = "oil",
      callback = function(args)
        local was_patched = patched
        local ok = install_column()
        if ok and not was_patched then
          schedule_refresh(args.buf)
        end
      end,
    })
    setup_done = true
  end

  local ok, err = install_column()
  if ok or err == "oil.nvim is not available" then
    return true
  end
  return false, err
end

function M.is_patched()
  return patched
end

return M
