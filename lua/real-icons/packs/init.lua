local config = require("real-icons.config")
local path_util = require("real-icons.path")

local M = {}

local loaded = {}
local load_errors = {}
local installing = {}

local material = {
  name = "material",
  version = "5.37.0",
  url = "https://registry.npmjs.org/material-icon-theme/-/material-icon-theme-5.37.0.tgz",
}

local function pack_root(name)
  return path_util.join(path_util.data_dir(), "packs", name)
end

local function material_root()
  return pack_root("material")
end

local builtin_specs = {
  builtin = {
    type = "builtin",
  },
  material = {
    type = "vscode",
    path = material_root(),
    manifest = "dist/material-icons.json",
  },
}

local function spec_for(name)
  return config.options.packs[name] or builtin_specs[name]
end

local function load_spec(name, spec)
  local loader_name = spec.type or "simple"
  local ok, loader = pcall(require, "real-icons.packs.loaders." .. loader_name)
  if not ok then
    return nil, "unknown pack loader: " .. loader_name
  end
  local loaded_ok, pack, err = pcall(loader.load, name, spec)
  if not loaded_ok then
    return nil, pack
  end
  return pack, err
end

local function normalize_pack(name, pack)
  pack = pack or {}
  pack.name = pack.name or name or "builtin"
  pack.definitions = pack.definitions or {}
  pack.file_extensions = pack.file_extensions or {}
  pack.file_names = pack.file_names or {}
  pack.folder_names = pack.folder_names or {}
  pack.language_ids = pack.language_ids or {}
  return pack
end

function M.installed(name)
  if name == "builtin" then
    return true
  end
  if name == "material" and not config.options.packs.material then
    return path_util.exists(path_util.join(material_root(), "dist", "material-icons.json"))
  end

  local spec = spec_for(name)
  if not spec or not spec.path then
    return false
  end
  return path_util.exists(vim.fn.fnamemodify(spec.path, ":p"))
end

function M.get(name)
  name = name or config.options.pack
  local variant = name .. "|" .. vim.o.background
  if loaded[variant] then
    return loaded[variant]
  end

  local spec = spec_for(name)
  local pack
  local err
  load_errors[name] = nil
  if spec and M.installed(name) then
    pack, err = load_spec(name, spec)
    if not pack then
      load_errors[name] = err or "failed to load pack"
    end
  elseif spec then
    load_errors[name] = "pack is not installed"
  else
    load_errors[name] = "unknown icon pack"
  end

  if not pack then
    pack = require("real-icons.packs.loaders.builtin").load()
  end

  pack = normalize_pack(name, pack)
  loaded[variant] = pack
  return pack
end

function M.source(name)
  if name == "material" then
    return material
  end
  return spec_for(name)
end

function M.register(name, spec)
  name = name and vim.trim(tostring(name)) or ""
  if name == "" then
    return false, "pack name is required"
  end
  if type(spec) ~= "table" then
    return false, "pack spec must be a table"
  end

  config.options.packs[name] = vim.deepcopy(spec)
  loaded[name .. "|dark"] = nil
  loaded[name .. "|light"] = nil
  load_errors[name] = nil
  return true
end

