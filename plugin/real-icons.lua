if vim.g.loaded_real_icons == 1 then
  return
end
vim.g.loaded_real_icons = 1

local function real_icons()
  return require("real-icons")
end

vim.api.nvim_create_user_command("RealIconsDemo", function()
  real_icons().demo()
end, {})

vim.api.nvim_create_user_command("RealIconsHealth", function()
  vim.cmd("checkhealth real-icons")
end, {})

vim.api.nvim_create_user_command("RealIconsInstallPack", function(args)
  require("real-icons").install_pack(args.args ~= "" and args.args or nil)
end, {
  nargs = "?",
  complete = function()
    return { "material" }
  end,
})

vim.api.nvim_create_user_command("RealIconsBuildCache", function()
  require("real-icons").build_cache()
end, {})

vim.api.nvim_create_user_command("RealIconsClearCache", function(args)
  require("real-icons").clear_cache(args.args ~= "" and args.args or nil)
end, {
  nargs = "?",
  complete = function()
    return real_icons().available_packs()
  end,
})

vim.api.nvim_create_user_command("RealIconsUsePack", function(args)
  local icons = real_icons()
  if args.args == "" then
    vim.notify(
      "Current icon pack: " .. icons.pack(),
      vim.log.levels.INFO,
      { title = "real-icons.nvim" }
    )
    return
  end

  local ok, err = icons.use_pack(args.args)
  if not ok then
    vim.notify(err, vim.log.levels.ERROR, { title = "real-icons.nvim" })
  end
end, {
  nargs = "?",
  complete = function()
    return real_icons().available_packs()
  end,
})

vim.api.nvim_create_user_command("RealIconsPacks", function()
  local icons = real_icons()
  local current = icons.pack()
  local lines = {}
  for _, name in ipairs(icons.available_packs()) do
    lines[#lines + 1] = (name == current and "* " or "  ") .. name
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "real-icons.nvim" })
end, {})

vim.api.nvim_create_user_command("RealIconsOilEnable", function()
  real_icons().setup({ integrations = { oil = true } })
  require("real-icons.integrations.oil").attach_current()
end, {})
