local events = require("neoweaver._internal.events")
local curl = require("plenary.curl")
local config = require("neoweaver._internal.api.config")

local M = {}

local sse_state = {
  job = nil,
  buffer = "",
  last_event_id = nil,
  last_heartbeat = nil,
  status = "disconnected", ---@type "disconnected"|"connecting"|"connected"
  session_id = nil,
}

--- Parse SSE events from buffered data
---@param buffer string
---@return table[] parsed_events
---@return string remaining
local function parse_sse_events(buffer)
  local parsed_events = {}
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
      table.insert(parsed_events, event)
    end
  end

  return parsed_events, remaining
end

--- Connect to the SSE event stream
function M.connect()
  if sse_state.status ~= "disconnected" then
    vim.notify("SSE: Already " .. sse_state.status, vim.log.levels.WARN)
    return
  end

  local base_url = config.get_current_server_url()
  local url = base_url .. "/events/stream"

  sse_state.status = "connecting"
  sse_state.buffer = ""

  if config.config.debug_info then
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
            if config.config.debug_info then
              vim.notify("SSE: Connected", vim.log.levels.INFO)
            end
          end

          sse_state.buffer = sse_state.buffer .. line .. "\n"
          local parsed_events, remaining = parse_sse_events(sse_state.buffer)
          sse_state.buffer = remaining

          for _, event in ipairs(parsed_events) do
            if event.id then
              sse_state.last_event_id = event.id
            end

            if event.event == "system" and event.data then
              if event.data.type == "connected" and event.data.session_id then
                sse_state.session_id = event.data.session_id
                if config.config.debug_info then
                  vim.notify("SSE: Session ID: " .. sse_state.session_id, vim.log.levels.DEBUG)
                end
              elseif event.data.type == "heartbeat" then
                sse_state.last_heartbeat = vim.uv.now()
              end
            end

            -- Skip self-originated events (session_id filtering)
            if event.data and event.data.origin_session_id and event.data.origin_session_id == sse_state.session_id then
              if config.config.debug_info then
                vim.notify("SSE: Skipping self-originated event: " .. (event.event or "unknown"), vim.log.levels.DEBUG)
              end
            else
              if config.config.debug_info then
                vim.notify(
                  string.format("SSE Event: %s - %s", event.event or "unknown", vim.inspect(event.data)),
                  vim.log.levels.DEBUG
                )
              end

              events.dispatch_sse(event)
            end
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
  if config.config.debug_info then
    vim.notify("SSE: Job created - " .. type(result), vim.log.levels.DEBUG)
  end
end

--- Disconnect from the SSE event stream
function M.disconnect()
  if sse_state.job then
    sse_state.job:shutdown()
    sse_state.job = nil
  end
  sse_state.status = "disconnected"
  sse_state.buffer = ""
  sse_state.session_id = nil

  if config.config.debug_info then
    vim.notify("SSE: Disconnected", vim.log.levels.INFO)
  end
end

---@return "disconnected"|"connecting"|"connected"
function M.status()
  return sse_state.status
end

function M.get_session_id()
  return sse_state.session_id
end

return M
