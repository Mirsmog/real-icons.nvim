local root = assert(
  vim.env.REAL_ICONS_TEST_DEPS,
  "Set REAL_ICONS_TEST_DEPS to a directory containing lualine, bufferline, telescope, and plenary checkouts"
)
for _, dependency in ipairs({ "lualine", "bufferline", "telescope", "plenary" }) do
  local path = root .. "/" .. dependency
  assert(vim.fn.isdirectory(path .. "/lua") == 1, "Missing local dependency: " .. path)
  vim.opt.runtimepath:append(path)
end

local icons = require("real-icons")
local lualine = require("lualine")
local bufferline = require("bufferline")
local user_line = { sections = { lualine_c = { "branch", "filename" } } }
lualine.setup(user_line)
bufferline.setup({ options = { numbers = "ordinal" } })
icons.setup({
  pack = "builtin",
  backend = "disabled",
  integrations = { lualine = true, bufferline = true },
})

local function check_line()
  local count = 0
  for _, component in ipairs(lualine.get_config().sections.lualine_c) do
    if type(component) == "table" and component.real_icons_lualine then
      count = count + 1
    end
  end
  assert(count == 1, "Lualine must contain exactly one real icon")
  assert(
    require("bufferline.config").options.get_element_icon,
    "Bufferline callback was not installed"
  )
  assert(
    require("bufferline.config").options.numbers == "ordinal",
    "Bufferline user settings changed"
  )
end
check_line()
print("ok - real lualine and bufferline configured before real-icons")
lualine.setup(user_line)
bufferline.setup({ options = { numbers = "ordinal" } })
check_line()
print("ok - real lualine and bufferline configured after real-icons")

local original_buf = vim.api.nvim_get_current_buf()
local file_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(file_buf, "/tmp/real-icons-lualine-context.lua")
vim.api.nvim_set_current_buf(file_buf)
vim.bo[file_buf].filetype = "lua"
local file_win = vim.api.nvim_get_current_win()
lualine.setup({
  options = {
    globalstatus = true,
    component_separators = "",
    section_separators = "",
    ignore_focus = function(win)
      return vim.api.nvim_win_get_config(win).relative ~= "" or vim.bo.buftype ~= ""
    end,
  },
  sections = {
    lualine_a = { {
      function()
        return "N"
      end,
      padding = 1,
    } },
    lualine_b = {},
    lualine_c = { { "filename", padding = { left = 1, right = 0 } } },
    lualine_x = {},
    lualine_y = {},
    lualine_z = {},
  },
})
local function rendered_line()
  lualine.refresh({ force = true })
  return vim.api.nvim_eval_statusline(
    vim.wo[file_win].statusline,
    { winid = file_win, maxwidth = 140 }
  ).str
end
local segment = require("real-icons.render.placeholder").segment(
  require("real-icons.resolver").resolve(
    "file",
    vim.api.nvim_buf_get_name(file_buf),
    { filetype = "lua" }
  )
)
assert(
  rendered_line():find(segment.text .. " real-icons-lualine-context.lua", 1, true),
  "Icon/file gap must be one cell"
)
print("ok - real Lualine renders a single gap between icon and filename")
local popup_buf = vim.api.nvim_create_buf(false, true)
vim.bo[popup_buf].filetype = "TelescopePrompt"
local popup_win = vim.api.nvim_open_win(popup_buf, true, {
  relative = "editor",
  row = 1,
  col = 1,
  width = 20,
  height = 4,
  style = "minimal",
})
assert(
  require("real-icons.integrations.lualine").component() == "",
  "Prompt must not invent a file icon"
)
assert(
  rendered_line():find(segment.text .. " real-icons-lualine-context.lua", 1, true),
  "Popup stole the file context"
)
vim.api.nvim_win_close(popup_win, true)
vim.api.nvim_buf_delete(popup_buf, { force = true })
vim.cmd("vnew")
local tree_win, tree_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo[tree_buf].buftype = "nofile"
vim.bo[tree_buf].filetype = "NvimTree"
assert(
  require("real-icons.integrations.lualine").component() == "",
  "Tree must not invent a file icon"
)
assert(
  rendered_line():find(segment.text .. " real-icons-lualine-context.lua", 1, true),
  "Tree stole the file context"
)
vim.api.nvim_win_close(tree_win, true)
vim.api.nvim_buf_delete(tree_buf, { force = true })
vim.api.nvim_set_current_buf(original_buf)
vim.api.nvim_buf_delete(file_buf, { force = true })
print("ok - real Lualine preserves file context across popup and tree focus")

local send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function() end
local assets = require("real-icons.assets").dir()
icons.setup({
  pack = "a",
  backend = "kitty",
  integrations = { telescope = true },
  packs = {
    a = { type = "simple", path = assets, file = "filetypes/lua.png" },
    b = { type = "simple", path = assets, file = "filetypes/typescript.png" },
  },
})
local make_entry = require("telescope.make_entry").gen_from_file({})
local entry = make_entry("example.lua")
entry.display(entry)
assert(entry._real_icons_segment.icon.pack == "a")
assert(icons.use_pack("b", { notify = false }))
entry.display(entry)
assert(entry._real_icons_segment.icon.pack == "b")
local hl = entry._real_icons_segment.hl
vim.cmd("colorscheme default")
entry.display(entry)
assert(vim.api.nvim_get_hl(0, { name = hl }).fg, "Telescope image highlight was not restored")
print("ok - real Telescope entries refresh on pack and colorscheme changes")

vim.o.columns, vim.o.lines = 110, 35
local picker = require("telescope.pickers").new({}, {
  prompt_title = "Local integration test",
  finder = require("telescope.finders").new_table({
    results = { "example.lua", "example.ts" },
    entry_maker = make_entry,
  }),
  sorter = require("telescope.config").values.generic_sorter({}),
})
picker:find()
assert(vim.wait(3000, function()
  return picker.manager and picker.manager:num_results() == 2
end, 10))
local row = picker:get_selection_row()
local selected = picker:get_selection()
picker._multi:add(selected)
assert(icons.use_pack("a", { notify = false }))
assert(
  vim.wait(3000, function()
    local item = picker.manager:get_entry(1)
    return item._real_icons_segment and item._real_icons_segment.icon.pack == "a"
  end, 10),
  "Visible Telescope results were not redrawn"
)
assert(picker:get_selection_row() == row, "Pack changes moved the selection")
assert(picker._multi:is_selected(selected), "Pack changes lost multiselection")
require("telescope.actions").close(picker.prompt_bufnr)
print("ok - open Telescope picker refreshes without losing selection or multiselection")

require("real-icons.backend.kitty").clear_uploaded()
vim.api.nvim_chan_send = send
print("integration tests: 6 passed")
vim.cmd("qa!")
