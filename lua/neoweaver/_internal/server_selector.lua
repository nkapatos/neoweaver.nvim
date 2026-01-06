--- Server selection UI for health check failures
local M = {}

---@param opts {servers: table<string, {url: string}>, failed_server: string?, on_select: fun(name: string), on_cancel: fun()}
function M.show(opts)
  local servers = opts.servers or {}
  local failed_server = opts.failed_server
  local on_select = opts.on_select
  local on_cancel = opts.on_cancel or function() end

  local items = {}
  local name_map = {}

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
