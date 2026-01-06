local M = {}
local curl = require("plenary.curl")

local sse_state = {
  job = nil,
  buffer = "",
  last_event_id = nil,
  last_heartbeat = nil,
  status = "disconnected", ---@type "disconnected"|"connecting"|"connected"
  session_id = nil,
}

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

---@param method string HTTP method (semantic only - all requests use POST)
---@param endpoint string Connect RPC endpoint
---@param opts table Request options
---@param cb fun(res: ApiResponse)
local function get_current_server_url()
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

--- Parse SSE events from buffered data
---@param buffer string
---@return table[] events
---@return string remaining
local function parse_sse_events(buffer)
  local events = {}
  local remaining = buffer

  -- SSE events are separated by double newlines
  while true do
    local event_end = remaining:find("\n\n")
    if not event_end then
      break
    end

    local event_block = remaining:sub(1, event_end - 1)
    remaining = remaining:sub(event_end + 2)

    local event = {}
    for line in event_block:gmatch("[^\n]+") do
      local field, value = line:match("^([^:]+):%s*(.*)$")
      if field and value then
        if field == "data" then
          -- Parse JSON data
          local ok, parsed = pcall(vim.json.decode, value)
          event.data = ok and parsed or value
        elseif field == "id" then
          event.id = value
        elseif field == "event" then
          event.event = value
        end
      end
    end

    if event.event or event.data then
      table.insert(events, event)
    end
  end

  return events, remaining
end

local function request(method, endpoint, opts, cb)
  local base_url = get_current_server_url()
  local url = base_url .. endpoint
  opts = opts or {}

  if sse_state.session_id then
    opts.headers = opts.headers or {}
    opts.headers["X-Session-Id"] = sse_state.session_id
  end

  if M.config.debug_info then
    vim.notify("API Request: " .. method:upper() .. " " .. url, vim.log.levels.DEBUG)
  end

  opts.callback = function(res)
    vim.schedule(function()
      local ok, res_body = pcall(vim.json.decode, res.body)

      if not ok then
        cb({
          status = res.status,
          error = { code = "parse_error", message = "JSON Decode error: " .. tostring(res_body) },
        })
        return
      end

      if res.status >= 200 and res.status < 300 then
        cb({ status = res.status, data = res_body })

        if M.config.auto_connect_events and sse_state.status == "disconnected" then
          M.events.connect()
        end
      else
        cb({ status = res.status, error = res_body or { code = "unknown", message = "unknown error" } })
      end
    end)
  end

  local curl_fn = curl.post

  if M.config.debug_info then
    vim.notify("Request opts: " .. vim.inspect(opts), vim.log.levels.DEBUG)
  end

  curl_fn(url, opts)
end

---@class NotesMethods Notes service methods
---@field list fun(req: mind.v3.ListNotesRequest, cb: fun(res: ApiResponse)) List notes
---@field get fun(req: mind.v3.GetNoteRequest, cb: fun(res: ApiResponse)) Get a note
---@field create fun(req: mind.v3.CreateNoteRequest, cb: fun(res: ApiResponse)) Create a note
---@field new fun(req: mind.v3.NewNoteRequest, cb: fun(res: ApiResponse)) Create a new note with auto-generated title
---@field find fun(req: mind.v3.FindNotesRequest, cb: fun(res: ApiResponse)) Find notes by title and filters
---@field update fun(req: mind.v3.ReplaceNoteRequest, etag: string?, cb: fun(res: ApiResponse)) Update a note
---@field delete fun(req: mind.v3.DeleteNoteRequest, cb: fun(res: ApiResponse)) Delete a note

