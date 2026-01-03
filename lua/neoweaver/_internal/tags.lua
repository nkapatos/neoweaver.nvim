---
--- tags.lua - Tag management for Neoweaver (v3)
--- Handles tag listing (read-only)
---
local api = require("neoweaver._internal.api")

local M = {}

--- List all tags
---@param opts? { pageSize?: number, pageToken?: string }
---@param cb fun(tags: table[]|nil, error: table|nil)
function M.list_tags(opts, cb)
  opts = opts or {}

  ---@type mind.v3.ListTagsRequest
  local req = {
    pageSize = opts.pageSize or 100,
    pageToken = opts.pageToken or "",
  }

  api.tags.list(req, function(res)
    if res.error then
      cb(nil, res.error)
      return
    end

    local tags = res.data.tags or {}

    -- Normalize string IDs to numbers (protobuf int64 serializes as strings in JSON)
    for _, tag in ipairs(tags) do
      tag.id = tonumber(tag.id)
    end

    cb(tags, nil)
  end)
end

return M
