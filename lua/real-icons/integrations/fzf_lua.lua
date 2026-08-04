local config = require("real-icons.config")
local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local api = vim.api
local uv = vim.uv or vim.loop
local FILE_SLOT_ICON = ""
local DIRECTORY_SLOT_ICON = ""
local PROCESS_BATCH_SIZE = 1
local REDRAW_BATCH_SIZE = 4
local RIGHT_BORDERS = { "│", "┃", "▏", "▕", "▐", "▌" }

local namespace = api.nvim_create_namespace("real-icons-fzf-lua")
local group = api.nvim_create_augroup("RealIconsFzfLua", { clear = true })
local states_by_window = {}
local states_by_buffer = {}
local active_slot
local decoration_provider_ready = false
local work_scheduled = false
local patched = false
local fzf_path

local function slot_columns()
  local size = config.options.size or {}
  local cols = tonumber(size.cols) or 2
  return math.max(1, math.min(3, math.floor(cols)))
end

local function slot_text(icon, cols)
  return icon .. string.rep(" ", math.max(0, cols - 1))
end

local function new_slot()
  local ok, utils = pcall(require, "fzf-lua.utils")
  local nbsp = ok and utils.nbsp or vim.fn.nr2char(0x2002)
  local cols = slot_columns()
  return {
    cols = cols,
    file = slot_text(FILE_SLOT_ICON, cols),
    directory = slot_text(DIRECTORY_SLOT_ICON, cols),
    nbsp = nbsp,
  }
end

local function neutral_devicons_state()
  active_slot = new_slot()
  return {
    icon_padding = nil,
    dir_icon = { icon = active_slot.directory, color = nil },
    default_icon = { icon = active_slot.file, color = nil },
    icons = {
      by_filename_case_sensitive = false,
      by_filename = {},
      by_ext = {},
      by_ext_2part = {},
      ext_has_2part = {},
    },
    bg = vim.o.background,
    termguicolors = vim.o.termguicolors,
    real_icons = {
      slot_cols = active_slot.cols,
      visible_only = true,
    },
  }
end

local function install_neutral_state(devicons)
  local ok = pcall(devicons.set_state, nil, neutral_devicons_state())
  return ok
end

