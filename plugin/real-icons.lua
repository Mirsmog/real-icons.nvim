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
    return { "material", "builtin" }
  end,
})

vim.api.nvim_create_user_command("RealIconsOilEnable", function()
  real_icons().setup({ integrations = { oil = true } })
  require("real-icons.integrations.oil").attach_current()
end, {})
