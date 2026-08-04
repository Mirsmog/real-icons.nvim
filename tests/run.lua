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
  assert_equal(vim.fn.exists(":RealIconsBuildCache"), 2, "plugin command")
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

print(string.format("tests: %d passed, %d skipped, %d failed", passed, skipped, #failures))
if #failures > 0 then
  for _, failure in ipairs(failures) do
    print("\n" .. failure.name .. "\n" .. failure.error)
  end
  vim.cmd("cquit 1")
else
  vim.cmd("qa!")
end
