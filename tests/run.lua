local failures = {}
local passed = 0
local skipped = 0

local function fail(message)
  error(message, 2)
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    fail(string.format(
      "%s: expected %s, got %s",
      message or "values differ",
      vim.inspect(expected),
      vim.inspect(actual)
    ))
  end
end

local function assert_true(value, message)
  if not value then
    fail(message or "expected a truthy value")
  end
end

local function test(name, callback)
  local ok, err = xpcall(callback, debug.traceback)
  if ok then
    passed = passed + 1
    print("ok - " .. name)
  else
    failures[#failures + 1] = { name = name, error = err }
    print("not ok - " .. name)
  end
end

local function skip(name, reason)
  skipped = skipped + 1
  print("skip - " .. name .. ": " .. reason)
end

local function with_modules(overrides, reset, callback)
  local names = {}
  for name in pairs(overrides or {}) do
    names[name] = true
  end
  for _, name in ipairs(reset or {}) do
    names[name] = true
  end

  local saved = {}
  local present = {}
  for name in pairs(names) do
    present[name] = package.loaded[name] ~= nil
    saved[name] = package.loaded[name]
    package.loaded[name] = nil
  end
  for name, value in pairs(overrides or {}) do
    package.loaded[name] = value
  end

  local ok, err = xpcall(callback, debug.traceback)
  for name in pairs(names) do
    package.loaded[name] = present[name] and saved[name] or nil
  end
  if not ok then
    error(err, 0)
  end
end

local terminal_env_keys = {
  "GHOSTTY_BIN_DIR",
  "GHOSTTY_RESOURCES_DIR",
  "KITTY_WINDOW_ID",
  "TERM",
  "TERM_PROGRAM",
  "TMUX",
  "TMUX_PANE",
  "WEZTERM_EXECUTABLE",
  "WEZTERM_PANE",
}

local function with_terminal_env(values, callback)
  local saved = {}
  for _, key in ipairs(terminal_env_keys) do
    saved[key] = vim.env[key]
    vim.env[key] = nil
  end
  for key, value in pairs(values or {}) do
    vim.env[key] = value
  end

  local ok, err = xpcall(callback, debug.traceback)
  for _, key in ipairs(terminal_env_keys) do
    vim.env[key] = saved[key]
  end
  if not ok then
    error(err, 0)
  end
end

test("default configuration", function()
  local config = require("real-icons.config")
  config.setup()
  assert_equal(config.options.size.density, "auto", "default density")
  assert_equal(config.options.size.oversample, 1.25, "default oversample")
  assert_equal(config.options.size.cols, 2, "default columns")
  assert_equal(#config.options.rules.directories, 0, "default directory rules")
  assert_equal(config.options.integrations.fzf_lua, false, "default fzf-lua integration")
end)

test("builtin icon resolution and public API", function()
  local icons = require("real-icons")
  icons.setup({ pack = "builtin", backend = "disabled" })

  assert_equal(icons.resolve("file", "src/init.lua", { is_dir = false }).key, "lua")
  assert_equal(icons.resolve("directory", "src").key, "folder-src")
  assert_true(icons.resolve("file", "unknown.bin", { is_dir = false }).is_default)

  local text, hl, is_default, meta = icons.get("file", "README.md", { is_dir = false })
  assert_equal(type(text), "string", "icon text type")
  assert_equal(type(hl), "string", "highlight type")
  assert_equal(is_default, false, "README icon should be mapped")
  assert_equal(meta.fallback, true, "disabled backend should use fallback")
  assert_true(vim.tbl_contains(icons.categories(), "directory"), "directory category")
  assert_true(vim.tbl_contains(icons.list("extension"), "lua"), "lua extension")
end)

test("one root command exposes the complete user workflow", function()
  assert_equal(vim.fn.exists(":RealIcons"), 2, "root plugin command")
  for _, name in ipairs({
    "RealIconsBuildCache",
    "RealIconsClearCache",
    "RealIconsDemo",
    "RealIconsDiscoverPacks",
    "RealIconsHealth",
    "RealIconsInstallPack",
    "RealIconsOilEnable",
    "RealIconsPacks",
    "RealIconsSelectPack",
    "RealIconsUsePack",
  }) do
    assert_equal(vim.fn.exists(":" .. name), 0, "removed command " .. name)
  end

  local command = require("real-icons.command")
  local completion = command.complete("", "RealIcons ", #"RealIcons ")
  for _, action in ipairs({ "demo", "packs", "install", "health", "help", "clear-cache" }) do
    assert_true(vim.tbl_contains(completion, action), "command completion " .. action)
  end

  local called = {}
  with_modules({
    ["real-icons"] = {
      demo = function()
        called.demo = true
      end,
      select_pack = function()
        called.packs = true
      end,
      install_pack = function(name)
        called.install = name
        return true
      end,
      clear_cache = function(name)
        called.clear_cache = name or true
        return true
      end,
    },
  }, {}, function()
    assert_true(command.execute({ "demo" }))
    assert_true(command.execute({ "packs" }))
    assert_true(command.execute({ "install" }))
    assert_true(command.execute({ "clear-cache", "material" }))
    assert_equal(called.install, "material", "default install pack")

    called.install = nil
    vim.cmd("RealIconsInstallPack material")
    assert_equal(called.install, "material", "legacy install command bridge")
    assert_equal(vim.fn.exists(":RealIconsInstallPack"), 0, "legacy command stays hidden")

    called.demo = nil
    vim.cmd("RealIconsDemo")
    assert_true(called.demo, "legacy demo command bridge")
    assert_equal(vim.fn.exists(":RealIconsDemo"), 0, "legacy demo command stays hidden")

    called.packs = nil
    vim.cmd("RealIconsPacks")
    assert_true(called.packs, "legacy packs command bridge")
    assert_equal(vim.fn.exists(":RealIconsPacks"), 0, "legacy packs command stays hidden")
  end)
  assert_true(called.demo, "demo action")
  assert_true(called.packs, "packs action")
  assert_equal(called.install, "material", "default install pack")
  assert_equal(called.clear_cache, "material", "cache pack")
end)

test("directory rules match full paths with stable precedence", function()
  local icons = require("real-icons")
  local scala_rule = {
    glob = "**/src/*/scala/**",
    icon = "folder-test",
  }

  icons.setup({
    pack = "builtin",
    backend = "disabled",
    overrides = {
      folder_names = {
        chapter1 = "folder-src",
        scala = "folder-src",
      },
    },
    rules = {
      directories = {
        scala_rule,
        { glob = "**/src/*/scala/**", icon = "folder-src" },
      },
    },
  })

  assert_equal(
    icons.resolve("directory", "/project/src/main/scala/chapter1").key,
    "folder-src",
    "exact override should win"
  )
  assert_equal(
    icons.resolve("directory", "/project/src/main/scala/chapter2").key,
    "folder-test",
    "first matching rule should win"
  )
  assert_equal(
    icons.resolve("directory", "module/src/test/scala/com/example").key,
    "folder-test",
    "nested relative package path"
  )
  assert_equal(
    icons.resolve("directory", [[C:\project\src\it\scala\example]]).key,
    "folder-test",
    "Windows path separators"
  )
  assert_equal(
    icons.resolve("directory", "/project/src/main/scala").key,
    "folder-src",
    "source root should use its name mapping"
  )
  assert_equal(
    icons.resolve("directory", "/project/chapter2").key,
    "folder",
    "unrelated directory should not match"
  )

  icons.setup({
    pack = "builtin",
    backend = "disabled",
    rules = {
      directories = {
        { glob = "**/src/*/scala/**", icon = "not-in-this-pack" },
        { glob = "**/src/*/scala/**", icon = "folder-src" },
      },
    },
  })
  assert_equal(
    icons.resolve("directory", "/project/src/main/scala/chapter1").key,
    "folder-src",
    "missing rule icon should continue to the next rule"
  )

  icons.setup({
    pack = "builtin",
    backend = "disabled",
    rules = {
      directories = {
        { glob = "**/src/*/scala/**", icon = "not-in-this-pack" },
      },
    },
  })
  assert_equal(
    icons.resolve("directory", "/project/src/main/scala/test").key,
    "folder-test",
    "missing rule icons should continue normal resolution"
  )
  assert_true(
    icons.resolve("directory", "/project/src/main/scala/chapter1").is_default,
    "missing rule icon should use the default folder"
  )

  local custom_source = require("real-icons.assets").file("folders", "src")
  icons.setup({
    pack = "builtin",
    backend = "disabled",
    rules = {
      directories = {
        { glob = "**/generated/**", icon = custom_source },
      },
    },
  })
  local custom = icons.resolve("directory", "/project/generated/client")
  assert_equal(custom.source, custom_source, "rule should accept a direct asset path")
  assert_true(custom.key:match("^override%-") ~= nil, "direct asset rule key")

  local config = require("real-icons.config")
  local previous = config.options
  local ok = pcall(config.setup, {
    rules = { directories = { { glob = "", icon = "folder-test" } } },
  })
  assert_equal(ok, false, "invalid directory rule should fail during setup")
  assert_equal(config.options, previous, "failed setup should preserve configuration")
end)

test("adaptive SVG density", function()
  local cache = require("real-icons.cache")
  local source = vim.fn.tempname() .. ".svg"
  vim.fn.writefile({
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">',
    '<path fill="#ffffff" d="M0 0h24v24H0z"/>',
    "</svg>",
  }, source)

  local ok, err = xpcall(function()
    assert_equal(cache.density({ pixels = 64, padding = 0, density = "auto", oversample = 1.25 }, source), 320)
    assert_equal(cache.density({ pixels = 64, padding = 0, density = 384 }, source), 384)
    assert_true(cache.density_key({ density = "auto", oversample = 1.25 }):match("dauto") ~= nil)
  end, debug.traceback)
  vim.fn.delete(source)
  if not ok then
    error(err, 0)
  end
end)

test("batch cache handles ready and missing assets", function()
  local assets = require("real-icons.assets")
  local cache = require("real-icons.cache")
  local icons = {
    { pack = "test", key = "lua", source = assets.file("filetypes", "lua") },
    { pack = "test", key = "folder", source = assets.file("folders", "default") },
  }
  local count, failed = cache.ensure_many(icons, { jobs = 2 })
  assert_equal(count, 2, "ready PNG count")
  assert_equal(failed, 0, "ready PNG failures")

  count, failed = cache.ensure_many({
    { pack = "test", key = "missing", source = "/real-icons/does-not-exist.svg" },
  })
  assert_equal(count, 0, "missing asset count")
  assert_equal(failed, 1, "missing asset failures")
end)

if vim.fn.executable("magick") == 1 then
  test("parallel SVG cache build", function()
    local cache = require("real-icons.cache")
    local pack = "real-icons-test-" .. vim.fn.getpid()
    local sources = {
      vim.fn.tempname() .. ".svg",
      vim.fn.tempname() .. ".svg",
    }
    for index, source in ipairs(sources) do
      vim.fn.writefile({
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">',
        string.format('<path fill="#ffffff" d="M%d %dh16v16H%dz"/>', index, index, index),
        "</svg>",
      }, source)
    end

    local ok, err = xpcall(function()
      local icons = {}
      for index, source in ipairs(sources) do
        icons[index] = { pack = pack, key = "icon-" .. index, source = source }
      end
      local size = {
        pixels = 32,
        padding = 0,
        trim = false,
        density = "auto",
        oversample = 1.25,
      }
      local count, failed = cache.ensure_many(icons, {
        jobs = 2,
        batch_size = 8,
        size = size,
      })
      assert_equal(count, 2, "converted SVG count")
      assert_equal(failed, 0, "converted SVG failures")
      for _, icon in ipairs(icons) do
        local target = cache.target(icon, size)
        local stat = vim.uv.fs_stat(target)
        assert_true(stat and stat.size > 8, "cached PNG should exist")
      end
    end, debug.traceback)

    cache.clear(pack)
    for _, source in ipairs(sources) do
      vim.fn.delete(source)
    end
    if not ok then
      error(err, 0)
    end
  end)
else
  skip("parallel SVG cache build", "ImageMagick is not installed")
end

test("WezTerm uses safe fallback", function()
  with_terminal_env({
    TERM = "xterm-256color",
    TERM_PROGRAM = "WezTerm",
    WEZTERM_PANE = "1",
  }, function()
    local config = require("real-icons.config")
    local backend = require("real-icons.backend.kitty")
    config.setup({ backend = "auto" })
    local detected = backend.detect({ refresh = true })
    assert_equal(detected.terminal, "wezterm")
    assert_equal(detected.graphics, true, "base graphics support")
    assert_equal(detected.placeholders, false, "placeholder support")
    assert_equal(detected.supported, false, "renderer support")
    assert_true(detected.reason:match("Unicode placeholders") ~= nil, "fallback reason")
  end)
end)

test("WezTerm can be explicitly forced for future builds", function()
  with_terminal_env({
    TERM = "xterm-256color",
    TERM_PROGRAM = "WezTerm",
    WEZTERM_PANE = "1",
  }, function()
    local config = require("real-icons.config")
    local backend = require("real-icons.backend.kitty")
    config.setup({ backend = "kitty" })
    local detected = backend.detect({ refresh = true })
    assert_equal(detected.terminal, "wezterm")
    assert_equal(detected.forced, true)
    assert_equal(detected.placeholders, true)
    assert_equal(detected.supported, true)
  end)
end)

test("Ghostty and Kitty support placeholders", function()
  local config = require("real-icons.config")
  local backend = require("real-icons.backend.kitty")
  for _, terminal in ipairs({
    { env = { TERM_PROGRAM = "ghostty" }, name = "ghostty" },
    { env = { TERM = "xterm-kitty", KITTY_WINDOW_ID = "1" }, name = "kitty" },
  }) do
    with_terminal_env(terminal.env, function()
      config.setup({ backend = "auto" })
      local detected = backend.detect({ refresh = true })
      assert_equal(detected.terminal, terminal.name)
      assert_equal(detected.placeholders, true)
      assert_equal(detected.supported, true)
    end)
  end
end)

test("uploaded terminal images are released", function()
  if not vim.v.stderr or vim.v.stderr <= 0 then
    skip("uploaded terminal images are released", "stderr channel is unavailable")
    return
  end

  local assets = require("real-icons.assets")
  local backend = require("real-icons.backend.kitty")
  local original_send = vim.api.nvim_chan_send
  local writes = {}
  vim.api.nvim_chan_send = function(_, data)
    writes[#writes + 1] = data
  end

  local ok, err = xpcall(function()
    backend.clear_uploaded()
    local image_id, upload_err = backend.upload({
      asset = assets.file("filetypes", "lua"),
    }, {
      cols = 2,
      rows = 1,
    })
    assert_true(image_id ~= nil, upload_err)
    backend.clear_uploaded()
    assert_true(table.concat(writes):match("a=d,d=I,q=2,i=" .. image_id) ~= nil, "delete command")
  end, debug.traceback)

  vim.api.nvim_chan_send = original_send
  backend.clear_uploaded()
  if not ok then
    error(err, 0)
  end
end)

test("pack paths cannot escape their root", function()
  local util = require("real-icons.packs.util")
  local ok = pcall(util.join, "/tmp/real-icons-pack-root", "../escape.svg")
  assert_equal(ok, false)
end)

test("placeholder dimensions are validated", function()
  local renderer = require("real-icons.render.placeholder")
  assert_equal(#renderer.placeholder(2, 1), 1, "placeholder row count")
  assert_equal(pcall(renderer.placeholder, 4, 1), false, "column limit")
  assert_equal(pcall(renderer.placeholder, 1, 2), false, "row limit")
end)

test("bufferline integration preserves options and injects its public icon callback", function()
  local applied
  local bufferline = {
    setup = function(opts)
      applied = opts
    end,
  }

  with_modules({
    bufferline = bufferline,
  }, {
    "real-icons.integrations.bufferline",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.bufferline")
    local ok, err = integration.setup()
    assert_true(ok, err)

    bufferline.setup({ options = { numbers = "ordinal" } })
    assert_equal(applied.options.numbers, "ordinal", "user bufferline option")
    assert_equal(type(applied.options.get_element_icon), "function", "icon callback")
    local icon, hl = applied.options.get_element_icon({
      directory = false,
      filetype = "lua",
      path = "/project/init.lua",
    })
    assert_equal(type(icon), "string", "bufferline icon")
    assert_equal(type(hl), "string", "bufferline icon highlight")
  end)
end)

test("lualine integration inserts an icon without replacing configured components", function()
  local applied
  local lualine = {
    setup = function(opts)
      applied = opts
    end,
  }

  with_modules({
    lualine = lualine,
  }, {
    "real-icons.integrations.lualine",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.lualine")
    local ok, err = integration.setup()
    assert_true(ok, err)

    lualine.setup({
      sections = {
        lualine_c = { "branch", "filename" },
      },
    })
    local section = applied.sections.lualine_c
    assert_equal(section[1], "branch", "existing lualine component")
    assert_true(section[2].real_icons_lualine, "real icon component")
    assert_equal(section[3], "filename", "target lualine component")
  end)
end)

test("mini.files integration uses the official content prefix hook", function()
  local applied
  local files = {
    config = {
      content = {},
      windows = { preview = false },
    },
    setup = function(opts)
      applied = opts
    end,
  }

  with_modules({
    ["mini.files"] = files,
  }, {
    "real-icons.integrations.mini_files",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.mini_files")
    local ok, err = integration.setup()
    assert_true(ok, err)

    files.setup({ windows = { preview = true } })
    assert_equal(applied.windows.preview, true, "mini.files user option")
    assert_equal(type(applied.content.prefix), "function", "mini.files prefix")
    local prefix, hl = applied.content.prefix({
      fs_type = "file",
      path = "/project/init.lua",
    })
    assert_true(prefix:sub(-1) == " ", "mini.files icon spacing")
    assert_equal(type(hl), "string", "mini.files icon highlight")
  end)
end)

test("neo-tree integration uses the official icon provider", function()
  local defaults = {
    default_component_configs = {
      icon = {
        folder_closed = ">",
      },
    },
  }
  local neo_tree = {
    config = vim.deepcopy(defaults),
  }

  with_modules({
    ["neo-tree"] = neo_tree,
    ["neo-tree.defaults"] = defaults,
  }, {
    "real-icons.integrations.neo_tree",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.neo_tree")
    local ok, err = integration.setup()
    assert_true(ok, err)
    assert_equal(
      defaults.default_component_configs.icon.provider,
      integration.provider,
      "neo-tree default provider"
    )
    assert_equal(defaults.default_component_configs.icon.folder_closed, ">", "neo-tree option")

    local icon = integration.provider({}, {
      path = "/project/src",
      type = "directory",
    })
    assert_equal(type(icon.text), "string", "neo-tree icon")
    assert_equal(type(icon.highlight), "string", "neo-tree highlight")
  end)
end)

test("Oil integration replaces the native icon column without buffer scans", function()
  local registered_name
  local registered_column
  local columns = {
    register = function(name, column)
      registered_name = name
      registered_column = column
    end,
  }
  local constants = {
    FIELD_ID = 1,
    FIELD_NAME = 2,
    FIELD_TYPE = 3,
    FIELD_META = 4,
  }
  local oil = {
    get_current_dir = function()
      return "/project"
    end,
  }
  local util = {
    export_entry = function(entry)
      return {
        id = entry[1],
        name = entry[2],
        type = entry[3],
        meta = entry[4],
      }
    end,
  }

  with_modules({
    oil = oil,
    ["oil.columns"] = columns,
    ["oil.constants"] = constants,
    ["oil.util"] = util,
  }, {
    "real-icons.integrations.oil",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.oil")
    local ok, err = integration.setup()
    assert_true(ok, err)
    assert_true(integration.is_patched(), "Oil column should be installed")
    assert_equal(registered_name, "icon", "Oil column name")
    assert_equal(type(registered_column.render), "function", "Oil column renderer")
    assert_equal(type(registered_column.parse), "function", "Oil column parser")

    local chunk = registered_column.render({ 1, "init.lua", "file" }, {}, 0)
    assert_equal(type(chunk[1]), "string", "Oil icon text")
    assert_equal(type(chunk[2]), "string", "Oil icon highlight")
    assert_true(chunk[1]:sub(-1) == " ", "Oil icon padding")

    local autocmds = vim.api.nvim_get_autocmds({ group = "RealIconsOil" })
    for _, autocmd in ipairs(autocmds) do
      assert_true(
        autocmd.event ~= "TextChanged" and autocmd.event ~= "TextChangedI",
        "Oil integration must not scan on text changes"
      )
    end
  end)
end)

test("nvim-tree integration registers the public Decorator API", function()
  local Decorator = {}
  Decorator.__index = Decorator
  function Decorator:extend()
    local child = {}
    child.__index = child
    return setmetatable(child, { __index = self })
  end

  local applied
  local custom_decorator = { name = "Custom" }
  local nvim_tree = {
    setup = function(opts)
      applied = opts
    end,
  }
  local tree_config = {
    d = {
      renderer = {
        decorators = { "Git", "Open", "Cut" },
      },
    },
  }
  local previous_setup = vim.g.NvimTreeSetup
  vim.g.NvimTreeSetup = nil

  local ok, err = xpcall(function()
    with_modules({
      ["nvim-tree"] = nvim_tree,
      ["nvim-tree.api"] = { Decorator = Decorator },
      ["nvim-tree.config"] = tree_config,
    }, {
      "real-icons.integrations.nvim_tree",
    }, function()
      require("real-icons").setup({ pack = "builtin", backend = "disabled" })
      local integration = require("real-icons.integrations.nvim_tree")
      local setup_ok, setup_err = integration.setup()
      assert_true(setup_ok, setup_err)
      assert_equal(integration.mode(), "decorator", "nvim-tree integration mode")

      nvim_tree.setup({ renderer = { decorators = { "Git", custom_decorator } } })
      assert_equal(applied.renderer.decorators[1], "Git", "first user decorator")
      assert_equal(applied.renderer.decorators[2], custom_decorator, "custom user decorator")
      assert_equal(
        applied.renderer.decorators[3],
        integration.decorator(),
        "real-icons decorator"
      )

      local repeated = integration.opts(vim.deepcopy(applied))
      assert_equal(#repeated.renderer.decorators, 3, "real-icons decorator is not duplicated")
    end)
  end, debug.traceback)
  vim.g.NvimTreeSetup = previous_setup
  if not ok then
    error(err, 0)
  end
end)

test("nvim-tree integration keeps a legacy fallback for older releases", function()
  local Builder = {
    icon_name_decorated = function()
      return { str = "old", hl = { "Old" } }, { str = "init.lua", hl = {} }
    end,
  }
  local nvim_tree = {
    setup = function() end,
  }

  with_modules({
    ["nvim-tree"] = nvim_tree,
    ["nvim-tree.api"] = {},
    ["nvim-tree.renderer.builder"] = Builder,
  }, {
    "real-icons.integrations.nvim_tree",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.nvim_tree")
    local ok, err = integration.setup()
    assert_true(ok, err)
    assert_equal(integration.mode(), "legacy", "nvim-tree fallback mode")

    local icon = Builder.icon_name_decorated({}, {
      absolute_path = "/project/init.lua",
      type = "file",
    })
    assert_true(icon.str ~= "old", "legacy icon should be replaced")
  end)
end)

test("Snacks picker integration preserves formatter output and caches item icons", function()
  local original_calls = 0
  local builtin_icons_disabled = false
  local format = {
    filename = function(_, picker)
      original_calls = original_calls + 1
      builtin_icons_disabled = picker.opts.icons.files.enabled == false
      return { { "init.lua", "SnacksPickerFile" } }
    end,
  }

  with_modules({
    ["snacks.picker.format"] = format,
  }, {
    "real-icons.integrations.snacks_picker",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.snacks_picker")
    local ok, err = integration.setup()
    assert_true(ok, err)

    local item = { file = "/project/init.lua" }
    local picker = { opts = { icons = { files = { enabled = true } } } }
    local first = format.filename(item, picker)
    local segment = item._real_icons_segment
    local second = format.filename(item, picker)
    assert_true(builtin_icons_disabled, "Snacks builtin icon should be disabled during formatting")
    assert_equal(picker.opts.icons.files.enabled, true, "Snacks icon setting should be restored")
    assert_equal(original_calls, 2, "original Snacks formatter calls")
    assert_equal(item._real_icons_segment, segment, "Snacks item icon cache")
    assert_true(#first >= 3 and #second >= 3, "Snacks formatter chunks")
  end)
end)

test("Telescope integration wraps the upstream file entry maker", function()
  local received_opts
  local make_entry = {
    gen_from_file = function(opts)
      received_opts = opts
      return function(path)
        return {
          path = path,
          display = function(entry)
            return entry.path, { { { 0, #entry.path }, "Base" } }
          end,
        }
      end
    end,
  }
  local highlights = {
    new = function()
      return {
        hi_selection = function() end,
      }
    end,
  }

  with_modules({
    ["telescope.make_entry"] = make_entry,
    ["telescope.pickers.highlights"] = highlights,
  }, {
    "real-icons.integrations.telescope",
    "real-icons.integrations.telescope_file_browser",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.telescope")
    local ok, err = integration.setup()
    assert_true(ok, err)

    local maker = make_entry.gen_from_file({ path_display = { "truncate" } })
    assert_equal(received_opts.disable_devicons, true, "Telescope builtin icons")
    assert_equal(received_opts.path_display[1], "truncate", "Telescope entry option")
    local entry = maker("/project/init.lua")
    local display, styles = entry.display(entry)
    assert_true(display:sub(-#entry.path) == entry.path, "Telescope base display")
    assert_true(#styles >= 2, "Telescope icon and base styles")
  end)
end)

test("telescope-file-browser decorates the upstream entry maker", function()
  local upstream_opts
  local seen_file_width
  local upstream = function(opts)
    upstream_opts = opts
    return function(path)
      return {
        marker = "upstream",
        path = path,
        is_dir = false,
        display = function()
          seen_file_width = opts.file_width
          return "init.lua", { { { 0, 4 }, "Base" } }
        end,
      }
    end
  end
  local current_win = vim.api.nvim_get_current_win()
  local state = {
    get_existing_prompt_bufnrs = function()
      return { 77 }
    end,
    get_status = function()
      return {
        picker = {
          finder = { _browse_files = true },
          selection_caret = "> ",
        },
        results_win = current_win,
      }
    end,
  }
  local highlights = {
    new = function()
      return {
        hi_selection = function() end,
      }
    end,
  }

  with_modules({
    ["telescope._extensions.file_browser.make_entry"] = upstream,
    ["telescope.pickers.highlights"] = highlights,
    ["telescope.state"] = state,
  }, {
    "real-icons.integrations.telescope_file_browser",
  }, function()
    require("real-icons").setup({ pack = "builtin", backend = "disabled" })
    local integration = require("real-icons.integrations.telescope_file_browser")
    local maker = integration.entry_maker({
      cwd = "/project",
      display_stat = false,
      git_status = false,
    })
    assert_equal(upstream_opts.disable_devicons, true, "file-browser builtin icons")

    local entry = maker("/project/init.lua")
    assert_equal(entry.marker, "upstream", "upstream entry fields")
    local display, styles = entry.display(entry)
    assert_true(display:sub(-8) == "init.lua", "upstream file-browser display")
    assert_true(type(seen_file_width) == "number" and seen_file_width >= 15, "dynamic file width")
    assert_equal(upstream_opts.file_width, nil, "temporary file width restoration")
    assert_true(#styles >= 2, "file-browser icon and upstream styles")
  end)
end)

test("fzf-lua integration preserves setup and prepares only an icon slot", function()
  local module_names = {
    "fzf-lua",
    "fzf-lua.devicons",
    "fzf-lua.path",
    "fzf-lua.utils",
    "fzf-lua.win",
    "real-icons.integrations.fzf_lua",
  }
  local saved = {}
  for _, name in ipairs(module_names) do
    saved[name] = package.loaded[name]
  end

  local fzf_setup_calls = 0
  local installed_state
  local fake_fzf = {
    setup = function()
      fzf_setup_calls = fzf_setup_calls + 1
    end,
  }
  local fake_devicons = {
    load = function()
      return false
    end,
    set_state = function(_, state)
      installed_state = state
    end,
  }
  local fake_path = {
    entry_to_file = function(entry)
      return { path = entry }
    end,
  }
  local fake_utils = { nbsp = vim.fn.nr2char(0x2002) }
  local fake_win = {
    new = function(opts)
      return { opts = opts }
    end,
  }

  package.loaded["fzf-lua"] = fake_fzf
  package.loaded["fzf-lua.devicons"] = fake_devicons
  package.loaded["fzf-lua.path"] = fake_path
  package.loaded["fzf-lua.utils"] = fake_utils
  package.loaded["fzf-lua.win"] = fake_win
  package.loaded["real-icons.integrations.fzf_lua"] = nil

  local scratch
  local ok, err = xpcall(function()
    local integration = require("real-icons.integrations.fzf_lua")
    local setup_ok, setup_err = integration.setup()
    assert_true(setup_ok, setup_err)
    assert_equal(fzf_setup_calls, 0, "integration must not rerun fzf-lua setup")
    assert_true(fake_devicons.load(), "neutral icon provider should load")
    assert_true(installed_state.real_icons.visible_only, "visible-only marker")
    assert_equal(installed_state.real_icons.slot_cols, 2, "reserved slot width")
    assert_equal(vim.tbl_count(installed_state.icons.by_filename), 0, "filename icons prepared")
    assert_equal(vim.tbl_count(installed_state.icons.by_ext), 0, "extension icons prepared")

    local slot = {
      cols = installed_state.real_icons.slot_cols,
      file = installed_state.default_icon.icon,
      directory = installed_state.dir_icon.icon,
      nbsp = fake_utils.nbsp,
    }
    local candidate, col = integration._line_entry(
      "▌ " .. slot.file .. slot.nbsp .. "src/init.lua      │",
      slot
    )
    assert_equal(candidate, "src/init.lua", "visible fzf entry path")
    assert_true(type(col) == "number" and col > 0, "icon overlay column")

    local user_on_create_calls = 0
    local opts = {
      _type = "file",
      winopts = {
        width = 0.61,
        on_create = function()
          user_on_create_calls = user_on_create_calls + 1
        end,
      },
    }
    local picker = fake_win.new(opts)
    assert_equal(picker.opts.winopts.width, 0.61, "user layout width")

    scratch = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    opts.winopts.on_create({ winid = winid, bufnr = scratch })
    assert_equal(user_on_create_calls, 1, "user on_create callback")
    assert_true(integration.is_attached(winid, scratch), "fzf buffer attachment")
    integration.detach(scratch)
  end, debug.traceback)

  if scratch and vim.api.nvim_buf_is_valid(scratch) then
    vim.api.nvim_buf_delete(scratch, { force = true })
  end
  for _, name in ipairs(module_names) do
    package.loaded[name] = saved[name]
  end
  if not ok then
    error(err, 0)
  end
end)

print(string.format("tests: %d passed, %d skipped, %d failed", passed, skipped, #failures))
if #failures > 0 then
  for _, failure in ipairs(failures) do
    print("\n" .. failure.name .. "\n" .. failure.error)
  end
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
