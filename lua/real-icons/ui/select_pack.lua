local config = require("real-icons.config")
local packs = require("real-icons.packs")
local discovery = require("real-icons.packs.discovery")
local window = require("real-icons.ui.window")
local preferences = require("real-icons.preferences")

local M = {}
local current
local samples = {
  { "directory", "src", "src/" },
  { "directory", "node_modules", "node_modules/" },
  { "file", "README.md", "README.md" },
  { "file", "package.json", "package.json" },
  { "file", "init.lua", "init.lua" },
  { "file", "widget.test.ts", "widget.test.ts" },
  { "file", "types.d.ts", "types.d.ts" },
  { "file", "Dockerfile", "Dockerfile" },
}

local function candidates()
  local result, seen = {}, {}
  for _, candidate in ipairs(discovery.discover()) do
    packs.register(candidate.name, candidate.spec)
    result[#result + 1] = candidate
    seen[candidate.name] = true
  end
  for _, name in ipairs(packs.names()) do
    if not seen[name] then
      result[#result + 1] = {
        name = name,
        label = name == "builtin" and "Built-in"
          or name == "material" and "Material Icon Theme"
          or name,
        source = name == "builtin" and "Bundled with real-icons" or "Configured pack",
      }
    end
  end
  table.sort(result, function(a, b)
    if a.name == b.name then
      return false
    end
    if a.name == config.options.pack then
      return true
    end
    if b.name == config.options.pack then
      return false
    end
    return a.label:lower() < b.label:lower()
  end)
  return result
end

function M.open()
  if current and current.valid() then
    vim.api.nvim_set_current_win(current.winid)
    return current
  end
  local state = window.open("real-icons-pack-picker", "Choose your icons", 104, 27)
  current = state
  state.candidates, state.filtered, state.index, state.query = candidates(), {}, 1, ""
  local ns = vim.api.nvim_create_namespace("real-icons-pack-picker")

  function state.render()
    if not state.valid() then
      return
    end
    window.highlights()
    state.resize(104, 27)
    local icons = require("real-icons")
    local count = #state.filtered
    local selected = state.filtered[state.index]
    local wide = state.width >= 72
    local left_width = wide and math.floor(state.width * 0.44) or state.width
    local height = math.max(1, state.height - 8)
    local first = math.max(1, state.index - height + 1)
    local lines = {
      "",
      "  / Search: "
        .. (state.query ~= "" and state.query or "all themes")
        .. "  ("
        .. count
        .. ")",
      "",
      "  ICON PACKS",
    }
    local preview = selected
        and {
          selected.label,
          selected.extension or selected.source or "",
          "",
          packs.installing(selected.name)
            or (packs.installed(selected.name) and "Sample files" or "Not installed. Press i."),
        }
      or {}
    local marks = {}
    for offset = 1, height do
      local index = first + offset - 1
      local item = state.filtered[index]
      local left = ""
      if item then
        local marker = item.name == config.options.pack and "* " or "  "
        local badge = packs.installed(item.name) and "" or " [install]"
        left = "  " .. marker .. item.label .. badge
      elseif offset == 1 then
        left = "  No matching themes. Press / to search."
      end
      left = window.fit(left, math.max(1, left_width - 2))
      if wide then
        left = left
          .. string.rep(" ", math.max(0, left_width - vim.fn.strdisplaywidth(left)))
          .. "│  "
        local sample = samples[offset - 4]
        local right = preview[offset] or (sample and sample[3]) or ""
        local extra = sample and config.options.size.cols + 1 or 0
        right = window.fit(right, math.max(1, state.width - left_width - 5 - extra))
        lines[#lines + 1] = left .. right
        if selected and sample then
          marks[#marks + 1] = { row = #lines - 1, col = #left, sample = sample }
        end
      else
        lines[#lines + 1] = left
      end
    end
    if wide then
      vim.list_extend(lines, {
        "",
        "  Enter Apply   s Save default   y Copy pack config",
        "  / Search      i Install       j/k Move   q Close",
        "",
      })
    else
      local label = selected and ("  Preview: " .. selected.label) or "  No theme selected"
      vim.list_extend(lines, {
        "",
        window.fit(label, state.width - 4),
        "  Enter Apply  / Search  s Save",
        "  y Copy  i Install  q Close",
      })
      if selected then
        marks[#marks + 1] = { row = #lines - 3, col = 2, sample = samples[5] }
      end
    end
    for i, line in ipairs(lines) do
      lines[i] = window.fit(line, state.width)
    end
    icons.clear(state.bufnr)
    state.lines(lines)
    vim.api.nvim_buf_clear_namespace(state.bufnr, ns, 0, -1)
    for _, heading in ipairs({
      { 1, "RealIconsMuted" },
      { 3, "RealIconsAccent" },
      { #lines - 3, "RealIconsMuted" },
      { #lines - 2, "RealIconsMuted" },
    }) do
      vim.api.nvim_buf_set_extmark(state.bufnr, ns, heading[1], 0, {
        end_col = #lines[heading[1] + 1],
        hl_group = heading[2],
      })
    end
    local row = 4 + state.index - first
    if count > 0 then
      vim.api.nvim_buf_set_extmark(state.bufnr, ns, row, 0, {
        end_col = #window.fit(lines[row + 1], left_width),
        hl_group = "RealIconsSelected",
      })
      vim.api.nvim_win_set_cursor(state.winid, { row + 1, 0 })
    end
    if selected then
      for _, mark in ipairs(marks) do
        icons.render(state.bufnr, mark.row, mark.col, mark.sample[1], mark.sample[2], {
          pack = selected.name,
        })
      end
    end
  end

  function state.filter(query)
    state.query = query or ""
    state.filtered = {}
    for _, item in ipairs(state.candidates) do
      local haystack = table.concat({ item.label, item.name, item.extension or "" }, " "):lower()
      if haystack:find(state.query:lower(), 1, true) then
        state.filtered[#state.filtered + 1] = item
      end
    end
    state.index = 1
    state.render()
  end

  function state.move(delta)
    if #state.filtered > 0 then
      state.index = ((state.index - 1 + delta) % #state.filtered) + 1
      state.render()
    end
  end

  function state.choose(save)
    local selected = state.filtered[state.index]
    if not selected then
      return false
    end
    packs.get(selected.name)
    local err = packs.last_error(selected.name)
    if err then
      require("real-icons.log").warn(
        err .. (selected.name == "material" and ". Press i to install." or ". Check the pack path.")
      )
      return false, err
    end
    local ok, use_err =
      require("real-icons").use_pack(selected.name, { save = save, notify = false })
    if not ok then
      require("real-icons.log").error(use_err)
      return false, use_err
    end
    state.close()
    local message = "Using "
      .. selected.label
      .. (save and ". Saved as your default." or ". This session only.")
    if save and config.explicit_pack then
      message = message .. " Your explicit pack setting takes priority on restart."
    end
    require("real-icons.log").info(message)
    return true
  end

  state.map("j", function()
    state.move(1)
  end)
  state.map("<Down>", function()
    state.move(1)
  end)
  state.map("k", function()
    state.move(-1)
  end)
  state.map("<Up>", function()
    state.move(-1)
  end)
  state.map("<CR>", function()
    state.choose(false)
  end)
  state.map("s", function()
    state.choose(true)
  end)
  state.map("/", function()
    vim.ui.input({ prompt = "Filter icon themes: ", default = state.query }, function(query)
      if query ~= nil and state.valid() then
        state.filter(query)
      end
    end)
  end)
  state.map("y", function()
    local selected = state.filtered[state.index]
    if selected then
      preferences.copy(preferences.config(selected.name))
    end
  end)
  state.map("i", function()
    local selected = state.filtered[state.index]
    if selected and selected.name == "material" then
      require("real-icons").install_pack("material", { async = true })
      state.render()
    else
      require("real-icons.log").info(
        "Only Material Icon Theme can be installed here. Other themes use local files."
      )
    end
  end)
  window.watch(state, state.render)
  state.filter("")
  return state
end

return M
