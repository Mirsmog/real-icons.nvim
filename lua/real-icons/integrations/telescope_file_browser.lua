local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local sep = " "
local overlay_ns = vim.api.nvim_create_namespace("real-icons-telescope-selection")
local placeholder_char = vim.fn.nr2char(0x10eeee)
local patched_highlighter = false
local color_autocmd = false
local overlay_hl_cache = {}

local function color(value)
  if type(value) == "number" then
    return string.format("#%06x", value)
  end
  return value
end

local function selected_icon_hl(base_hl)
  if type(base_hl) ~= "string" or not base_hl:match("^RealIconsImage") then
    return nil
  end

  if overlay_hl_cache[base_hl] then
    return overlay_hl_cache[base_hl]
  end

  local ok, icon_hl = pcall(vim.api.nvim_get_hl, 0, { name = base_hl, link = false })
  if not ok or not icon_hl.fg then
    return nil
  end

  local selection = vim.api.nvim_get_hl(0, { name = "TelescopeSelection", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local name = base_hl .. "Selected"
  vim.api.nvim_set_hl(0, name, {
    fg = color(icon_hl.fg),
    bg = color(selection.bg or normal.bg),
  })
  overlay_hl_cache[base_hl] = name
  return name
end

local function protect_selected_icon(highlighter, row)
  local picker = highlighter and highlighter.picker
  local bufnr = picker and picker.results_bufnr
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, overlay_ns, 0, -1)

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line or not line:find(placeholder_char, 1, true) then
    return
  end

  local telescope_entry_ns = vim.api.nvim_get_namespaces().telescope_entry
  if not telescope_entry_ns then
    return
  end

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, telescope_entry_ns, { row, 0 }, { row, -1 }, { details = true })
  for _, mark in ipairs(marks) do
    local start_col = mark[3]
    local details = mark[4] or {}
    local hl_group = type(details.hl_group) == "table" and details.hl_group[#details.hl_group] or details.hl_group
    local selected_hl = selected_icon_hl(hl_group)
    if selected_hl and details.end_col then
      vim.api.nvim_buf_set_extmark(bufnr, overlay_ns, row, start_col, {
        end_col = details.end_col,
        hl_group = selected_hl,
        priority = 10000,
      })
    end
  end
end

local function patch_telescope_highlighter()
  if patched_highlighter then
    return true
  end

  if not color_autocmd then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("RealIconsTelescope", { clear = true }),
      callback = function()
        overlay_hl_cache = {}
      end,
    })
    color_autocmd = true
  end

  local ok, highlights = pcall(require, "telescope.pickers.highlights")
  if not ok or type(highlights.new) ~= "function" then
    return false
  end
  if highlights._real_icons_patched then
    patched_highlighter = true
    return true
  end

  local original_new = highlights.new
  highlights.new = function(...)
    local highlighter = original_new(...)
    if type(highlighter) ~= "table" or highlighter._real_icons_patched then
      return highlighter
    end

    local original_hi_selection = highlighter.hi_selection
    if type(original_hi_selection) ~= "function" then
      return highlighter
    end
    highlighter.hi_selection = function(self, row, caret)
      original_hi_selection(self, row, caret)
      protect_selected_icon(self, row)
    end
    highlighter._real_icons_patched = true

    return highlighter
  end

  highlights._real_icons_patched = true
  patched_highlighter = true
  return true
end

local function get_fb_prompt(state)
  local existing = type(state.get_existing_prompt_bufnrs) == "function"
      and state.get_existing_prompt_bufnrs()
    or {}
  for _, prompt_bufnr in ipairs(existing) do
    local status = state.get_status(prompt_bufnr)
    local picker = status and status.picker
    if picker and picker.finder and picker.finder._browse_files then
      return prompt_bufnr
    end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "TelescopePrompt" then
      return bufnr
    end
  end
end

local function current_status(state)
  local prompt_bufnr = get_fb_prompt(state)
  if type(state.get_status) ~= "function" then
    return nil
  end
  return state.get_status(prompt_bufnr)
end

local function compute_file_width(status, opts, icon_width)
  if not status or not status.results_win or not vim.api.nvim_win_is_valid(status.results_win) then
    return math.max(15, 80 - icon_width - #sep)
  end

  local picker = status.picker or {}
  local total = vim.api.nvim_win_get_width(status.results_win)
    - #(picker.selection_caret or "")
    - icon_width
    - #sep
    - (opts.git_status and (2 + #sep) or 0)

  if type(opts.display_stat) == "table" then
    for _, stat in pairs(opts.display_stat) do
      if type(stat) == "table" then
        total = total - (stat.width or 0) - #sep
      end
    end
  end

  return math.max(15, total)
end

local function offset_styles(styles, offset)
  local shifted = {}
  for _, item in ipairs(styles or {}) do
    shifted[#shifted + 1] = {
      { item[1][1] + offset, item[1][2] + offset },
      item[2],
    }
  end
  return shifted
end

local function entry_segment(entry)
  local path = entry.path or entry.value
  local is_dir = entry.is_dir == true
  if entry._real_icons_path ~= path
      or entry._real_icons_is_dir ~= is_dir
      or not entry._real_icons_segment then
    local icon = resolver.resolve(is_dir and "directory" or "file", path, {
      is_dir = is_dir,
    })
    entry._real_icons_path = path
    entry._real_icons_is_dir = is_dir
    entry._real_icons_segment = renderer.segment(icon)
  end
  return entry._real_icons_segment
end

local function call_base_display(base_display, entry, opts, file_width)
  local previous_width = opts.file_width
  if previous_width == nil then
    opts.file_width = file_width
  end

  local ok, display, styles = pcall(base_display, entry)
  opts.file_width = previous_width
  if not ok then
    error(display, 0)
  end
  return display, styles
end

function M.entry_maker(opts)
  patch_telescope_highlighter()

  opts = opts or {}
  opts._entry_cache = opts._entry_cache or {}
  local upstream_opts = vim.tbl_extend("force", {}, opts, {
    disable_devicons = true,
  })
  local upstream = require("telescope._extensions.file_browser.make_entry")
  local base_entry_maker = upstream(upstream_opts)
  local state = require("telescope.state")

  return function(line)
    local entry = base_entry_maker(line)
    if not entry then
      return nil
    end

    local base_display = entry.display
    if type(base_display) ~= "function" then
      return entry
    end

    entry.display = function(display_entry)
      local segment = entry_segment(display_entry)
      local icon_width = upstream_opts.real_icons_width or segment.width or require("real-icons.config").options.size.cols
      local file_width = compute_file_width(current_status(state), upstream_opts, icon_width)
      local display, styles = call_base_display(base_display, display_entry, upstream_opts, file_width)
      local prefix = segment.text .. sep
      local decorated_styles = {
        { { 0, #segment.text }, segment.hl },
      }

      vim.list_extend(decorated_styles, offset_styles(styles, #prefix))
      return prefix .. (display or ""), decorated_styles
    end

    return entry
  end
end

function M.setup()
  patch_telescope_highlighter()
  return true
end

return M
