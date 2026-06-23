local util = require("real-icons.packs.util")

local M = {}

local function resolve_relative(base, path)
  if not path or path == "" then
    return base
  end
  if path:sub(1, 1) == "/" then
    return path
  end
  return vim.fs.normalize(base .. "/" .. path)
end

local function theme_manifest(root, spec)
  if spec.manifest then
    return util.join(root, spec.manifest)
  end

  local package_file = util.join(root, "package.json")
  local package = util.read_json(package_file)
  local icon_themes = package and package.contributes and package.contributes.iconThemes or {}

  if #icon_themes == 0 then
    return util.join(root, "dist", "material-icons.json")
  end

  local requested = spec.theme or spec.id
  local selected = icon_themes[1]
  if requested then
    selected = nil
    for _, theme in ipairs(icon_themes) do
      if theme.id == requested or theme.label == requested then
        selected = theme
        break
      end
    end
    if not selected then
      return nil, "icon theme not found: " .. requested
    end
  end

  return util.join(root, selected.path)
end

function M.load(name, spec)
  local root = util.expand(assert(spec.path, "vscode icon pack requires path"))
  local manifest_file, manifest_err = theme_manifest(root, spec)
  if not manifest_file then
    return nil, manifest_err
  end

  local manifest, err = util.read_json(manifest_file)
  if not manifest then
    return nil, err
  end

  local manifest_dir = vim.fs.dirname(manifest_file)
  local definitions = {}
  for key, value in pairs(manifest.iconDefinitions or {}) do
    if value.iconPath then
      definitions[key] = resolve_relative(manifest_dir, value.iconPath)
    end
  end

  return {
    name = name,
    root = root,
    manifest = manifest_file,
    license = spec.license,
    definitions = definitions,
    file = manifest.file,
    folder = manifest.folder,
    folder_expanded = manifest.folderExpanded,
    root_folder = manifest.rootFolder,
    root_folder_expanded = manifest.rootFolderExpanded,
    file_extensions = manifest.fileExtensions or {},
    file_names = manifest.fileNames or {},
    folder_names = manifest.folderNames or {},
    folder_names_expanded = manifest.folderNamesExpanded or {},
    language_ids = manifest.languageIds or {},
  }
end

return M
