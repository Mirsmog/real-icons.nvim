local path_util = require("real-icons.path")

local M = {}

function M.load()
  local root = path_util.project_root()
  local assets = path_util.join(root, "assets")
  return {
    name = "builtin",
    root = root,
    license = "MIT",
    definitions = {
      file = path_util.join(assets, "filetypes", "default.png"),
      folder = path_util.join(assets, "folders", "default.png"),
      lua = path_util.join(assets, "filetypes", "lua.png"),
      javascript = path_util.join(assets, "filetypes", "javascript.png"),
      typescript = path_util.join(assets, "filetypes", "typescript.png"),
      json = path_util.join(assets, "filetypes", "json.png"),
      markdown = path_util.join(assets, "filetypes", "markdown.png"),
      rust = path_util.join(assets, "filetypes", "rust.png"),
      text = path_util.join(assets, "filetypes", "text.png"),
      git = path_util.join(assets, "filetypes", "git.png"),
      ["folder-src"] = path_util.join(assets, "folders", "src.png"),
      ["folder-test"] = path_util.join(assets, "folders", "test.png"),
      ["folder-node_modules"] = path_util.join(assets, "folders", "node_modules.png"),
    },
    file = "file",
    folder = "folder",
    file_extensions = {
      js = "javascript",
      jsx = "javascript",
      ts = "typescript",
      tsx = "typescript",
      json = "json",
      lua = "lua",
      md = "markdown",
      rs = "rust",
      txt = "text",
    },
    file_names = {
      [".gitignore"] = "git",
      ["README.md"] = "markdown",
      ["package.json"] = "json",
    },
    folder_names = {
      src = "folder-src",
      test = "folder-test",
      tests = "folder-test",
      node_modules = "folder-node_modules",
    },
  }
end

return M
