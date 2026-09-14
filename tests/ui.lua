return function(test, eq, truth)
  local icons = require("real-icons")
  local fixture_root = vim.fn.getcwd() .. "/tests/fixtures"
  local function fixture_options()
    return {
      pack = "fixture",
      backend = "disabled",
      packs = { fixture = { type = "vscode", path = fixture_root, manifest = "theme.json" } },
    }
  end

  test("saved custom packs survive setup while explicit configuration wins", function()
    local preferences = require("real-icons.preferences")
    icons.setup(fixture_options())
    truth(preferences.save("fixture"))
    icons.setup({ backend = "disabled" })
    eq(icons.pack(), "fixture")
    eq(icons.resolve("file", "test.test.ts", { is_dir = false }).key, "test")
    icons.setup({ pack = "builtin", backend = "disabled" })
    eq(icons.pack(), "builtin")
    vim.fn.writefile({ "invalid json" }, preferences.path())
    eq(preferences.read(), nil)
    vim.fn.delete(preferences.path())
    icons.setup({ backend = "disabled" })
    eq(icons.pack(), "material")
  end)

  test("dashboard and pack picker support filtering and small terminal sizes", function()
    icons.setup({
      pack = "builtin",
      backend = "disabled",
      packs = { material = { type = "vscode", path = vim.fn.tempname() } },
    })
    local dashboard = require("real-icons.ui.dashboard").open()
    local contents = table.concat(vim.api.nvim_buf_get_lines(dashboard.bufnr, 0, -1, false), "\n")
    truth(contents:find("YOUR SETUP", 1, true))
    truth(contents:find("Font icons", 1, true))
    eq(require("real-icons.ui.dashboard").open(), dashboard, "opening twice reuses the window")
    dashboard.close()
    local picker = icons.select_pack()
    picker.filter("material")
    eq(#picker.filtered, 1)
    eq(picker.filtered[1].name, "material")
    eq(picker.choose(false), false, "missing packs must not silently become the active choice")
    picker.filter("no-such-theme")
    eq(#picker.filtered, 0)
    picker.move(1)
    picker.close()
    local columns, lines = vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 45, 15
    picker = icons.select_pack()
    truth(picker.width <= 41)
    truth(picker.height <= 11)
    picker.filter("builtin")
    truth(picker.choose(false))
    vim.o.columns, vim.o.lines = columns, lines
  end)
end