function M.names()
  local names = {
    "builtin",
    "material",
  }

  local seen = {
    builtin = true,
    material = true,
  }

  for name in pairs(config.options.packs or {}) do
    if not seen[name] then
      names[#names + 1] = name
      seen[name] = true
    end
  end

  table.sort(names)
  return names
end

function M.last_error(name)
  return load_errors[name or config.options.pack]
end

function M.spec(name)
  return vim.deepcopy(spec_for(name))
end

function M.installing(name)
  return installing[name or "material"]
end

local function run(command, opts)
  if opts._async then
    return coroutine.yield(command)
  end
  local started, process = pcall(vim.system, command, { text = true, timeout = 120000 })
  if not started then
    return false, tostring(process)
  end
  local result = process:wait()
  if result.code ~= 0 then
    return false, path_util.shell_error(command, result.stderr or result.stdout)
  end
  return true
end

local function remove_path(path)
  if path and path_util.exists(path) then
    vim.fn.delete(path, "rf")
  end
end

local function rename_path(from, to)
  if vim.fn.rename(from, to) == 0 then
    return true
  end

  local err = vim.v.errmsg ~= "" and (": " .. vim.v.errmsg) or ""
  return false, "unable to rename " .. from .. " to " .. to .. err
end

function M.install(name, opts)
  opts = opts or {}
  name = name or config.options.pack
  if name ~= "material" then
    return false, "unknown installable pack: " .. tostring(name)
  end

  local source = material
  local root = material_root()
  local parent = vim.fs.dirname(root)
  if not path_util.ensure_dir(parent) then
    return false, "unable to create " .. parent
  end

  local token = vim.fn.fnamemodify(vim.fn.tempname(), ":t")
  local archive = path_util.join(parent, ".material-" .. token .. ".tgz")
  local staging = path_util.join(parent, ".material-" .. token)
  local backup = path_util.join(parent, ".material-backup-" .. token)

  local ok, err = run({
    "curl",
    "-L",
    "--fail",
    "--connect-timeout",
    "10",
    "--max-time",
    "120",
    "-o",
    archive,
    source.url,
  }, opts)
  if not ok then
    remove_path(archive)
    return false, err
  end

  remove_path(staging)
  if not path_util.ensure_dir(staging) then
    remove_path(archive)
    return false, "unable to create " .. staging
  end

  ok, err = run({ "tar", "-xzf", archive, "--strip-components=1", "-C", staging }, opts)
  if not ok then
    remove_path(archive)
    remove_path(staging)
    return false, err
  end

  local manifest = path_util.join(staging, "dist", "material-icons.json")
  if not path_util.exists(manifest) then
    remove_path(archive)
    remove_path(staging)
    return false, "downloaded Material Icon Theme is missing dist/material-icons.json"
  end
  local valid, decoded = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(manifest), "\n"))
  end)
  if not valid or type(decoded) ~= "table" or type(decoded.iconDefinitions) ~= "table" then
    remove_path(archive)
    remove_path(staging)
    return false, "downloaded Material Icon Theme has an invalid icon manifest"
  end

  remove_path(backup)
  if path_util.exists(root) then
    ok, err = rename_path(root, backup)
    if not ok then
      remove_path(archive)
      remove_path(staging)
      return false, err
    end
  end

  ok, err = rename_path(staging, root)
  if not ok then
    if path_util.exists(backup) then
      rename_path(backup, root)
    end
    remove_path(archive)
    remove_path(staging)
    return false, err
  end

  remove_path(archive)
  remove_path(backup)
  loaded[name .. "|dark"] = nil
  loaded[name .. "|light"] = nil

  if opts.notify ~= false then
    require("real-icons.log").info("Installed Material Icon Theme " .. source.version)
  end
  return true
end

function M.clear_cache()
  loaded = {}
  load_errors = {}
end

function M.install_async(name, opts)
  name = name or "material"
  opts = opts or {}
  if name ~= "material" then
    return false, "unknown installable pack: " .. tostring(name)
  end
  if installing[name] then
    return false, "Material Icon Theme installation is already running"
  end
  installing[name] = "Starting installation"
  local thread = coroutine.create(function()
    return M.install(name, { _async = true, notify = false })
  end)
  local resume
  local function complete(ok, err)
    installing[name] = nil
    require("real-icons.events").changed("install")
    if opts.on_complete then
      opts.on_complete(ok, err)
    end
  end
  resume = function(ok, err)
    local resumed, result, install_err = coroutine.resume(thread, ok, err)
    if not resumed then
      complete(false, tostring(result))
    elseif coroutine.status(thread) == "dead" then
      complete(result, install_err)
    else
      local command = result
      installing[name] = command[1] == "curl" and "Downloading Material Icon Theme"
        or "Unpacking Material Icon Theme"
      require("real-icons.events").changed("install")
      local started, process = pcall(
        vim.system,
        command,
        { text = true, timeout = 120000 },
        function(output)
          vim.schedule(function()
            resume(
              output.code == 0,
              output.code ~= 0 and path_util.shell_error(command, output.stderr or output.stdout)
                or nil
            )
          end)
        end
      )
      if not started then
        vim.schedule(function()
          resume(false, tostring(process))
        end)
      end
    end
  end
  resume()
  return true
end

return M
