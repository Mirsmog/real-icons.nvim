local config = require("real-icons.config")
local path_util = require("real-icons.path")

local M = {}

local loaded = {}

local material = {
  name = "material",
  version = "5.35.0",
  url = "https://registry.npmjs.org/material-icon-theme/-/material-icon-theme-5.35.0.tgz",
  license = "MIT",
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
    license = "MIT",
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
  return loader.load(name, spec)
end

function M.installed(name)
  if name == "builtin" then
    return true
  end
  if name == "material" then
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
  if loaded[name] then
    return loaded[name]
  end

  local spec = spec_for(name)
  local pack
  if spec and M.installed(name) then
    pack = load_spec(name, spec)
  end

  if not pack then
    pack = require("real-icons.packs.loaders.builtin").load()
  end

  loaded[name] = pack
  return pack
end

function M.source(name)
  if name == "material" then
    return material
  end
  return spec_for(name)
end

local function run(command)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    return false, path_util.shell_error(command, output)
  end
  return true
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
  path_util.ensure_dir(parent)

  local tmp = vim.fn.tempname()
  local archive = tmp .. ".tgz"

  local ok, err = run({ "curl", "-L", "--fail", "-o", archive, source.url })
  if not ok then
    return false, err
  end

  vim.fn.delete(root, "rf")
  path_util.ensure_dir(root)

  ok, err = run({ "tar", "-xzf", archive, "--strip-components=1", "-C", root })
  if not ok then
    vim.fn.delete(archive)
    vim.fn.delete(root, "rf")
    return false, err
  end

  vim.fn.delete(archive)
  loaded[name] = nil

  if opts.notify ~= false then
    require("real-icons.log").info("Installed Material Icon Theme " .. source.version)
  end
  return true
end

function M.clear_cache()
  loaded = {}
end

return M
