local config = require("real-icons.config")
local bit = require("bit")

local M = {}
local uv = vim.uv or vim.loop

local ESC = string.char(27)
local uploaded = {}
local detect_cache

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

local function option_backend()
  local value = config.options.backend
  if value == nil then
    return "auto"
  end
  if value == false then
    return "disabled"
  end
  value = tostring(value):lower()
  if value == "ghostty" then
    return "auto"
  end
  if value == "kitty-graphics" or value == "kitty-placeholder" then
    return "kitty"
  end
  if value == "none" or value == "off" or value == "false" then
    return "disabled"
  end
  return value
end

local function env_lower(name)
  return ((vim.env[name] or "")):lower()
end

local function detect_from_env()
  local term_program = env_lower("TERM_PROGRAM")
  local term = env_lower("TERM")

  if term_program:find("ghostty", 1, true) or vim.env.GHOSTTY_RESOURCES_DIR or vim.env.GHOSTTY_BIN_DIR then
    return "ghostty", "environment"
  end

  if term_program:find("kitty", 1, true) or vim.env.KITTY_WINDOW_ID or term:find("xterm%-kitty") then
    return "kitty", "environment"
  end
end

local function detect_from_tmux()
  local client_term = M.tmux_client_term()
  if not client_term then
    return nil, nil, nil
  end

  if client_term:find("ghostty", 1, true) then
    return "ghostty", "tmux", client_term
  end
  if client_term:find("kitty", 1, true) or client_term:find("xterm%-kitty") then
    return "kitty", "tmux", client_term
  end
  return nil, nil, client_term
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

function M.detect(opts)
  opts = opts or {}
  if detect_cache ~= nil and not opts.refresh then
    return detect_cache
  end

  local backend = option_backend()
  local tmux = M.in_tmux()

  if backend ~= "auto" and backend ~= "kitty" and backend ~= "disabled" then
    detect_cache = {
      supported = false,
      backend = backend,
      protocol = "none",
      terminal = "unsupported",
      tmux = tmux,
      reason = "unknown backend: " .. backend,
    }
    return detect_cache
  end

  if backend == "disabled" then
    detect_cache = {
      supported = false,
      backend = backend,
      protocol = "none",
      terminal = "disabled",
      tmux = tmux,
      reason = "backend disabled",
    }
    return detect_cache
  end

  local terminal, source, tmux_client_term
  if tmux then
    terminal, source, tmux_client_term = detect_from_tmux()
  end

  if not terminal then
    terminal, source = detect_from_env()
    if tmux then
      tmux_client_term = tmux_client_term or M.tmux_client_term()
    end
  end

  local force_kitty = backend == "kitty"
  local supported = terminal ~= nil or force_kitty
  local reason
  if not supported then
    reason = "no Kitty Graphics Protocol compatible terminal detected"
  end
  detect_cache = {
    supported = supported,
    backend = backend,
    protocol = supported and "kitty" or "none",
    terminal = terminal or (force_kitty and "unknown" or "unsupported"),
    tmux = tmux,
    tmux_client_term = tmux_client_term,
    source = source or (force_kitty and "forced" or "none"),
    reason = reason,
  }
  return detect_cache
end

function M.supports_terminal()
  return M.detect().supported
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
  detect_cache = nil
end

return M