local function trim_candidate(candidate)
  candidate = tostring(candidate or ""):gsub("[ \t\r\n]+$", "")
  for _, border in ipairs(RIGHT_BORDERS) do
    if candidate:sub(-#border) == border then
      candidate = candidate:sub(1, #candidate - #border)
      break
    end
  end
  return candidate:gsub("[ \t\r\n]+$", "")
end

local function line_entry(line, slot)
  if type(line) ~= "string" or line == "" or not slot then
    return nil
  end

  for _, marker in ipairs({ slot.file, slot.directory }) do
    local token = marker .. slot.nbsp
    local start = line:find(token, 1, true)
    if start then
      local candidate = trim_candidate(line:sub(start + #token))
      if candidate ~= "" then
        return candidate, start - 1
      end
    end
  end
end

local function file_path(candidate, opts)
  if not fzf_path or type(fzf_path.entry_to_file) ~= "function" then
    return nil
  end

  local ok, entry = pcall(fzf_path.entry_to_file, candidate, opts or {})
  if not ok or type(entry) ~= "table" then
    return nil
  end

  local path = entry.path or entry.uri
  if type(path) ~= "string" or path == "" then
    return nil
  end
  if path:match("^file://") then
    local uri_ok, filename = pcall(vim.uri_to_fname, path)
    return uri_ok and filename or nil
  end
  if path:match("^[%a%-]+://") then
    return nil
  end
  return path
end

local function render_candidate(state, candidate)
  local path = file_path(candidate, state.opts)
  if not path then
    return false
  end

  local cached = state.segments_by_path[path]
  if cached ~= nil then
    return cached
  end

  local stat = uv.fs_stat(path)
  local is_dir = stat and stat.type == "directory" or false
  local ok, segment = pcall(function()
    local icon = resolver.resolve(is_dir and "directory" or "file", path, {
      is_dir = is_dir,
    })
    return renderer.segment(icon, { cols = state.slot.cols })
  end)
  if not ok or type(segment) ~= "table" then
    state.segments_by_path[path] = false
    return false
  end

  state.segments_by_path[path] = segment
  return segment
end

local function redraw(state)
  if not state or not api.nvim_buf_is_valid(state.bufnr) then
    return
  end
  if type(api.nvim__redraw) == "function" then
    local ok = pcall(api.nvim__redraw, {
      buf = state.bufnr,
      valid = false,
      flush = true,
    })
    if ok then
      return
    end
  end
  pcall(vim.cmd, "redraw!")
end

local request_work

local function process_state(state)
  if not state or states_by_buffer[state.bufnr] ~= state then
    return false
  end

  local processed = 0
  local rendered = 0
  while state.pending_index <= #state.pending and processed < PROCESS_BATCH_SIZE do
    local candidate = state.pending[state.pending_index]
    state.pending_index = state.pending_index + 1
    state.pending_set[candidate] = nil
    if state.visible[candidate] and state.results[candidate] == nil then
      state.results[candidate] = render_candidate(state, candidate)
      rendered = rendered + 1
    end
    processed = processed + 1
  end

  if state.pending_index > #state.pending then
    state.pending = {}
    state.pending_index = 1
  end

  local remaining = #state.pending > 0
  state.dirty = state.dirty + rendered
  if state.dirty > 0 and (state.dirty >= REDRAW_BATCH_SIZE or not remaining) then
    redraw(state)
    state.dirty = 0
  end
  return remaining
end

request_work = function()
  if work_scheduled then
    return
  end
  work_scheduled = true
  vim.schedule(function()
    work_scheduled = false
    local remaining = false
    for _, state in pairs(states_by_buffer) do
      remaining = process_state(state) or remaining
    end
    if remaining then
      request_work()
    end
  end)
end

local function queue_candidate(state, candidate)
  if state.results[candidate] ~= nil or state.pending_set[candidate] then
    return
  end
  state.pending_set[candidate] = true
  state.pending[#state.pending + 1] = candidate
  request_work()
end

local function virtual_chunks(segment, cols)
  local chunks = { { segment.text, segment.hl } }
  local padding = cols - (tonumber(segment.width) or cols)
  if padding > 0 then
    chunks[#chunks + 1] = { string.rep(" ", padding), "Normal" }
  end
  return chunks
end

local function decorate_line(state, bufnr, row)
  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  local candidate, col = line_entry(line, state.slot)
  if not candidate then
    return
  end
  state.visible[candidate] = true

  local segment = state.results[candidate]
  if segment == nil then
    queue_candidate(state, candidate)
    return
  end
  if segment == false then
    return
  end

  pcall(api.nvim_buf_set_extmark, bufnr, namespace, row, col, {
    virt_text = virtual_chunks(segment, state.slot.cols),
    virt_text_pos = "overlay",
    hl_mode = "combine",
    ephemeral = true,
    priority = 250,
  })
end

local function ensure_decoration_provider()
  if decoration_provider_ready then
    return
  end
  api.nvim_set_decoration_provider(namespace, {
    on_win = function(_, winid, bufnr)
      local state = states_by_window[winid]
      if not state or state.bufnr ~= bufnr then
        return false
      end
      state.visible = {}
      return true
    end,
    on_line = function(_, winid, bufnr, row)
      local state = states_by_window[winid]
      if state and state.bufnr == bufnr then
        decorate_line(state, bufnr, row)
      end
    end,
  })
  decoration_provider_ready = true
end

function M.detach(bufnr)
  local state = states_by_buffer[bufnr]
  if not state then
    return
  end
  states_by_buffer[bufnr] = nil
  if states_by_window[state.winid] == state then
    states_by_window[state.winid] = nil
  end
end

function M.attach(winid, bufnr, opts)
  if not winid or not bufnr or not api.nvim_buf_is_valid(bufnr) then
    return false
  end

  ensure_decoration_provider()
  M.detach(bufnr)
  local previous = states_by_window[winid]
  if previous then
    M.detach(previous.bufnr)
  end

  local state = {
    winid = winid,
    bufnr = bufnr,
    opts = opts or {},
    slot = active_slot or new_slot(),
    results = {},
    segments_by_path = {},
    visible = {},
    dirty = 0,
    pending = {},
    pending_index = 1,
    pending_set = {},
  }
  states_by_window[winid] = state
  states_by_buffer[bufnr] = state

  api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      M.detach(bufnr)
    end,
  })
  return true
end

local function refresh_attached()
  for _, state in pairs(states_by_buffer) do
    state.results = {}
    state.segments_by_path = {}
    state.pending = {}
    state.pending_index = 1
    state.pending_set = {}
    state.visible = {}
    state.dirty = 0
    redraw(state)
  end
end

local function patch_devicons(devicons)
  if devicons._real_icons_patched then
    return true
  end
  if type(devicons.load) ~= "function" or type(devicons.set_state) ~= "function" then
    return false, "fzf-lua devicons API is not compatible"
  end

  devicons._real_icons_original_load = devicons.load
  devicons.load = function()
    return install_neutral_state(devicons)
  end
  devicons._real_icons_patched = true
  if not install_neutral_state(devicons) then
    return false, "unable to install the fzf-lua icon slot"
  end
  return true
end

local function patch_window(win)
  if win._real_icons_patched then
    return true
  end
  if type(win.new) ~= "function" then
    return false, "fzf-lua window API is not compatible"
  end

  local original_new = win.new
  win._real_icons_original_new = original_new
  win.new = function(opts)
    if type(opts) == "table"
        and opts._type == "file"
        and not opts._is_fzf_tmux
        and not opts._real_icons_on_create
    then
      opts.winopts = opts.winopts or {}
      local user_on_create = opts.winopts.on_create
      opts.winopts.on_create = function(ctx)
        M.attach(ctx and ctx.winid, ctx and ctx.bufnr, opts)
        if type(user_on_create) == "function" then
          return user_on_create(ctx)
        end
      end
      opts._real_icons_on_create = true
    end
    return original_new(opts)
  end
  win._real_icons_patched = true
  return true
end

function M.opts(opts)
  M.setup()
  return opts or {}
end

function M.setup()
  if patched then
    return true
  end

  local ok_fzf = pcall(require, "fzf-lua")
  if not ok_fzf then
    return false, "fzf-lua is not available"
  end

  local ok_devicons, devicons = pcall(require, "fzf-lua.devicons")
  local ok_win, win = pcall(require, "fzf-lua.win")
  local ok_path, path = pcall(require, "fzf-lua.path")
  if not ok_devicons or not ok_win or not ok_path then
    return false, "fzf-lua integration API is not available"
  end
  fzf_path = path

  local icons_ok, icons_err = patch_devicons(devicons)
  if not icons_ok then
    return false, icons_err
  end
  local win_ok, win_err = patch_window(win)
  if not win_ok then
    return false, win_err
  end

  ensure_decoration_provider()
  api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = refresh_attached,
  })
  api.nvim_create_autocmd("User", {
    group = group,
    pattern = "RealIconsPackChanged",
    callback = refresh_attached,
  })
  patched = true
  return true
end

function M.is_patched()
  return patched
end

function M.is_attached(winid, bufnr)
  local state = states_by_window[winid]
  return state ~= nil and state.bufnr == bufnr
end

M._line_entry = line_entry
M._trim_candidate = trim_candidate

return M
