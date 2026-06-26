local renderer = require("real-icons.render.placeholder")
local resolver = require("real-icons.resolver")

local M = {}

local uv = vim.uv or vim.loop
local group = vim.api.nvim_create_augroup("real-icons-oil", { clear = true })
local attached = {}
local timers = {}

local function close_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

local function join(dir, name)
  if dir:sub(-1) == "/" then
    return dir .. name
  end
  return dir .. "/" .. name
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local ok, oil = pcall(require, "oil")
  if not ok then
    return
  end

  local dir = oil.get_current_dir(bufnr)
  if not dir then
    return
  end

  renderer.clear(bufnr)

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for lnum = 1, line_count do
    local entry = oil.get_entry_on_line(bufnr, lnum)
    if entry and entry.name and entry.name ~= ".." then
      local is_dir = entry.type == "directory"
      local icon = resolver.resolve(is_dir and "directory" or "file", join(dir, entry.name))
      renderer.render(bufnr, lnum - 1, 0, icon, { priority = 250 })
    end
  end
end

function M.attach(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if attached[bufnr] then
    M.refresh(bufnr)
    return
  end
  attached[bufnr] = true

  local function schedule_refresh()
    if timers[bufnr] then
      close_timer(timers[bufnr])
    end

    local timer = uv.new_timer()
    if not timer then
      vim.schedule(function()
        M.refresh(bufnr)
      end)
      return
    end

    timers[bufnr] = timer
    timer:start(30, 0, vim.schedule_wrap(function()
      if timers[bufnr] == timer then
        timers[bufnr] = nil
      end
      close_timer(timer)
      M.refresh(bufnr)
    end))
  end

  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI" }, {
    group = group,
    buffer = bufnr,
    callback = schedule_refresh,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = bufnr,
    callback = function()
      attached[bufnr] = nil
      if timers[bufnr] then
        close_timer(timers[bufnr])
        timers[bufnr] = nil
      end
    end,
  })

  schedule_refresh()
end

function M.attach_current()
  M.attach(vim.api.nvim_get_current_buf())
end

function M.setup()
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "oil",
    callback = function(args)
      M.attach(args.buf)
    end,
  })
end

return M
