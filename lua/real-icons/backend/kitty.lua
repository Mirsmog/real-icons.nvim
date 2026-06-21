local config = require("real-icons.config")
local bit = require("bit")

local M = {}
local uv = vim.uv or vim.loop

local ESC = string.char(27)
local uploaded = {}
local supports_terminal_cache

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64(data)
  return ((data:gsub(".", function(x)
    local byte = x:byte()
    local bits = ""
    for i = 8, 1, -1 do
      bits = bits .. (byte % 2 ^ i - byte % 2 ^ (i - 1) > 0 and "1" or "0")
    end
    return bits
  end) .. "0000"):gsub("%d%d%d?%d?%d?%d?", function(x)
    if #x < 6 then
      return ""
    end
    local c = 0
    for i = 1, 6 do
      c = c + (x:sub(i, i) == "1" and 2 ^ (6 - i) or 0)
    end
    return b64chars:sub(c + 1, c + 1)
  end) .. ({ "", "==", "=" })[#data % 3 + 1])
end

local function send(data)
  data = M.wrap_for_tmux(data)
  if vim.v.stderr and vim.v.stderr > 0 then
    vim.api.nvim_chan_send(vim.v.stderr, data)
  else
    io.stderr:write(data)
    io.stderr:flush()
  end
end

local function command(control, payload)
  send(ESC .. "_G" .. control .. ";" .. (payload or "") .. ESC .. "\\")
end

local function fnv1a(str)
  local hash = 2166136261
  for i = 1, #str do
    hash = bit.bxor(hash, str:byte(i))
    hash = (hash * 16777619) % 4294967296
  end
  return hash
end

function M.in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

function M.tmux_client_term()
  if not M.in_tmux() then
    return nil
  end
  local ok, output = pcall(vim.fn.system, { "tmux", "display-message", "-p", "#{client_termname}" })
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(output):lower()
end

function M.tmux_passthrough()
  if not M.in_tmux() then
    return nil
  end
  local ok, output = pcall(vim.fn.system, { "tmux", "show", "-gv", "allow-passthrough" })
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(output)
end

function M.wrap_for_tmux(data)
  if not M.in_tmux() then
    return data
  end
  return ESC .. "Ptmux;" .. data:gsub(ESC, ESC .. ESC) .. ESC .. "\\"
end

function M.supports_terminal()
  if supports_terminal_cache ~= nil then
    return supports_terminal_cache
  end

  local term_program = (vim.env.TERM_PROGRAM or ""):lower()
  if term_program:find("ghostty", 1, true) then
    supports_terminal_cache = true
    return true
  end
  if vim.env.GHOSTTY_RESOURCES_DIR or vim.env.GHOSTTY_BIN_DIR then
    supports_terminal_cache = true
    return true
  end
  local tmux_term = M.tmux_client_term()
  supports_terminal_cache = tmux_term ~= nil and tmux_term:find("ghostty", 1, true) ~= nil
  return supports_terminal_cache
end

function M.image_id(path)
  return 0x520000 + (fnv1a(path) % 0x0fffff)
end

function M.upload(icon, opts)
  opts = opts or {}
  local image_id = opts.image_id or M.image_id(icon.asset)
  local size = opts.size or config.options.size
  local cols = opts.cols or size.cols
  local rows = opts.rows or size.rows

  if uploaded[image_id] then
    return image_id
  end

  if not icon.asset or not uv.fs_stat(icon.asset) then
    return nil, "asset does not exist: " .. tostring(icon.asset)
  end

  local control = table.concat({
    "a=T",
    "f=100",
    "t=f",
    "q=2",
    "U=1",
    "i=" .. image_id,
    "c=" .. cols,
    "r=" .. rows,
  }, ",")

  command(control, base64(icon.asset))
  uploaded[image_id] = true
  return image_id
end

function M.clear_uploaded()
  uploaded = {}
  supports_terminal_cache = nil
end

return M
