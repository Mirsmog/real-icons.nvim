local window = require("real-icons.ui.window")
local M = {}
local current

function M.open()
  if current and current.valid() then
    vim.api.nvim_set_current_win(current.winid)
    return current
  end
  local state = window.open("real-icons-overview", "real-icons.nvim", 78, 25)
  current = state
  local ns = vim.api.nvim_create_namespace("real-icons-dashboard")
  function state.render()
    if not state.valid() then
      return
    end
    window.highlights()
    local status = require("real-icons.status").snapshot()
    local caps = status.capabilities
    local lines = {
      "",
      "  Make your files easier to recognise.",
      "",
      "  YOUR SETUP",
      "",
      "  Renderer      " .. (caps.images and "Image icons" or "Font icons (fallback)"),
      "  Terminal      " .. caps.terminal .. (caps.tmux and " inside tmux" or ""),
      "  Icon pack     " .. status.selected_pack,
    }
    local notes = {}
    if caps.reason then
      notes[#notes + 1] = caps.reason
    end
    if status.pack_error then
      notes[#notes + 1] = "Using built-in icons. " .. status.pack_error .. "."
    end
    if not status.conversion then
      notes[#notes + 1] = "Install ImageMagick to use SVG themes."
    end
    if status.installing then
      notes[#notes + 1] = status.installing .. "..."
    end
    if status.cache.pending > 0 then
      notes[#notes + 1] = "Preparing " .. status.cache.pending .. " icons in the background..."
    end
    if status.cache.failed > 0 then
      notes[#notes + 1] = "Some icons could not be prepared. Press h for diagnostics."
    end
    for _, note in ipairs(notes) do
      lines[#lines + 1] = "  " .. note
    end
    lines[#lines + 1] = ""
    local integration_row = #lines
    lines[#lines + 1] = "  INTEGRATIONS"
    local enabled = 0
    for _, name in ipairs(vim.fn.sort(vim.tbl_keys(status.integrations))) do
      local item = status.integrations[name]
      if item.enabled then
        enabled = enabled + 1
        lines[#lines + 1] = "  "
          .. require("real-icons.status").labels[name]
          .. ": "
          .. (item.status == "ready" and "Connected" or item.error or item.status)
      end
    end
    if enabled == 0 then
      lines[#lines + 1] = "  None enabled. Press ? for setup examples."
    end
    vim.list_extend(lines, {
      "",
      "  TRY IT",
      "",
      "  p  Choose a theme          d  Preview icons",
      "  i  Install Material        h  Check health",
      "  r  Retry integrations      y  Copy diagnostics",
      "",
      "  ?  Help                    q  Close",
      "",
    })
    state.resize(78, #lines)
    for i, line in ipairs(lines) do
      lines[i] = window.fit(line, state.width - 1)
    end
    state.lines(lines)
    vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
    for _, row in ipairs({ 1, 3, integration_row, #lines - 8 }) do
      vim.api.nvim_buf_set_extmark(
        state.bufnr,
        ns,
        row,
        0,
        { end_col = #lines[row + 1], hl_group = "RealIconsAccent" }
      )
    end
    vim.api.nvim_buf_set_extmark(state.bufnr, ns, 5, math.min(16, #lines[6]), {
      end_col = #lines[6],
      hl_group = caps.images and "RealIconsReady" or "RealIconsWarning",
      strict = false,
    })
  end
  state.map("p", function()
    state.close()
    require("real-icons").select_pack()
  end)
  state.map("d", function()
    state.close()
    require("real-icons").demo()
  end)
  state.map("i", function()
    require("real-icons").install_pack("material", { async = true })
    state.render()
  end)
  state.map("h", function()
    state.close()
    vim.cmd("checkhealth real-icons")
  end)
  state.map("?", function()
    state.close()
    vim.cmd("help real-icons")
  end)
  state.map("r", function()
    require("real-icons").retry_integrations()
    state.render()
  end)
  state.map("y", function()
    require("real-icons.preferences").copy(require("real-icons.status").report())
  end)
  window.watch(state, state.render)
  state.render()
  return state
end

return M
