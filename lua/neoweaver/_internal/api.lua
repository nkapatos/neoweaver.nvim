local M = {}
local curl = require("plenary.curl")

-- SSE connection state
local sse_state = {
  job = nil, -- plenary job handle
  buffer = "", -- incomplete chunk buffer
  last_event_id = nil, -- for reconnection support
  last_heartbeat = nil, -- timestamp of last heartbeat (for future health monitoring)
  status = "disconnected", -- "disconnected" | "connecting" | "connected"
  session_id = nil, -- assigned by server on SSE connect, used to filter self-originated events
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
  debug_info = true, -- Can be toggled independently with :MwToggleDebug
  auto_connect_events = true, -- Auto-connect to SSE on first successful API call
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

---Centralized API request handler for Connect RPC
---Connect RPC returns the proto message directly (no {"data": ...} wrapper for success)
---Errors are returned as {"code": "...", "message": "...", "details": [...]}
---@param method string Semantic HTTP method ("GET", "POST", "PUT", "DELETE") - all become POST
---@param endpoint string Connect RPC endpoint (e.g., "/mind.v3.NotesService/GetNote")
---@param opts table Request options (body, headers)
---@param cb fun(res: ApiResponse) Callback function
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
--- SSE format:
---   id: 42
---   event: note
---   data: {"type":"updated","entity_id":123,"ts":1735748041321}
---   <blank line>
---@param buffer string The accumulated buffer
---@return table[] events Array of parsed events {id, event, data}
---@return string remaining Unparsed data (incomplete event)
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

  -- Inject session ID header if available (for SSE self-event filtering)
  if sse_state.session_id then
    opts.headers = opts.headers or {}
    opts.headers["X-Session-Id"] = sse_state.session_id
  end

  if M.config.debug_info then
    vim.notify("API Request: " .. method:upper() .. " " .. url, vim.log.levels.DEBUG)
  end

  opts.callback = function(res)
    vim.schedule(function()
      -- Try to decode the response body
      local ok, res_body = pcall(vim.json.decode, res.body)

      -- JSON Decoding has failed
      if not ok then
        cb({
          status = res.status,
          error = { code = "parse_error", message = "JSON Decode error: " .. tostring(res_body) },
        })
        return
      end

      if res.status >= 200 and res.status < 300 then
        -- Success: Connect RPC returns proto message directly (not wrapped in {"data": ...})
        cb({
          status = res.status,
          data = res_body,
        })

        -- Auto-connect to SSE events on first successful API call
        if M.config.auto_connect_events and sse_state.status == "disconnected" then
          M.events.connect()
        end
      else
        -- Error: Connect RPC format {"code": "...", "message": "...", "details": [...]}
        local err = res_body or { code = "unknown", message = "unknown error" }
        cb({
          status = res.status,
          error = err,
        })
      end
    end)
  end

  -- Connect RPC always uses POST regardless of semantic method
  -- We keep the method parameter for developer clarity (GET/PUT/DELETE semantics)
  -- but all requests are actually POST under the hood
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

-- Notes Service
---@type NotesMethods
M.notes = {
  -- POST /mind.v3.NotesService/ListNotes
  -- Request: mind.v3.ListNotesRequest
  -- Response: mind.v3.ListNotesResponse
  list = function(req, cb)
    request("GET", "/mind.v3.NotesService/ListNotes", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.NotesService/GetNote
  -- Request: mind.v3.GetNoteRequest
  -- Response: mind.v3.Note
  get = function(req, cb)
    request("GET", "/mind.v3.NotesService/GetNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.NotesService/CreateNote
  -- Request: mind.v3.CreateNoteRequest
  -- Response: mind.v3.Note
  create = function(req, cb)
    request("POST", "/mind.v3.NotesService/CreateNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.NotesService/NewNote
  -- Request: mind.v3.NewNoteRequest
  -- Response: mind.v3.Note
  new = function(req, cb)
    request("POST", "/mind.v3.NotesService/NewNote", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.NotesService/FindNotes
  -- Request: mind.v3.FindNotesRequest
  -- Response: mind.v3.FindNotesResponse
  find = function(req, cb)
    request("POST", "/mind.v3.NotesService/FindNotes", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.NotesService/ReplaceNote
  -- Request: mind.v3.ReplaceNoteRequest
  -- Response: mind.v3.Note
  -- Requires If-Match header with etag for optimistic locking
  update = function(req, etag, cb)
    request("PUT", "/mind.v3.NotesService/ReplaceNote", {
      body = vim.json.encode(req),
      headers = {
        ["Content-Type"] = "application/json",
        ["If-Match"] = etag or "*",
      },
    }, cb)
  end,

  -- POST /mind.v3.NotesService/UpdateNote
  -- Request: mind.v3.UpdateNoteRequest (partial update with field masking)
  -- Response: mind.v3.Note
  -- Requires If-Match header with etag for optimistic locking
  patch = function(req, etag, cb)
    request("POST", "/mind.v3.NotesService/UpdateNote", {
      body = vim.json.encode(req),
      headers = {
        ["Content-Type"] = "application/json",
        ["If-Match"] = etag,
      },
    }, cb)
  end,

  -- POST /mind.v3.NotesService/DeleteNote
  -- Request: mind.v3.DeleteNoteRequest
  -- Response: google.protobuf.Empty
  delete = function(req, cb)
    request("DELETE", "/mind.v3.NotesService/DeleteNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,
}

-- Helper function to list notes by collection ID
-- Uses collectionId field in ListNotesRequest
---@param collection_id number The collection ID
---@param query? table Optional additional query parameters (pageSize, pageToken, etc.)
---@param cb fun(res: ApiResponse) Callback function
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

-- Collections Service
---@type CollectionsMethods
M.collections = {
  -- POST /mind.v3.CollectionsService/ListCollections
  -- Request: mind.v3.ListCollectionsRequest
  -- Response: mind.v3.ListCollectionsResponse (contains collections array and totalSize)
  list = function(req, cb)
    request("GET", "/mind.v3.CollectionsService/ListCollections", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.CollectionsService/GetCollection
  -- Request: mind.v3.GetCollectionRequest
  -- Response: mind.v3.Collection
  get = function(req, cb)
    request("GET", "/mind.v3.CollectionsService/GetCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.CollectionsService/CreateCollection
  -- Request: mind.v3.CreateCollectionRequest
  -- Response: mind.v3.Collection
  create = function(req, cb)
    request("POST", "/mind.v3.CollectionsService/CreateCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.CollectionsService/UpdateCollection
  -- Request: mind.v3.UpdateCollectionRequest
  -- Response: mind.v3.Collection
  update = function(req, cb)
    request("PUT", "/mind.v3.CollectionsService/UpdateCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  -- POST /mind.v3.CollectionsService/DeleteCollection
  -- Request: mind.v3.DeleteCollectionRequest
  -- Response: google.protobuf.Empty
  delete = function(req, cb)
    request("DELETE", "/mind.v3.CollectionsService/DeleteCollection", {
      body = vim.json.encode(req),
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

-- SSE Events API
M.events = {}

-- Event type constants for type safety
M.events.types = {
  NOTE = "note",
  COLLECTION = "collection",
  SYSTEM = "system",
}

-- Subscriber registry: { [domain]: { callback, ... } }
local event_subscribers = {}

--- Subscribe to domain events
--- Returns an unsubscribe function that MUST be called on cleanup to prevent memory leaks.
--- Store the returned function and call it when the subscriber is torn down (e.g., buffer close).
---
--- @param domains string|string[] Domain type(s) to listen for (use api.events.types.*)
--- @param callback fun(event: SSEEvent) Called when matching event received
--- @return fun() unsubscribe Call to remove subscription
function M.events.on(domains, callback)
  -- Normalize to array
  if type(domains) == "string" then
    domains = { domains }
  end

  -- Register callback for each domain
  for _, domain in ipairs(domains) do
    if not event_subscribers[domain] then
      event_subscribers[domain] = {}
    end
    table.insert(event_subscribers[domain], callback)
  end

  -- Return unsubscribe function
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

--- Dispatch event to all subscribers for the event's domain
--- Skips events that originated from this session (self-event filtering)
--- @param event table Parsed SSE event { event = "domain", data = {...}, id = "..." }
local function dispatch_event(event)
  local domain = event.event
  if not domain then
    return
  end

  -- Skip events originated from this session
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

  -- TODO: Consider debouncing refresh calls if multiple events arrive rapidly
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
    -- Disable curl's output buffering so SSE events are delivered immediately.
    -- Without -N, curl buffers output and the stream callback never fires.
    raw = { "-N" },
    -- NOTE: plenary.curl's stream callback receives data line-by-line with newlines stripped.
    -- SSE spec uses "\n\n" as event separator, so we must reconstruct newlines when buffering.
    -- See plenary/job.lua on_output() which splits on "\n" before invoking callbacks.
    stream = function(_, line)
      if line == nil then
        return
      end

      vim.schedule(function()
        local ok, cb_err = pcall(function()
          -- First line means we're connected
          if sse_state.status == "connecting" then
            sse_state.status = "connected"
            if M.config.debug_info then
              vim.notify("SSE: Connected", vim.log.levels.INFO)
            end
          end

          -- Accumulate lines and reconstruct newlines (stripped by plenary)
          sse_state.buffer = sse_state.buffer .. line .. "\n"
          local events, remaining = parse_sse_events(sse_state.buffer)
          sse_state.buffer = remaining

          -- Process parsed events
          for _, event in ipairs(events) do
            if event.id then
              sse_state.last_event_id = event.id
            end

            -- Handle system events
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

            -- Log events when debug is enabled
            if M.config.debug_info then
              vim.notify(
                string.format("SSE Event: %s - %s", event.event or "unknown", vim.inspect(event.data)),
                vim.log.levels.DEBUG
              )
            end

            -- Dispatch to subscribers
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

--- Get current SSE connection status
---@return string status "disconnected" | "connecting" | "connected"
function M.events.status()
  return sse_state.status
end

return M
