--- Internal event bus for component coordination
--- Handles both SSE events (from server) and local events (between components)

local M = {}

--- Event domain types
M.types = {
  -- SSE events (from server)
  NOTE = "note",
  COLLECTION = "collection",
  TAG = "tag",
  SYSTEM = "system",
}

--- Reserved origin for SSE events (bypasses origin filtering)
local SSE_ORIGIN = "sse"

---@class EventSubscriber
---@field fn fun(event: table)
---@field origin string|nil

---@type table<string, EventSubscriber[]>
local subscribers = {}

--- Subscribe to domain events
---@param domains string|string[] Event domains to subscribe to
---@param callback fun(event: table) Called when event is dispatched
---@param opts? { origin?: string } Origin identifier for filtering (e.g., "buffer", "collections")
---@return fun() unsubscribe Cleanup function
function M.on(domains, callback, opts)
  if type(domains) == "string" then
    domains = { domains }
  end

  opts = opts or {}
  local subscriber = { fn = callback, origin = opts.origin }

  for _, domain in ipairs(domains) do
    if not subscribers[domain] then
      subscribers[domain] = {}
    end
    table.insert(subscribers[domain], subscriber)
  end

  return function()
    for _, domain in ipairs(domains) do
      local subs = subscribers[domain]
      if subs then
        for i, sub in ipairs(subs) do
          if sub == subscriber then
            table.remove(subs, i)
            break
          end
        end
      end
    end
  end
end

--- Dispatch event to subscribers
---@param event table Event with type, data, and optional origin
local function dispatch(event)
  local domain = event.type
  if not domain then
    return
  end

  local subs = subscribers[domain]
  if not subs then
    return
  end

  local event_origin = event.origin

  for _, subscriber in ipairs(subs) do
    -- Skip if origins match (unless SSE origin, which goes to everyone)
    local should_skip = event_origin
      and event_origin ~= SSE_ORIGIN
      and subscriber.origin
      and subscriber.origin == event_origin

    if not should_skip then
      local ok, err = pcall(subscriber.fn, event)
      if not ok then
        vim.notify("Event subscriber error: " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end
end

--- Emit a local event (with origin filtering)
---@param event_type string Domain type (e.g., "note", "collection")
---@param data table Event data (action, entity details)
---@param opts { origin: string } Source component identifier
function M.emit(event_type, data, opts)
  if not opts or not opts.origin then
    vim.notify("events.emit: origin is required", vim.log.levels.WARN)
    return
  end

  dispatch({
    type = event_type,
    data = data,
    origin = opts.origin,
  })
end

--- Dispatch SSE event from server (no origin filtering)
--- Called by api.lua when SSE event arrives (already filtered by session_id)
---@param event table Raw SSE event { event = string, data = table }
function M.dispatch_sse(event)
  dispatch({
    type = event.event,
    data = event.data,
    origin = SSE_ORIGIN,
  })
end

return M
