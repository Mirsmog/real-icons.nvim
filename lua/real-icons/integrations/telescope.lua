local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local patched = false
local original_gen_from_file

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

local function icon_path(entry)
  return entry.path or entry.filename or entry.value
end

function M.gen_from_file(opts)
  opts = vim.tbl_deep_extend("force", opts or {}, {
    disable_devicons = true,
  })

  local make_entry = require("telescope.make_entry")
  local base = original_gen_from_file or make_entry.gen_from_file
  local base_entry_maker = base(opts)

  return function(line)
    local entry = base_entry_maker(line)
    if not entry then
      return nil
    end

    local base_display = entry.display
    entry.display = function(display_entry)
      local display, path_style = base_display(display_entry)
      local icon = resolver.resolve(icon_path(display_entry), { is_dir = false })
      local segment = renderer.segment(icon)
      local prefix = segment.text .. " "
      local style = {
        { { 0, #segment.text }, segment.hl },
      }

      vim.list_extend(style, offset_styles(path_style, #prefix))
      return prefix .. display, style
    end

    return entry
  end
end

function M.setup()
  if patched then
    return
  end

  require("real-icons.integrations.telescope_file_browser").setup()

  local ok, make_entry = pcall(require, "telescope.make_entry")
  if not ok or make_entry._real_icons_patched then
    patched = true
    return
  end

  original_gen_from_file = make_entry.gen_from_file
  make_entry.gen_from_file = M.gen_from_file
  make_entry._real_icons_patched = true
  patched = true
end

function M.is_patched()
  return patched
end

return M
