local M = {}

local command_order = {
  "demo",
  "packs",
  "install",
  "health",
  "help",
  "clear-cache",
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "real-icons.nvim" })
end

local function real_icons()
  return require("real-icons")
end

local actions = {
  demo = {
    label = "Preview icons",
    max_args = 0,
    run = function()
      real_icons().demo()
      return true
    end,
  },
  packs = {
    label = "Choose an icon pack",
    max_args = 0,
    run = function()
      real_icons().select_pack()
      return true
    end,
  },
  install = {
    label = "Install Material Icon Theme",
    max_args = 1,
    run = function(args)
      return real_icons().install_pack(args[1] or "material")
    end,
  },
  health = {
    label = "Run health checks",
    max_args = 0,
    run = function()
      vim.cmd("checkhealth real-icons")
      return true
    end,
  },
  help = {
    label = "Open help",
    max_args = 0,
    run = function()
      vim.cmd("help real-icons")
      return true
    end,
  },
  ["clear-cache"] = {
    label = "Clear the icon cache",
    max_args = 1,
    run = function(args)
      return real_icons().clear_cache(args[1])
    end,
  },
}

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function matching(values, prefix)
  local result = {}
  for _, value in ipairs(values) do
    if starts_with(value, prefix or "") then
      result[#result + 1] = value
    end
  end
  return result
end

local function action_error(message)
  message = tostring(message)
  notify(message, vim.log.levels.ERROR)
  return false, message
end

function M.open()
  local items = {}
  for _, name in ipairs({ "demo", "packs", "install", "health", "help" }) do
    items[#items + 1] = {
      name = name,
      label = actions[name].label,
    }
  end

  vim.ui.select(items, {
    prompt = "real-icons.nvim",
    format_item = function(item)
      return item.label
    end,
  }, function(item)
    if item then
      M.execute({ item.name })
    end
  end)
  return true
end

function M.execute(args)
  args = vim.deepcopy(args or {})
  local name = table.remove(args, 1)
  if not name or name == "" then
    return M.open()
  end

  local action = actions[name]
  if not action then
    return action_error(
      "Unknown action '" .. name .. "'. Available: " .. table.concat(command_order, ", ")
    )
  end
  if #args > action.max_args then
    return action_error("Too many arguments for '" .. name .. "'")
  end

  local ok, result, err = pcall(action.run, args)
  if not ok then
    return action_error(result)
  end
  if result == false then
    return false, err or ("Action '" .. name .. "' failed")
  end
  return result == nil and true or result, err
end

local function route(action, args)
  local routed = { action }
  vim.list_extend(routed, args or {})
  return M.execute(routed)
end

-- Old commands are created only after CmdUndefined fires, then removed again.
-- Existing configs keep working without adding deprecated names to completion.
local legacy_actions = {}
local legacy_routes = {
  RealIconsClearCache = { "clear-cache", "?" },
  RealIconsDemo = { "demo", 0 },
  RealIconsDiscoverPacks = { "packs", 0 },
  RealIconsHealth = { "health", 0 },
  RealIconsInstallPack = { "install", "?" },
  RealIconsPacks = { "packs", 0 },
  RealIconsSelectPack = { "packs", 0 },
}

for name, spec in pairs(legacy_routes) do
  local action = spec[1]
  legacy_actions[name] = {
    nargs = spec[2],
    run = function(args)
      return route(action, args)
    end,
  }
end

legacy_actions.RealIconsBuildCache = {
  nargs = 0,
  run = function()
    real_icons().build_cache()
    return true
  end,
}

legacy_actions.RealIconsOilEnable = {
  nargs = 0,
  run = function()
    local ok, err = real_icons().enable_integration("oil")
    if not ok then
      return action_error(err)
    end
    local attached, attach_err = require("real-icons.integrations.oil").attach_current()
    if attached == false then
      return action_error(attach_err)
    end
    return true
  end,
}

legacy_actions.RealIconsUsePack = {
  nargs = "?",
  run = function(args)
    if not args[1] then
      notify("Current icon pack: " .. real_icons().pack())
      return true
    end
    local ok, err = real_icons().use_pack(args[1])
    if not ok then
      return action_error(err)
    end
    return true
  end,
}

local legacy_names = vim.tbl_keys(legacy_actions)
table.sort(legacy_names)

local function define_legacy_command(name)
  local legacy = legacy_actions[name]
  if not legacy then
    return
  end

  vim.api.nvim_create_user_command(name, function(opts)
    local ok, err = pcall(legacy.run, opts.fargs)
    pcall(vim.api.nvim_del_user_command, name)
    if not ok then
      action_error(err)
    end
  end, {
    nargs = legacy.nargs,
    desc = "Compatibility command for real-icons.nvim",
  })
end

function M.complete(arg_lead, cmd_line, cursor_pos)
  local before_cursor = cmd_line:sub(1, cursor_pos)
  local arguments = before_cursor:match("^%s*RealIcons!?%s*(.*)$") or ""
  local trailing_space = arguments:match("%s$") ~= nil
  local words = vim.split(arguments, "%s+", { trimempty = true })

  if #words == 0 or (#words == 1 and not trailing_space) then
    return matching(command_order, arg_lead)
  end

  local action = words[1]
  if action == "install" then
    return matching({ "material" }, arg_lead)
  end
  if action == "clear-cache" then
    return matching(real_icons().available_packs(), arg_lead)
  end
  return {}
end

function M.setup()
  vim.api.nvim_create_user_command("RealIcons", function(opts)
    M.execute(opts.fargs)
  end, {
    nargs = "*",
    complete = M.complete,
    desc = "Manage real-icons.nvim",
    force = true,
  })

  local group = vim.api.nvim_create_augroup("RealIconsCommands", { clear = true })
  vim.api.nvim_create_autocmd("CmdUndefined", {
    group = group,
    pattern = legacy_names,
    callback = function(args)
      define_legacy_command(args.match)
    end,
    desc = "Load removed real-icons.nvim commands only when an old config calls one",
  })
end

return M
