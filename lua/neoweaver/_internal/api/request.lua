local curl = require("plenary.curl")
local config = require("neoweaver._internal.api.config")
local sse = require("neoweaver._internal.api.sse")
local M = {}

---@param method string HTTP method (semantic only - all requests use POST)
---@param endpoint string Connect RPC endpoint
---@param opts table Request options
---@param cb fun(res: ApiResponse)
function M.request(method, endpoint, opts, cb)
  local base_url = config.get_current_server_url()
  local url = base_url .. endpoint
  opts = opts or {}

  local session_id = sse.get_session_id()
  if session_id then
    opts.headers = opts.headers or {}
    opts.headers["X-Session-Id"] = session_id
  end

  if config.config.debug_info then
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

        if config.config.auto_connect_events and sse.status() == "disconnected" then
          sse.connect()
        end
      else
        cb({ status = res.status, error = res_body or { code = "unknown", message = "unknown error" } })
      end
    end)
  end

  local curl_fn = curl.post

  if config.config.debug_info then
    vim.notify("Request opts: " .. vim.inspect(opts), vim.log.levels.DEBUG)
  end

  curl_fn(url, opts)
end

return M
