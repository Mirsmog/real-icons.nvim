local M = {}

function M.path()
  return vim.fn.stdpath("state") .. "/real-icons/selection.json"
end

function M.read()
  local file = M.path()
  if vim.fn.filereadable(file) ~= 1 then
    return nil
  end
  local ok, data = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(file), "\n"))
  end)
  if not ok or type(data) ~= "table" or type(data.pack) ~= "string" or data.pack == "" then
    return nil
  end
  if
    data.spec ~= nil
    and (
      type(data.spec) ~= "table"
      or type(data.spec.path) ~= "string"
      or (data.spec.type ~= "simple" and data.spec.type ~= "vscode")
    )
  then
    return nil
  end
  return data
end

function M.save(name)
  local packs = require("real-icons.packs")
  if not packs.source(name) then
    return false, "unknown icon pack: " .. tostring(name)
  end
  local data = { pack = name }
  if name ~= "builtin" and name ~= "material" then
    data.spec = packs.spec(name)
  end
  local file = M.path()
  local temporary = file .. "." .. vim.fn.getpid() .. ".tmp"
  local ok, err = pcall(function()
    vim.fn.mkdir(vim.fs.dirname(file), "p")
    assert(vim.fn.writefile({ vim.json.encode(data) }, temporary) == 0, "unable to write selection")
    local renamed, rename_err = (vim.uv or vim.loop).fs_rename(temporary, file)
    assert(renamed, rename_err)
  end)
  if not ok then
    vim.fn.delete(temporary)
    return false, tostring(err)
  end
  return true
end

function M.config(name)
  local options = { pack = name }
  if name ~= "builtin" and name ~= "material" then
    options.packs = { [name] = require("real-icons.packs").spec(name) }
  end
  return "-- Merge these fields into your real-icons setup options.\n" .. vim.inspect(options)
end

function M.copy(text)
  vim.fn.setreg('"', text)
  local copied = false
  if vim.fn.has("clipboard") == 1 then
    copied = pcall(vim.fn.setreg, "+", text)
  end
  require("real-icons.log").info(
    copied and "Copied to clipboard" or "Copied to the unnamed register. Paste with p."
  )
end

return M
