local M = {}

---@class ConnectError Connect RPC error format
---@field code string Error code (e.g., "invalid_argument", "not_found")
---@field message string Human-readable error message
---@field details? table[] Additional error details

---@class ApiResponse
---@field status number HTTP status code
---@field data? table Response data (present on success) - direct proto message
---@field error? ConnectError Error object (present on failure)

M.config = {
  servers = {},
  current_server = nil,
  debug_info = true,
  auto_connect_events = true,
}

local function normalize_servers(servers)
  if type(servers) ~= "table" or vim.tbl_isempty(servers) then
    error("neoweaver.api.setup: 'servers' table is required")
  end

  local normalized = {}
  local default_name = nil

  for name, value in pairs(servers) do
    if type(name) ~= "string" or name == "" then
      error("neoweaver.api.setup: server names must be non-empty strings")
    end

    local url
    local is_default = false

    if type(value) == "string" then
      url = value
    elseif type(value) == "table" then
      url = value.url
      is_default = value.default == true
    else
      error(string.format("neoweaver.api.setup: invalid configuration for server '%s'", name))
    end

    if type(url) ~= "string" or url == "" then
      error(string.format("neoweaver.api.setup: server '%s' must provide a non-empty url", name))
    end

    normalized[name] = { url = url }

    if is_default and not default_name then
      default_name = name
    end
  end

  return normalized, default_name
end

function M.setup(opts)
  opts = opts or {}

  if opts.debug_info ~= nil then
    M.config.debug_info = opts.debug_info
  end

  if opts.auto_connect_events ~= nil then
    M.config.auto_connect_events = opts.auto_connect_events
  end

  if opts.servers then
    local normalized, default_name = normalize_servers(opts.servers)
    M.config.servers = normalized
    M.config.current_server = default_name
  else
    M.config.servers = {}
    M.config.current_server = nil
  end

  if vim.tbl_isempty(M.config.servers) then
    error("neoweaver.api.setup: at least one server must be configured")
  end

  if M.config.debug_info then
    local msg = "Neoweaver API configured"
    if M.config.current_server then
      msg = msg .. " (default: " .. M.config.current_server .. ")"
    else
      msg = msg .. " (no default server)"
    end
    vim.notify(msg, vim.log.levels.INFO)
  end
end

function M.get_current_server_url()
  local name = M.config.current_server
  if not name or name == "" then
    error("neoweaver.api: no server selected. Use :MwServerUse <name> or set a default server.")
  end

  local entry = M.config.servers[name]
  if not entry then
    error(string.format("neoweaver.api: server '%s' is not configured", name))
  end

  return entry.url
end

function M.set_current_server(name)
  if not name or name == "" then
    error("MwServerUse: server name is required")
  end

  if not M.config.servers[name] then
    error(string.format("MwServerUse: server '%s' is not configured", name))
  end

  M.config.current_server = name

  if M.config.debug_info then
    vim.notify("Neoweaver server set to '" .. name .. "'", vim.log.levels.INFO)
  end
end

function M.list_server_names()
  local names = {}
  for name, _ in pairs(M.config.servers) do
    if type(name) == "string" then
      table.insert(names, name)
    end
  end
  table.sort(names)
  return names
end

function M.toggle_debug()
  M.config.debug_info = not M.config.debug_info
  vim.notify("Debug logging: " .. (M.config.debug_info and "ON" or "OFF"), vim.log.levels.INFO)
end

return M
