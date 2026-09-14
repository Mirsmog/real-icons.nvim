local dependencies = assert(vim.env.REAL_ICONS_TEST_DEPS, "Set REAL_ICONS_TEST_DEPS")
for _, name in ipairs({ "nvim_tree", "devicons" }) do
  local path = dependencies .. "/" .. name
  assert(vim.fn.isdirectory(path .. "/lua") == 1, "Missing local dependency: " .. path)
  vim.opt.runtimepath:append(path)
end
assert(
  vim.fn.executable("magick") == 1 or vim.fn.executable("convert") == 1,
  "ImageMagick is required"
)

vim.o.columns, vim.o.lines = 120, 40
vim.g.loaded_netrw, vim.g.loaded_netrwPlugin = 1, 1
local send = vim.api.nvim_chan_send
vim.api.nvim_chan_send = function() end
require("nvim-web-devicons").setup({})

local root = vim.fn.tempname() .. "/orbit"
for _, name in ipairs({ "data", "docs", "src" }) do
  vim.fn.mkdir(root .. "/" .. name, "p")
end
vim.fn.writefile({ "{}" }, root .. "/data/bookmarks.json")
vim.fn.writefile({ "# Orbit" }, root .. "/docs/guide.md")
vim.fn.writefile({ "return {}" }, root .. "/src/app.lua")

local fixtures = vim.fn.fnamemodify("tests/fixtures", ":p")
local icons = require("real-icons")
icons.setup({
  backend = "kitty",
  pack = "fixture-a",
  integrations = { nvim_tree = true },
  overrides = { folder_names = { src = "open" } },
  packs = {
    ["fixture-a"] = { type = "vscode", path = fixtures, manifest = "theme.json" },
    ["fixture-b"] = { type = "simple", path = fixtures, file = "blue.svg", folder = "blue.svg" },
  },
})
require("nvim-tree").setup({
  git = { enable = false },
  filesystem_watchers = { enable = false },
  renderer = { root_folder_label = ":t" },
})
local api = require("nvim-tree.api")
assert(icons.segment("directory", root .. "/src", { async = false }).image)
api.tree.open({ path = root })
local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
local placeholder = vim.fn.nr2char(0x10eeee)

local function row_for(name)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:sub(-#name - 1) == " " .. name then
      return row, line
    end
  end
  error("Missing tree row: " .. name)
end

local function is_image(name)
  local _, line = row_for(name)
  return line:find(placeholder, 1, true) ~= nil
end

local function correct_image(name, expanded)
  local row = row_for(name)
  local expected = icons.segment("directory", root .. "/" .. name, { expanded = expanded })
  if not expected.image or not is_image(name) then
    return false
  end
  local ns = vim.api.nvim_get_namespaces().NvimTreeHighlights
  for _, mark in
    ipairs(
      vim.api.nvim_buf_get_extmarks(buf, ns, { row - 1, 0 }, { row - 1, -1 }, { details = true })
    )
  do
    if vim.inspect(mark[4].hl_group):find(expected.hl, 1, true) then
      return vim.api.nvim_get_hl(0, { name = expected.hl }).fg ~= nil
    end
  end
  return false
end

assert(
  vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "orbit",
  "Root title contains a temporary path"
)
assert(is_image("src"), "Warm src icon should be ready")
assert(not is_image("data"), "Data icon must start cold for this regression")
local _, initial = row_for("data")
assert(initial:find("", 1, true), "Directory fallback must be a folder")
print("ok - real nvim-tree starts cold folders with a folder glyph and a short root title")

assert(
  vim.wait(10000, function()
    return correct_image("data", false) and correct_image("docs", false)
  end, 20),
  "Cold SVGs did not replace the visible fallback without manual reload"
)
assert(require("real-icons.cache").status().failed == 0)
print("ok - real nvim-tree replaces cold fallback icons automatically")

vim.api.nvim_win_set_cursor(win, { row_for("data"), 0 })
api.node.open.edit()
vim.api.nvim_win_set_cursor(win, { row_for("docs"), 0 })
local selected = vim.api.nvim_win_get_cursor(win)
assert(icons.use_pack("fixture-b", { notify = false }))
assert(
  vim.wait(10000, function()
    return correct_image("data", true)
  end, 20),
  "Pack switch left the old image in nvim-tree"
)
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(win), selected), "Pack switch moved the cursor")
assert(vim.api.nvim_get_current_win() == win, "Pack switch stole focus")
for _, node in ipairs(api.tree.get_nodes().nodes) do
  if node.name == "data" then
    assert(node.open, "Pack switch collapsed a folder")
  end
end
print("ok - real nvim-tree switches packs without losing expansion, focus or selection")

vim.cmd("colorscheme default")
assert(
  vim.wait(5000, function()
    return correct_image("data", true)
  end, 20),
  "Colorscheme change did not restore image highlights"
)
print("ok - real nvim-tree restores image highlights after a colorscheme change")

api.tree.close()
assert(icons.use_pack("fixture-a", { notify = false }))
vim.wait(200, function()
  return false
end, 20)
assert(not api.tree.is_visible(), "Icon refresh reopened a closed tree")
assert(icons.integration_status().nvim_tree.status == "ready")
print("ok - background refresh leaves a closed nvim-tree closed")

require("real-icons.backend.kitty").clear_uploaded()
vim.api.nvim_chan_send = send
print("nvim-tree integration tests: 5 passed")
vim.cmd("qa!")
