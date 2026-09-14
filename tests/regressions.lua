return function(test, eq, truth, with_modules)
  local icons = require("real-icons")
  local assets = require("real-icons.assets")
  local renderer = require("real-icons.render.placeholder")
  local cache = require("real-icons.cache")
  local fixture_root = vim.fn.getcwd() .. "/tests/fixtures"
  local function fixture_options()
    return {
      pack = "fixture",
      backend = "disabled",
      packs = { fixture = { type = "vscode", path = fixture_root, manifest = "theme.json" } },
    }
  end

  test("enabled integration errors remain visible and can be retried", function()
    local available = false
    local notifications = {}
    local notify = vim.notify
    vim.notify = function(message)
      notifications[#notifications + 1] = message
    end
    with_modules({
      ["real-icons.integrations.telescope"] = {
        setup = function()
          return available, available and nil or "dependency is not available"
        end,
      },
    }, {}, function()
      icons.setup({ pack = "builtin", backend = "disabled", integrations = { telescope = true } })
      eq(icons.integration_status().telescope.status, "error")
      truth(icons.integration_status().telescope.error:find("dependency", 1, true))
      truth(#notifications > 0, "failed setup must notify")
      available = true
      eq(icons.retry_integrations().telescope.status, "ready")
    end)
    vim.notify = notify
    local config = require("real-icons.config")
    local previous = config.options
    eq(pcall(config.setup, { integrations = { typo = true } }), false)
    eq(config.options, previous, "invalid settings preserve the previous configuration")
  end)

  test("cached picker items follow pack, colorscheme, and clear-cache changes", function()
    local send = vim.api.nvim_chan_send
    vim.api.nvim_chan_send = function() end
    icons.setup({
      pack = "first",
      backend = "kitty",
      packs = {
        first = { type = "simple", path = assets.dir(), file = "filetypes/lua.png" },
        second = { type = "simple", path = assets.dir(), file = "filetypes/typescript.png" },
      },
    })
    local adapter = require("real-icons.integrations.snacks_picker")
    local item = { file = "example.lua", dir = false }
    adapter.icon(item)
    eq(item._real_icons_segment.icon.pack, "first")
    truth(icons.use_pack("second", { notify = false }))
    adapter.icon(item)
    eq(item._real_icons_segment.icon.pack, "second")
    local hl = item._real_icons_segment.hl
    vim.api.nvim_set_hl(0, hl, {})
    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
    adapter.icon(item)
    truth(vim.api.nvim_get_hl(0, { name = hl }).fg, "colorscheme must recreate image highlighting")
    local old = item._real_icons_segment
    icons.clear_cache()
    adapter.icon(item)
    truth(item._real_icons_segment ~= old, "clear-cache must invalidate item segments")
    require("real-icons.backend.kitty").clear_uploaded()
    vim.api.nvim_chan_send = send
  end)

  test("one PNG can be uploaded at different cell widths", function()
    local backend = require("real-icons.backend.kitty")
    local send = vim.api.nvim_chan_send
    local writes = {}
    vim.api.nvim_chan_send = function(_, data)
      writes[#writes + 1] = data
    end
    backend.clear_uploaded()
    local icon = { asset = assets.file("filetypes", "lua") }
    local one = backend.upload(icon, { cols = 1, rows = 1 })
    local three = backend.upload(icon, { cols = 3, rows = 1 })
    truth(one ~= three, "different placements need different ids")
    eq(backend.upload(icon, { cols = 1, rows = 1 }), one, "same placement is reused")
    backend.clear_uploaded()
    vim.api.nvim_chan_send = send
    truth(table.concat(writes):find("c=3", 1, true))
  end)

  if vim.fn.executable("magick") == 1 then
    test("cold SVG rendering returns immediately and refreshes the same extmark", function()
      local send = vim.api.nvim_chan_send
      vim.api.nvim_chan_send = function() end
      local options = fixture_options()
      options.backend = "kitty"
      icons.setup(options)
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "example.ts" })
      local segment = icons.segment("file", "example.ts", { is_dir = false })
      truth(segment.pending, "a cold conversion must be queued")
      eq(segment.width, options.size and options.size.cols or 2)
      local id = icons.render(bufnr, 0, 0, "file", "example.ts", { is_dir = false })
      eq(cache.status().pending, 1, "the same SVG is only queued once")
      truth(
        vim.wait(10000, function()
          return cache.status().pending == 0
        end, 10),
        "conversion timeout"
      )
      renderer.refresh()
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, renderer.ns, 0, -1, { details = true })
      eq(#marks, 1)
      eq(marks[1][1], id, "refresh preserves the extmark id")
      truth(marks[1][4].virt_text[1][2]:find("RealIconsImage", 1, true))
      vim.api.nvim_buf_delete(bufnr, { force = true })
      require("real-icons.backend.kitty").clear_uploaded()
      vim.api.nvim_chan_send = send
    end)

    test("cache identities include the source and damaged files are rebuilt", function()
      icons.setup({ pack = "builtin", backend = "disabled" })
      local a = { pack = "source-test", key = "same", source = fixture_root .. "/red.svg" }
      local b = { pack = "source-test", key = "same", source = fixture_root .. "/blue.svg" }
      truth(cache.target(a) ~= cache.target(b))
      local target = assert(cache.ensure(a))
      vim.fn.writefile({ "corrupt" }, target)
      local done, error_message
      eq(
        cache.ensure_async(a, {}, function(path, err)
          done, error_message = path, err
        end),
        nil
      )
      truth(vim.wait(10000, function()
        return done ~= nil or error_message ~= nil
      end, 10))
      truth(done, error_message)
      truth(vim.uv.fs_stat(target).size > 8)
    end)
  end
end
