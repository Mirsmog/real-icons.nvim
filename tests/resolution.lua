return function(test, eq, truth, with_modules)
  local icons = require("real-icons")
  local fixture_root = vim.fn.getcwd() .. "/tests/fixtures"
  local function fixture_options()
    return {
      pack = "fixture",
      backend = "disabled",
      packs = { fixture = { type = "vscode", path = fixture_root, manifest = "theme.json" } },
    }
  end

  test("compound extensions use the longest match and filename overrides win", function()
    icons.setup(fixture_options())
    eq(icons.resolve("file", "widget.test.ts", { is_dir = false }).key, "test")
    eq(icons.resolve("file", "types.d.ts", { is_dir = false }).key, "types")
    eq(icons.resolve("file", "special.test.ts", { is_dir = false }).key, "plain")
    eq(icons.resolve("file", "WIDGET.TEST.TS", { is_dir = false }).key, "test")
    eq(icons.resolve("file", "widget.test.ts", { is_dir = false, extension = "ts" }).key, "plain")
    local opts = fixture_options()
    opts.overrides = { extensions = { ["test.ts"] = "types" } }
    icons.setup(opts)
    eq(icons.resolve("file", "widget.test.ts", { is_dir = false }).key, "types")
  end)

  test("folder state and light theme changes select different assets", function()
    local background = vim.o.background
    vim.o.background = "dark"
    icons.setup(fixture_options())
    eq(icons.resolve("directory", "src").key, "plain")
    eq(icons.resolve("directory", "src", { expanded = true }).key, "open")
    eq(icons.resolve("file", "unknown", { is_dir = false }).key, "plain")
    vim.o.background = "light"
    eq(icons.resolve("file", "unknown", { is_dir = false }).key, "light")
    vim.o.background = background
  end)

  test("directory fallbacks never ask a file-only provider for an icon", function()
    local file_calls = 0
    with_modules({
      ["nvim-web-devicons"] = {
        get_icon = function()
          file_calls = file_calls + 1
          return "FILE", "DevIconDefault"
        end,
      },
      ["mini.icons"] = {
        get = function()
          return nil
        end,
      },
    }, {}, function()
      local icons = require("real-icons")
      local fallback = require("real-icons.fallback")
      for _, provider in ipairs({ "auto", "devicons" }) do
        icons.setup({ backend = "disabled", fallback = { provider = provider } })
        eq(fallback.get("/project/data", { category = "directory" }).hl, "Directory")
        eq(fallback.get("/project/config.json", { is_dir = true }).icon, "")
      end
      eq(file_calls, 0, "directories bypass nvim-web-devicons")
      eq(fallback.get("/project/app.ts", {}).icon, "FILE")
      eq(file_calls, 1, "files still use nvim-web-devicons")
    end)
    with_modules({
      ["mini.icons"] = {
        get = function(category)
          eq(category, "directory")
          return "FOLDER", "MiniIconsDirectory"
        end,
      },
    }, {}, function()
      require("real-icons").setup({ backend = "disabled", fallback = { provider = "auto" } })
      eq(require("real-icons.fallback").get("/project/data", { is_dir = true }).icon, "FOLDER")
    end)
  end)
end
