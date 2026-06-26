local config = require("real-icons.config")
local packs = require("real-icons.packs")
local discovery = require("real-icons.packs.discovery")

local M = {}

local preview_items = {
  { "directory", "src", "src/" },
  { "directory", "node_modules", "node_modules/" },
  { "file", "README.md", "README.md" },
  { "file", "package.json", "package.json" },
  { "file", "init.lua", "init.lua" },
  { "file", "main.ts", "main.ts" },
  { "file", "Dockerfile", "Dockerfile" },
  { "file", ".gitignore", ".gitignore" },
}
local preview_sample_start = 5

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "real-icons.nvim" })
end

local function title_case(value)
  value = tostring(value or "")
  value = value:gsub("[_%-]+", " ")
  return (value:gsub("(%S)(%S*)", function(first, rest)
    return first:upper() .. rest
  end))
end

local function configured_label(name)
  if name == "builtin" then
    return "Built-in"
  end
  if name == "material" then
    return "Material Icon Theme"
  end
  return title_case(name)
end

local function pack_candidates()
  local result = {}
  local seen = {}

  for _, name in ipairs(packs.names()) do
    result[#result + 1] = {
      name = name,
      label = configured_label(name),
      source = name == "builtin" and "bundled" or "configured",
      kind = "configured",
    }
    seen[name] = true
  end

  for _, candidate in ipairs(discovery.discover()) do
    if not seen[candidate.name] then
      packs.register(candidate.name, candidate.spec)
      result[#result + 1] = candidate
      seen[candidate.name] = true
    end
  end

  local current = config.options.pack
  table.sort(result, function(a, b)
    if a.name == current then
      return true
    end
    if b.name == current then
      return false
    end
    return a.label:lower() < b.label:lower()
  end)
  return result
end

local function make_window_config()
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.min(110, math.max(72, columns - 8))
  local height = math.min(24, math.max(14, lines - 8))
  local row = math.floor((lines - height) / 2 - 1)
  local col = math.floor((columns - width) / 2)
  local list_width = math.floor(width * 0.42)
  local preview_width = width - list_width - 3

  return {
    row = math.max(0, row),
    col = math.max(0, col),
    height = height,
    list_width = list_width,
    preview_width = preview_width,
  }
end

local function set_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

local function close_state(state)
  for _, winid in ipairs({ state.list_win, state.preview_win }) do
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_close(winid, true)
    end
  end
end

local function render_list(state)
  local lines = {}
  local current = config.options.pack
  for index, candidate in ipairs(state.candidates) do
    local marker = candidate.name == current and "*" or " "
    local cursor = index == state.index and ">" or " "
    lines[#lines + 1] = string.format("%s %s %s", cursor, marker, candidate.label)
  end

  set_lines(state.list_buf, lines)
  if vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_win_set_cursor(state.list_win, { state.index, 0 })
  end
end

local function render_preview(state)
  local candidate = state.candidates[state.index]
  if not candidate then
    return
  end

  local icons = require("real-icons")
  local detail = candidate.extension or candidate.source or candidate.name
  local lines = {
    candidate.label,
    detail,
    "",
    "Sample",
  }
  for _, item in ipairs(preview_items) do
    lines[#lines + 1] = item[3]
  end

  set_lines(state.preview_buf, lines)
  icons.clear(state.preview_buf)

  for offset, item in ipairs(preview_items) do
    local row = preview_sample_start + offset - 2
    pcall(icons.render, state.preview_buf, row, 0, item[1], item[2], {
      pack = candidate.name,
    })
  end
end

local function redraw(state)
  render_list(state)
  render_preview(state)
end

local function move(state, delta)
  local count = #state.candidates
  if count == 0 then
    return
  end
  state.index = ((state.index - 1 + delta) % count) + 1
  redraw(state)
end

local function select_current(state)
  local candidate = state.candidates[state.index]
  if not candidate then
    return
  end

  close_state(state)
  local ok, err = require("real-icons").use_pack(candidate.name)
  if not ok then
    notify(err, vim.log.levels.ERROR)
  end
end

local function create_buffer(name)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_set_name(bufnr, name)
  return bufnr
end

function M.open()
  local candidates = pack_candidates()
  if #candidates == 0 then
    notify("No icon packs found", vim.log.levels.WARN)
    return
  end

  local layout = make_window_config()
  local list_buf = create_buffer("real-icons-pack-list")
  local preview_buf = create_buffer("real-icons-pack-preview")

  local list_win = vim.api.nvim_open_win(list_buf, true, {
    relative = "editor",
    row = layout.row,
    col = layout.col,
    width = layout.list_width,
    height = layout.height,
    style = "minimal",
    border = "rounded",
    title = " Icon Packs ",
    title_pos = "center",
  })

  local preview_win = vim.api.nvim_open_win(preview_buf, false, {
    relative = "editor",
    row = layout.row,
    col = layout.col + layout.list_width + 2,
    width = layout.preview_width,
    height = layout.height,
    style = "minimal",
    border = "rounded",
    title = " Preview ",
    title_pos = "center",
  })

  local state = {
    candidates = candidates,
    index = 1,
    list_buf = list_buf,
    list_win = list_win,
    preview_buf = preview_buf,
    preview_win = preview_win,
  }

  vim.wo[list_win].cursorline = true
  vim.wo[preview_win].cursorline = false

  local map_opts = { buffer = list_buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", function() close_state(state) end, map_opts)
  vim.keymap.set("n", "<Esc>", function() close_state(state) end, map_opts)
  vim.keymap.set("n", "j", function() move(state, 1) end, map_opts)
  vim.keymap.set("n", "<Down>", function() move(state, 1) end, map_opts)
  vim.keymap.set("n", "k", function() move(state, -1) end, map_opts)
  vim.keymap.set("n", "<Up>", function() move(state, -1) end, map_opts)
  vim.keymap.set("n", "<CR>", function() select_current(state) end, map_opts)

  redraw(state)
end

return M