---@type NotesMethods
M.notes = {
  list = function(req, cb)
    request("GET", "/mind.v3.NotesService/ListNotes", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  get = function(req, cb)
    request("GET", "/mind.v3.NotesService/GetNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  create = function(req, cb)
    request("POST", "/mind.v3.NotesService/CreateNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  new = function(req, cb)
    request("POST", "/mind.v3.NotesService/NewNote", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  find = function(req, cb)
    request("POST", "/mind.v3.NotesService/FindNotes", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  update = function(req, etag, cb)
    request("PUT", "/mind.v3.NotesService/ReplaceNote", {
      body = vim.json.encode(req),
      headers = {
        ["Content-Type"] = "application/json",
        ["If-Match"] = etag or "*",
      },
    }, cb)
  end,

  patch = function(req, etag, cb)
    request("POST", "/mind.v3.NotesService/UpdateNote", {
      body = vim.json.encode(req),
      headers = {
        ["Content-Type"] = "application/json",
        ["If-Match"] = etag,
      },
    }, cb)
  end,

  delete = function(req, cb)
    request("DELETE", "/mind.v3.NotesService/DeleteNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,
}

---@param collection_id number
---@param query? table
---@param cb fun(res: ApiResponse)
M.list_notes_by_collection = function(collection_id, query, cb)
  local req = vim.tbl_extend("force", query or {}, {
    collectionId = collection_id,
  })
  M.notes.list(req, cb)
end

---@class CollectionsMethods Collections service methods
---@field list fun(req: mind.v3.ListCollectionsRequest, cb: fun(res: ApiResponse)) List collections
---@field get fun(req: mind.v3.GetCollectionRequest, cb: fun(res: ApiResponse)) Get a collection
---@field create fun(req: mind.v3.CreateCollectionRequest, cb: fun(res: ApiResponse)) Create a collection
---@field update fun(req: mind.v3.UpdateCollectionRequest, cb: fun(res: ApiResponse)) Update a collection
---@field delete fun(req: mind.v3.DeleteCollectionRequest, cb: fun(res: ApiResponse)) Delete a collection

---@type CollectionsMethods
M.collections = {
  list = function(req, cb)
    request("GET", "/mind.v3.CollectionsService/ListCollections", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  get = function(req, cb)
    request("GET", "/mind.v3.CollectionsService/GetCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  create = function(req, cb)
    request("POST", "/mind.v3.CollectionsService/CreateCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  update = function(req, cb)
    request("PUT", "/mind.v3.CollectionsService/UpdateCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  delete = function(req, cb)
    request("DELETE", "/mind.v3.CollectionsService/DeleteCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,
}

---@class TagsMethods Tags service methods
---@field list fun(req: mind.v3.ListTagsRequest, cb: fun(res: ApiResponse)) List tags

---@type TagsMethods
M.tags = {
  list = function(req, cb)
    request("GET", "/mind.v3.TagsService/ListTags", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,
}

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

-- SSE Events
M.events = {}

M.events.types = {
  NOTE = "note",
  COLLECTION = "collection",
  TAG = "tag",
  SYSTEM = "system",
}

local event_subscribers = {} -- { [domain]: { callback, ... } }

--- Subscribe to domain events. Returns unsubscribe function (call on cleanup).
---@param domains string|string[]
---@param callback fun(event: table)
---@return fun() unsubscribe
function M.events.on(domains, callback)
  if type(domains) == "string" then
    domains = { domains }
  end

  for _, domain in ipairs(domains) do
    if not event_subscribers[domain] then
      event_subscribers[domain] = {}
    end
    table.insert(event_subscribers[domain], callback)
  end

  return function()
    for _, domain in ipairs(domains) do
      local subs = event_subscribers[domain]
      if subs then
        for i, cb in ipairs(subs) do
          if cb == callback then
            table.remove(subs, i)
            break
          end
        end
      end
    end
  end
end

--- Dispatch event to subscribers, skipping self-originated events
---@param event table
local function dispatch_event(event)
  local domain = event.event
  if not domain then
    return
  end

  if event.data and event.data.origin_session_id and event.data.origin_session_id == sse_state.session_id then
    if M.config.debug_info then
      vim.notify("SSE: Skipping self-originated event: " .. domain, vim.log.levels.DEBUG)
    end
    return
  end

  local subs = event_subscribers[domain]
  if not subs then
    return
  end

  for _, callback in ipairs(subs) do
    local ok, err = pcall(callback, event)
    if not ok then
      vim.notify("SSE subscriber error: " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

--- Connect to the SSE event stream
function M.events.connect()
  if sse_state.status ~= "disconnected" then
    vim.notify("SSE: Already " .. sse_state.status, vim.log.levels.WARN)
    return
  end

  local base_url = get_current_server_url()
  local url = base_url .. "/events/stream"

  sse_state.status = "connecting"
  sse_state.buffer = ""

  if M.config.debug_info then
    vim.notify("SSE: Connecting to " .. url, vim.log.levels.INFO)
  end

  local opts = {
    headers = {
      ["Accept"] = "text/event-stream",
      ["Cache-Control"] = "no-cache",
    },
    raw = { "-N" }, -- Disable curl buffering for SSE
    -- NOTE: plenary.curl strips newlines. SSE uses "\n\n" as separator, so we reconstruct.
    stream = function(_, line)
      if line == nil then
        return
      end

      vim.schedule(function()
        local ok, cb_err = pcall(function()
          if sse_state.status == "connecting" then
            sse_state.status = "connected"
            if M.config.debug_info then
              vim.notify("SSE: Connected", vim.log.levels.INFO)
            end
          end

          sse_state.buffer = sse_state.buffer .. line .. "\n"
          local events, remaining = parse_sse_events(sse_state.buffer)
          sse_state.buffer = remaining

          for _, event in ipairs(events) do
            if event.id then
              sse_state.last_event_id = event.id
            end

            if event.event == "system" and event.data then
              if event.data.type == "connected" and event.data.session_id then
                sse_state.session_id = event.data.session_id
                if M.config.debug_info then
                  vim.notify("SSE: Session ID: " .. sse_state.session_id, vim.log.levels.DEBUG)
                end
              elseif event.data.type == "heartbeat" then
                sse_state.last_heartbeat = vim.uv.now()
              end
            end

            if M.config.debug_info then
              vim.notify(
                string.format("SSE Event: %s - %s", event.event or "unknown", vim.inspect(event.data)),
                vim.log.levels.DEBUG
              )
            end

            dispatch_event(event)
          end
        end)

        if not ok then
          vim.notify("SSE callback error: " .. tostring(cb_err), vim.log.levels.ERROR)
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        sse_state.status = "disconnected"
        sse_state.job = nil
        vim.notify("SSE Error: " .. vim.inspect(err), vim.log.levels.ERROR)
      end)
    end,
  }

  local ok, result = pcall(curl.get, url, opts)
  if not ok then
    sse_state.status = "disconnected"
    vim.notify("SSE: Failed to start connection - " .. tostring(result), vim.log.levels.ERROR)
    return
  end

  sse_state.job = result
  if M.config.debug_info then
    vim.notify("SSE: Job created - " .. type(result), vim.log.levels.DEBUG)
  end
end

--- Disconnect from the SSE event stream
function M.events.disconnect()
  if sse_state.job then
    sse_state.job:shutdown()
    sse_state.job = nil
  end
  sse_state.status = "disconnected"
  sse_state.buffer = ""
  sse_state.session_id = nil

  if M.config.debug_info then
    vim.notify("SSE: Disconnected", vim.log.levels.INFO)
  end
end

---@return "disconnected"|"connecting"|"connected"
function M.events.status()
  return sse_state.status
end

M.health = {}

---@param server_name string|nil Server name (nil = current server)
---@param callback fun(result: {ok: boolean, error: string?})
function M.health.ping(server_name, callback)
  local server_url
  if server_name then
    local entry = M.config.servers[server_name]
    if not entry then
      callback({ ok = false, error = "Server not configured: " .. server_name })
      return
    end
    server_url = entry.url
  else
    local ok, url = pcall(get_current_server_url)
    if not ok then
      callback({ ok = false, error = tostring(url) })
      return
    end
    server_url = url
  end

  local url = server_url .. "/health"

  curl.get(url, {
    timeout = 2000, -- 2 seconds
    callback = function(res)
      vim.schedule(function()
        if res.status ~= 200 then
          callback({ ok = false, error = "HTTP " .. res.status })
          return
        end

        local ok, body = pcall(vim.json.decode, res.body)
        if not ok then
          callback({ ok = false, error = "Invalid JSON response" })
          return
        end

        if body.status == "healthy" then
          callback({ ok = true })
        else
          callback({ ok = false, error = "Status: " .. (body.status or "unknown") })
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        callback({ ok = false, error = tostring(err.message or err) })
      end)
    end,
  })
end

return M
