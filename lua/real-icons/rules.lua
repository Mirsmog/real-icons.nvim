local M = {}

local compiled_globs = {}
local compiled_rule_lists = setmetatable({}, { __mode = "k" })
local empty_rules = {}
local is_list = vim.islist or vim.tbl_islist

local function directory_rules(rules)
  if rules == nil then
    return empty_rules
  end
  if type(rules) ~= "table" then
    error("real-icons rules must be a table")
  end

  local directories = rules.directories
  if directories == nil then
    return empty_rules
  end
  if type(directories) ~= "table" or not is_list(directories) then
    error("real-icons rules.directories must be a list")
  end
  return directories
end

local function compile_glob(glob, index)
  local compiled = compiled_globs[glob]
  if compiled then
    return compiled
  end

  local ok, matcher = pcall(vim.glob.to_lpeg, glob)
  if not ok then
    error(string.format(
      "real-icons rules.directories[%d].glob is invalid: %s",
      index,
      matcher
    ))
  end
  compiled_globs[glob] = matcher
  return matcher
end

local function validate_rule(rule, index)
  if type(rule) ~= "table" then
    error(string.format("real-icons rules.directories[%d] must be a table", index))
  end
  if type(rule.glob) ~= "string" or rule.glob == "" then
    error(string.format(
      "real-icons rules.directories[%d].glob must be a non-empty string",
      index
    ))
  end
  if type(rule.icon) ~= "string" or rule.icon == "" then
    error(string.format(
      "real-icons rules.directories[%d].icon must be a non-empty string",
      index
    ))
  end
  compile_glob(rule.glob, index)
end

local function normalize_path(path)
  path = tostring(path or ""):gsub("\\", "/")
  path = path:gsub("/+", "/")
  if #path > 1 then
    path = path:gsub("/+$", "")
  end
  return path
end

local function compile_rules(rules)
  local directories = directory_rules(rules)
  local cached = compiled_rule_lists[directories]
  if cached then
    return cached
  end

  local compiled = {}
  for index, rule in ipairs(directories) do
    validate_rule(rule, index)
    if rule.enabled ~= false then
      compiled[#compiled + 1] = {
        icon = rule.icon,
        matcher = compile_glob(rule.glob, index),
      }
    end
  end
  compiled_rule_lists[directories] = compiled
  return compiled
end

function M.validate(rules)
  compile_rules(rules)
end

function M.has_directory_rules(rules)
  return #compile_rules(rules) > 0
end

function M.match_directory(path, rules, accept)
  local compiled = compile_rules(rules)
  if #compiled == 0 then
    return
  end
  path = normalize_path(path)
  for _, rule in ipairs(compiled) do
    if rule.matcher:match(path) and (not accept or accept(rule.icon)) then
      return rule.icon
    end
  end
end

return M
