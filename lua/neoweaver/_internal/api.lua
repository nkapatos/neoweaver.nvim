local config_module = require("neoweaver._internal.api.config")
local sse_module = require("neoweaver._internal.api.sse")
local services_module = require("neoweaver._internal.api.services")
local events = require("neoweaver._internal.events")

local M = {}

-- Expose config functions
M.setup = config_module.setup
M.set_current_server = config_module.set_current_server
M.list_server_names = config_module.list_server_names
M.toggle_debug = config_module.toggle_debug
M.config = config_module.config

-- Expose services
M.notes = services_module.notes
M.collections = services_module.collections
M.tags = services_module.tags
M.health = services_module.health
M.list_notes_by_collection = services_module.list_notes_by_collection

-- SSE Events - merge events module with SSE-specific methods
M.events = setmetatable({}, { __index = events })

M.events.connect = sse_module.connect
M.events.disconnect = sse_module.disconnect
M.events.status = sse_module.status

return M
