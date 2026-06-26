local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local ESC = string.char(27)
local RESET = ESC .. "[0m"

local function fzf_utils()
  local ok, utils = pcall(require, "fzf-lua.utils")
  if ok then
    return utils
  end
end

local function nbsp()
  local utils = fzf_utils()
  return utils and utils.nbsp or vim.fn.nr2char(0x2002)
end

local function strip_ansi(value)
  local utils = fzf_utils()
  if utils then
    return utils.strip_ansi_coloring(value)
  end
  return value:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
end

local function hl_fg(name)
  if not name or name == "" then
    return nil
  end

  local ok, hl = pcall(vim.api.nvim_get_hl, 0, {
    name = name,
    link = false,
  })
  if not ok or not hl or not hl.fg then
    return nil
  end

  return hl.fg
end

local function ansi_fg(color)
  if not color then
    return nil
  end

  local r = math.floor(color / 0x10000) % 0x100
  local g = math.floor(color / 0x100) % 0x100
  local b = color % 0x100
  return string.format("%s[38;2;%d;%d;%dm", ESC, r, g, b)
end

local function colorize(segment)
  local prefix = ansi_fg(hl_fg(segment.hl))
  if not prefix then
    return segment.text
  end
  return prefix .. segment.text .. RESET
end

local function copy_entry_opts(opts)
  local entry_opts = vim.tbl_deep_extend("force", {}, opts or {})
  entry_opts.file_icons = false
  entry_opts.color_icons = false
  entry_opts._fzf_nth_devicons = false
  entry_opts.fn_transform = nil
  entry_opts.fn_preprocess = nil
  entry_opts.fn_postprocess = nil
  return entry_opts
end

local function raw_path(value)
  if not value or value == "" then
    return nil
  end

  local file_part = strip_ansi(value)
  local colon = file_part:find(":", 1, true)
  if colon and colon > 1 then
    file_part = file_part:sub(1, colon - 1)
  end
  return file_part
end

local function entry_path(entry, opts, fallback)
  local path = raw_path(fallback)
  if path then
    return path
  end

  local ok, path_mod = pcall(require, "fzf-lua.path")
  if ok then
    local parsed_ok, parsed = pcall(path_mod.entry_to_file, entry, opts or {})
    if parsed_ok and parsed and parsed.path and parsed.path ~= "" then
      return parsed.path
    end
  end

  return raw_path(entry) or ""
end

local function with_icon(entry, opts, raw)
  if not entry or entry == "" then
    return entry
  end

  local path = entry_path(entry, opts, raw)
  local is_dir = opts and opts._real_icons_is_dir
  if is_dir == nil then
    is_dir = vim.fn.isdirectory(path) == 1
  end

  local icon = resolver.resolve(path, {
    is_dir = is_dir,
  })
  local segment = renderer.segment(icon)
  return colorize(segment) .. nbsp() .. entry
end

function M.transform(line, opts)
  local ok, make_entry = pcall(require, "fzf-lua.make_entry")
  if not ok then
    return line
  end

  local entry = make_entry.file(line, copy_entry_opts(opts))
  return with_icon(entry, opts, line)
end

function M.preprocess(opts)
  local ok, make_entry = pcall(require, "fzf-lua.make_entry")
  if not ok then
    return opts
  end
  return make_entry.preprocess(copy_entry_opts(opts))
end

local function file_opts(extra)
  local opts = {
    file_icons = false,
    color_icons = false,
    multiprocess = false,
    _real_icons_is_dir = false,
    fn_transform = [[return require("real-icons.integrations.fzf_lua").transform]],
    fn_preprocess = [[return require("real-icons.integrations.fzf_lua").preprocess]],
    fzf_opts = {
      ["--ansi"] = true,
      ["--delimiter"] = string.format("[%s]", nbsp()),
      ["--nth"] = "-1..",
    },
    _fzf_nth_devicons = false,
  }

  return vim.tbl_deep_extend("force", opts, extra or {})
end

function M.opts(opts)
  opts = opts or {}
  local shared = file_opts(opts.files)

  return {
    files = vim.deepcopy(shared),
    oldfiles = file_opts(opts.oldfiles),
    history = file_opts(opts.history),
    args = file_opts(opts.args),
    complete_file = file_opts(opts.complete_file),
    git = {
      files = file_opts(opts.git_files or (opts.git and opts.git.files)),
      diff = file_opts(opts.git_diff or (opts.git and opts.git.diff)),
    },
  }
end

function M.setup(opts)
  local ok, fzf_lua = pcall(require, "fzf-lua")
  if not ok then
    return false, "fzf-lua is not available"
  end

  if type(fzf_lua.setup) ~= "function" then
    return false, "fzf-lua setup API is not compatible"
  end

  fzf_lua.setup(M.opts(opts), true)
  return true
end

return M
