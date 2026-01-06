---
--- server_selector.lua - Server selection UI for when health check fails
---
local M = {}

--- Show server selector popup
--- @param opts table Options
--- @param opts.servers table<string, {url: string}> Available servers
--- @param opts.failed_server string? Server that failed health check (marked as unreachable)
--- @param opts.on_select fun(server_name: string) Called when user selects a server
--- @param opts.on_cancel fun() Called when user cancels selection
function M.show(opts)
  local servers = opts.servers or {}
  local failed_server = opts.failed_server
  local on_select = opts.on_select
  local on_cancel = opts.on_cancel or function() end

  -- Build list of server names with status indicators
  local items = {}
  local name_map = {} -- display string -> server name

  for name, config in pairs(servers) do
    local display
    if name == failed_server then
      display = string.format("%s (%s) [unreachable]", name, config.url)
    else
      display = string.format("%s (%s)", name, config.url)
    end
    table.insert(items, display)
    name_map[display] = name
  end

  table.sort(items)

  if #items == 0 then
    vim.notify("No servers configured", vim.log.levels.ERROR)
    on_cancel()
    return
  end

  vim.ui.select(items, {
    prompt = "Select server (current unreachable):",
    format_item = function(item)
      -- Highlight unreachable server
      if item:match("%[unreachable%]$") then
        return item
      end
      return item
    end,
  }, function(choice)
    if not choice then
      on_cancel()
      return
    end

    local server_name = name_map[choice]
    if server_name then
      on_select(server_name)
    else
      on_cancel()
    end
  end)
end

return M
