local M = {}

function M.highlights()
  for name, link in pairs({
    Title = "Title",
    Muted = "Comment",
    Accent = "Special",
    Ready = "DiagnosticOk",
    Warning = "DiagnosticWarn",
    Selected = "Visual",
  }) do
    vim.api.nvim_set_hl(0, "RealIcons" .. name, { link = link, default = true })
  end
  local border = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
  local normal = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
  local comment = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "RealIconsBorder", {
    fg = border.fg or comment.fg,
    bg = normal.bg,
    default = true,
  })
end

function M.fit(text, width)
  text = tostring(text):gsub("[\r\n\t]", " ")
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  while #text > 0 and vim.fn.strdisplaywidth(text) > math.max(0, width - 1) do
    text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
  end
  return width > 0 and text .. "…" or ""
end

function M.layout(width, height)
  width = math.max(1, math.min(width, vim.o.columns - 4))
  height = math.max(1, math.min(height, vim.o.lines - vim.o.cmdheight - 4))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width - 2) / 2)),
  }
end

function M.open(name, title, width, height)
  M.highlights()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.api.nvim_buf_set_name(bufnr, name)
  local layout = M.layout(width, height)
  local winid = vim.api.nvim_open_win(
    bufnr,
    true,
    vim.tbl_extend("force", layout, {
      style = "minimal",
      border = "rounded",
      title = " " .. title .. " ",
      title_pos = "center",
    })
  )
  vim.wo[winid].wrap = false
  vim.wo[winid].winhighlight = "FloatBorder:RealIconsBorder,FloatTitle:RealIconsAccent"
  local state = { bufnr = bufnr, winid = winid, width = layout.width, height = layout.height }
  function state.valid()
    return vim.api.nvim_win_is_valid(winid) and vim.api.nvim_buf_is_valid(bufnr)
  end
  function state.close()
    if state.valid() then
      vim.api.nvim_win_close(winid, true)
    end
  end
  function state.resize(w, h)
    if not state.valid() then
      return
    end
    local next_layout = M.layout(w, h)
    vim.api.nvim_win_set_config(winid, next_layout)
    state.width, state.height = next_layout.width, next_layout.height
  end
  function state.lines(lines)
    if not state.valid() then
      return
    end
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].modifiable = false
  end
  function state.map(key, callback)
    vim.keymap.set("n", key, callback, { buffer = bufnr, nowait = true, silent = true })
  end
  state.map("q", state.close)
  state.map("<Esc>", state.close)
  return state
end

function M.watch(state, callback)
  local ids = {}
  ids[#ids + 1] = vim.api.nvim_create_autocmd("User", {
    pattern = "RealIconsUpdated",
    callback = function()
      if state.valid() then
        callback()
      end
    end,
  })
  ids[#ids + 1] = vim.api.nvim_create_autocmd("VimResized", {
    callback = function()
      if state.valid() then
        callback()
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = state.bufnr,
    once = true,
    callback = function()
      for _, id in ipairs(ids) do
        pcall(vim.api.nvim_del_autocmd, id)
      end
    end,
  })
end

return M
