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

  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local name = base_hl .. "Selected"
  vim.api.nvim_set_hl(0, name, {
    fg = color(icon_hl.fg),
    bg = color(normal.bg),
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
    return
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
  if not ok or type(highlights.new) ~= "function" or highlights._real_icons_patched then
    patched_highlighter = true
    return
  end

  local original_new = highlights.new
  highlights.new = function(...)
    local highlighter = original_new(...)
    if type(highlighter) ~= "table" then
      return highlighter
    end
    if highlighter._real_icons_patched then
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
end

local function get_fb_prompt(state)
  local existing_prompt_bufnrs = state.get_existing_prompt_bufnrs and state.get_existing_prompt_bufnrs() or {}
  for _, prompt_bufnr in ipairs(existing_prompt_bufnrs) do
    local status = state.get_status(prompt_bufnr)
    local picker = status and status.picker
    if picker and picker.finder and picker.finder._browse_files then
      return prompt_bufnr
    end
  end

  local prompt_bufnrs = vim.tbl_filter(function(bufnr)
    return vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "TelescopePrompt"
  end, vim.api.nvim_list_bufs())

  return prompt_bufnrs[1]
end

local function compute_file_width(status, opts, icon_width, stat_enum)
  if not status or not status.results_win or not vim.api.nvim_win_is_valid(status.results_win) then
    return 80
  end

  local picker = status.picker or {}
  local selection_caret = picker.selection_caret or ""
  local total = vim.api.nvim_win_get_width(status.results_win)
    - #selection_caret
    - icon_width
    - #sep
    - (opts.git_status and (2 + #sep) or 0)

  if opts.display_stat then
    for key, value in pairs(opts.display_stat) do
      local default = stat_enum[key]
      if default == nil then
        opts.display_stat[key] = nil
      else
        if type(value) == "table" then
          opts.display_stat[key] = vim.tbl_deep_extend("keep", value, default)
        else
          opts.display_stat[key] = default
        end
        total = total - (opts.display_stat[key].width or 0) - #sep
      end
    end
  end

  return total
end

local function make_display_path(entry, opts, parent_dir, deps)
  local tail = deps.fb_utils.sanitize_path_str(entry.ordinal)
  local display = deps.telescope_utils.transform_path(opts, tail)

  if entry.is_dir then
    if entry.path == parent_dir then
      display = ".."
    end
    display = display .. deps.os_sep
  end

  return display
end

function M.entry_maker(opts)
  patch_telescope_highlighter()
  opts._entry_cache = opts._entry_cache or {}

  local deps = {
    Path = require("plenary.path"),
    entry_display = require("telescope.pickers.entry_display"),
    fb_git = require("telescope._extensions.file_browser.git"),
    fb_make_entry_utils = require("telescope._extensions.file_browser.make_entry_utils"),
    fb_utils = require("telescope._extensions.file_browser.utils"),
    fs_stat = require("telescope._extensions.file_browser.fs_stat"),
    log = require("telescope.log"),
    state = require("telescope.state"),
    strings = require("plenary.strings"),
    telescope_utils = require("telescope.utils"),
  }
  deps.os_sep = deps.Path.path.sep

  local stat_enum = {
    size = deps.fs_stat.size,
    date = deps.fs_stat.date,
    mode = deps.fs_stat.mode,
  }

  local prompt_bufnr = get_fb_prompt(deps.state)
  local status = deps.state.get_status(prompt_bufnr)
  local parent_dir = deps.fb_utils.sanitize_path_str(deps.Path:new(opts.cwd):parent():absolute())
  local icon_width = opts.real_icons_width or require("real-icons.config").options.size.cols
  local total_file_width = compute_file_width(status, opts, icon_width, stat_enum)
  local mt = { cwd = deps.fb_utils.sanitize_path_str(opts.cwd) }

  mt.display = function(entry)
    if type(prompt_bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(prompt_bufnr) then
      prompt_bufnr = get_fb_prompt(deps.state)
    end

    local icon = resolver.resolve(entry.is_dir and "directory" or "file", entry.path)
    local segment = renderer.segment(icon)
    local display_path = make_display_path(entry, opts, parent_dir, deps)
    local file_width = vim.F.if_nil(opts.file_width, math.max(15, total_file_width))

    if #display_path > file_width then
      display_path = deps.strings.truncate(display_path, file_width, nil, -1)
    end

    local widths = {
      { width = segment.width or icon_width },
      { width = file_width },
    }

    local display_array = {
      { segment.text, segment.hl },
      entry.stat and (entry.is_dir and { display_path, "TelescopePreviewDirectory" } or display_path)
        or { display_path, "WarningMsg" },
    }

    if opts.git_status then
      table.insert(widths, 2, { width = 2 })
      if entry.path == parent_dir then
        table.insert(display_array, 2, "  ")
      else
        table.insert(display_array, 2, entry.git_status)
      end
    end

    if entry.stat and opts.display_stat then
      for _, stat in ipairs({ "mode", "size", "date" }) do
        local item = opts.display_stat[stat]
        if item then
          table.insert(widths, { width = item.width, right_justify = item.right_justify })
          table.insert(display_array, item.display(entry))
        end
      end
    end

    return deps.entry_display.create({
      separator = sep,
      items = widths,
      prompt_bufnr = prompt_bufnr,
    })(display_array)
  end

  mt.__index = function(entry, key)
    local raw = rawget(mt, key)
    if raw then
      return raw
    end

    if key == "git_status" then
      local git_file_status = opts.git_file_status or {}
      local git_status
      if entry.is_dir then
        if not vim.tbl_isempty(git_file_status) then
          for git_path, value in pairs(git_file_status) do
            if git_path:sub(1, #entry.value) == entry.value then
              git_status = value
              break
            end
          end
        end
      else
        git_status = vim.F.if_nil(git_file_status[entry.value], "  ")
      end
      return deps.fb_git.make_display(opts, git_status)
    end

    if key == "stat" then
      entry.stat = vim.F.if_nil(vim.loop.fs_stat(entry.value), false)
      if not entry.stat then
        return entry.lstat
      end
      return entry.stat
    end

    if key == "lstat" then
      local lstat = vim.F.if_nil(vim.loop.fs_lstat(entry.value), false)
      if not lstat then
        deps.log.warn("Unable to get stat for " .. entry.value)
        entry.lstat = false
      else
        entry.lstat = lstat
      end
      return entry.lstat
    end

    return rawget(entry, rawget({ value = "path" }, key))
  end

  return function(absolute_path)
    absolute_path = deps.fb_utils.sanitize_path_str(absolute_path)
    local path = deps.Path:new(absolute_path)
    local is_dir = path:is_dir()
    local entry = setmetatable({
      absolute_path,
      ordinal = deps.fb_make_entry_utils.get_ordinal_path(absolute_path, opts.cwd, parent_dir),
      Path = path,
      path = absolute_path,
      is_dir = is_dir,
    }, mt)

    local cached_entry = opts._entry_cache[absolute_path]
    if cached_entry then
      cached_entry.is_dir = is_dir
      cached_entry.path = absolute_path
      cached_entry.Path = path
      cached_entry.ordinal = entry.ordinal
      cached_entry.display = entry.display
      cached_entry.cwd = opts.cwd
      return cached_entry
    end

    opts._entry_cache[absolute_path] = entry
    return entry
  end
end

function M.setup()
  patch_telescope_highlighter()
end

return M
