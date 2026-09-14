return function(test, eq, truth)
  local icons = require("real-icons")
  local cache = require("real-icons.cache")
  local packs = require("real-icons.packs")
  local uv = vim.uv or vim.loop
  local fixture_root = vim.fn.getcwd() .. "/tests/fixtures"

  local function with_system(replacement, callback)
    local original = vim.system
    vim.system = replacement
    local ok, err = xpcall(callback, debug.traceback)
    vim.system = original
    if not ok then
      error(err, 0)
    end
  end

  test("integration diagnostics distinguish deferred and manual setup", function()
    local modules =
      { "real-icons.integrations.oil", "real-icons.integrations.telescope_file_browser" }
    local saved = { package.loaded[modules[1]], package.loaded[modules[2]] }
    local patched = false
    package.loaded[modules[1]] = {
      setup = function()
        return true
      end,
      is_patched = function()
        return patched
      end,
    }
    package.loaded[modules[2]] = {
      setup = function()
        return true
      end,
    }
    local ok, err = xpcall(function()
      icons.setup({
        pack = "builtin",
        backend = "disabled",
        integrations = { oil = true, telescope_file_browser = true },
      })
      eq(icons.integration_status().oil.status, "waiting")
      eq(icons.integration_status().telescope_file_browser.status, "manual")
      patched = true
      eq(icons.integration_status().oil.status, "ready")
    end, debug.traceback)
    for index, name in ipairs(modules) do
      package.loaded[name] = saved[index]
    end
    icons.setup({ pack = "builtin", backend = "disabled" })
    if not ok then
      error(err, 0)
    end
  end)

  test("async installation preserves working packs on failure and rejects duplicates", function()
    icons.setup({ pack = "builtin", backend = "disabled" })
    local root = require("real-icons.path").data_dir() .. "/packs/material"
    truth(
      root:find("real-icons-test.", 1, true),
      "installer tests require the isolated tests/run.sh runner"
    )
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "keep me" }, root .. "/existing.txt")
    local mode, commands = "download-error", 0
    with_system(function(command, _, callback)
      commands = commands + 1
      truth(command[1] == "curl" or command[1] == "tar", "unexpected process in installer test")
      if mode == "spawn-error" then
        error("unable to spawn curl")
      end
      local code = 0
      if command[1] == "curl" then
        if mode == "download-error" then
          code = 22
        end
        for index, arg in ipairs(command) do
          if arg == "-o" then
            vim.fn.writefile({ "local archive fixture" }, command[index + 1])
          end
        end
      else
        if mode == "extract-error" then
          code = 2
        end
        local staging = command[#command]
        vim.fn.mkdir(staging .. "/dist", "p")
        local manifest = mode == "invalid-manifest" and "broken json"
          or vim.json.encode({ iconDefinitions = {} })
        vim.fn.writefile({ manifest }, staging .. "/dist/material-icons.json")
      end
      local result = { code = code, stderr = code ~= 0 and "simulated failure" or "" }
      if callback then
        vim.schedule(function()
          callback(result)
        end)
      end
      return {
        wait = function()
          return result
        end,
      }
    end, function()
      for _, scenario in ipairs({
        "download-error",
        "extract-error",
        "invalid-manifest",
        "spawn-error",
      }) do
        mode = scenario
        local completed
        truth(packs.install_async("material", {
          on_complete = function(ok, err)
            completed = { ok, err }
          end,
        }))
        eq(packs.install_async("material"), false, "a second install must not race the first")
        truth(
          vim.wait(3000, function()
            return completed ~= nil
          end, 10),
          scenario .. " timeout"
        )
        eq(completed[1], false, scenario)
        truth(type(completed[2]) == "string", "failures need an actionable message")
        eq(vim.fn.readfile(root .. "/existing.txt")[1], "keep me")
        eq(
          #vim.fn.glob(vim.fs.dirname(root) .. "/.material-*", false, true),
          0,
          "staging files must be cleaned up"
        )
      end
      mode = "spawn-error"
      eq(
        packs.install("material", { notify = false }),
        false,
        "headless install must return spawn errors"
      )
      mode = "success"
      local completed
      truth(packs.install_async("material", {
        on_complete = function(ok)
          completed = ok
        end,
      }))
      truth(vim.wait(3000, function()
        return completed ~= nil
      end, 10))
      eq(completed, true)
      truth(packs.installed("material"))
      eq(
        vim.fn.filereadable(root .. "/existing.txt"),
        0,
        "successful install replaces the old pack"
      )
      eq(#vim.fn.glob(vim.fs.dirname(root) .. "/.material-*", false, true), 0)
    end)
    truth(commands > 0)
  end)

  if vim.fn.executable("magick") ~= 1 then
    return
  end

  test("async queue bounds concurrency and cancellation cannot replace newer results", function()
    icons.setup({ pack = "builtin", backend = "disabled" })
    truth(vim.wait(3000, function()
      return cache.status().running == 0
    end, 10))
    local jobs, killed, obsolete_callbacks = {}, 0, 0
    with_system(function(command, _, callback)
      jobs[#jobs + 1] = { command = command, callback = callback }
      return {
        kill = function()
          killed = killed + 1
        end,
      }
    end, function()
      local first
      for index = 1, 5 do
        local icon =
          { pack = "async-cancel", key = tostring(index), source = fixture_root .. "/red.svg" }
        first = first or icon
        cache.ensure_async(icon, {}, function()
          obsolete_callbacks = obsolete_callbacks + 1
        end)
      end
      eq(#jobs, 2, "at most two ImageMagick processes may run")
      eq(cache.status().pending, 5)
      cache.cancel_pending()
      eq(killed, 2)
      eq(cache.status().pending, 0)
      local ready
      cache.ensure_async(first, {}, function(path)
        ready = path
      end)
      eq(#jobs, 2, "replacement waits for cancelled processes to stop")
      for index = 1, 2 do
        jobs[index].callback({ code = 143, stderr = "cancelled" })
      end
      truth(vim.wait(3000, function()
        return #jobs == 3
      end, 10))
      eq(cache.status().pending, 1, "old completions cannot remove a new job with the same key")
      local target = jobs[3].command[#jobs[3].command]
      truth(uv.fs_copyfile(require("real-icons.assets").file("filetypes", "lua"), target))
      jobs[3].callback({ code = 0 })
      truth(vim.wait(3000, function()
        return ready ~= nil
      end, 10))
      truth(uv.fs_stat(ready))
      eq(uv.fs_stat(target), nil, "the temporary output is renamed, not left behind")
      eq(obsolete_callbacks, 0)
      eq(cache.status().running, 0)
      eq(cache.status().pending, 0)
      eq(cache.status().failed, 0)
    end)
  end)

  test("conversion errors are reported once and clear-cache allows a retry", function()
    icons.setup({ pack = "builtin", backend = "disabled" })
    local calls, message = 0, nil
    local icon = { pack = "async-failure", key = "broken", source = fixture_root .. "/red.svg" }
    with_system(function(_, _, callback)
      calls = calls + 1
      vim.schedule(function()
        callback({ code = 1, stderr = "invalid SVG fixture" })
      end)
      return { kill = function() end }
    end, function()
      cache.ensure_async(icon, {}, function(_, err)
        message = err
      end)
      truth(vim.wait(3000, function()
        return message ~= nil
      end, 10))
      eq(message, "invalid SVG fixture")
      eq(cache.status().failed, 1)
      local _, err = cache.ensure_async(icon)
      eq(err, message)
      eq(calls, 1, "a failing icon must not spawn on every redraw")
      truth(cache.clear("async-failure"))
      message = nil
      cache.ensure_async(icon, {}, function(_, error_message)
        message = error_message
      end)
      truth(vim.wait(3000, function()
        return message ~= nil
      end, 10))
      eq(calls, 2)
    end)
    cache.cancel_pending()
  end)
end
