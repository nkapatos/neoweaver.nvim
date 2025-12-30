---
--- collections/view.lua - ViewSource implementation for collections domain
---
--- PURPOSE:
--- Implements the ViewSource interface for the collections domain.
--- This file contains all domain-specific logic for displaying collections/notes
--- in the picker.
---
--- ARCHITECTURE DECISION RECORD (ADR):
---
--- This ViewSource implementation demonstrates the domain-specific responsibilities:
---
--- 1. LOAD_DATA - Fetches and transforms data:
---    - Calls collections.list_collections_with_notes() to fetch from API
---    - Builds NuiTree.Node[] hierarchy with domain properties attached:
---      - type: "server", "collection", "note"
---      - is_system: boolean (system collections can't be deleted/renamed)
---      - collection_id, note_id: for API operations
---      - icon, highlight: for rendering
---    - Wraps in server node for multi-server support
---    - Returns nodes + stats via callback
---
--- 2. PREPARE_NODE - Renders nodes using domain knowledge:
---    - Indentation based on tree depth
---    - Expand/collapse indicator (▾/▸) for nodes with children
---    - Icons based on type (server, collection, system collection, note)
---    - Highlights based on type
---    - "(default)" suffix for default items
---
--- 3. ACTIONS - CRUD operations with domain validation:
---    - select: Opens note (notes.open_note) or no-op for collections
---    - create: Creates collection under server/collection node
---    - rename: Renames collection (not allowed for system collections)
---    - delete: Deletes collection (not allowed for system collections)
---    - All actions receive (node, refresh_callback)
---    - Actions call API, then refresh_callback() on success
---
--- 4. POLL_INTERVAL - Domain decides polling frequency:
---    - Collections poll every 5 seconds (configurable)
---    - Picker manages the timer, this just provides the interval
---
--- NODE TYPES AND PROPERTIES:
---   server:     { type, name, icon, highlight, server_name, server_url, is_default }
---   collection: { type, name, icon, highlight, collection_id, is_system }
---   note:       { type, name, icon, highlight, note_id, collection_id }
---
--- REFERENCE:
--- See _refactor_ref/explorer/tree.lua for original prepare_node logic
--- See _refactor_ref/explorer/init.lua for original action handlers
--- See collections.lua for API functions (list_collections, create_collection, etc.)
---

local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local explorer = require("neoweaver._internal.explorer")

local M = {}

--- Build tree nodes from collections data
--- TODO: Implement - call collections.list_collections_with_notes(), build NuiTree.Node[]
---@param callback fun(nodes: NuiTree.Node[], stats: ViewStats)
local function load_data(callback)
  -- Stub: notify and return empty
  vim.notify("[collections/view] load_data called (stub)", vim.log.levels.INFO)
  callback({}, { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } })
end

--- Render a node for display
--- TODO: Implement - indentation, expand/collapse, icons, highlights, suffixes
---@param node NuiTree.Node
---@param parent NuiTree.Node|nil
---@return NuiLine[]
local function prepare_node(node, parent)
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))
  line:append(node.text or node.name or "???")
  return { line }
end

--- Get stats for statusline
---@return ViewStats
local function get_stats()
  return { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } }
end

---@type ViewSource
M.source = {
  name = "collections",
  poll_interval = 5000, -- 5 seconds (stub value for testing)
  load_data = load_data,
  prepare_node = prepare_node,
  get_stats = get_stats,
  actions = {
    --- Open note or no-op for collections (expand/collapse handled by picker)
    ---@param node NuiTree.Node
    ---@param refresh_cb fun()
    select = function(node, refresh_cb)
      -- TODO: Implement - if node.type == "note" then notes.open_note(node.note_id)
      vim.notify("[collections/view] select action (stub)", vim.log.levels.INFO)
    end,

    --- Create new collection under server or collection node
    ---@param node NuiTree.Node
    ---@param refresh_cb fun()
    create = function(node, refresh_cb)
      -- TODO: Implement - validate node type, prompt for name, call API, refresh_cb()
      vim.notify("[collections/view] create action (stub)", vim.log.levels.INFO)
    end,

    --- Rename collection (not allowed for system collections)
    ---@param node NuiTree.Node
    ---@param refresh_cb fun()
    rename = function(node, refresh_cb)
      -- TODO: Implement - validate not system, prompt for name, call API, refresh_cb()
      vim.notify("[collections/view] rename action (stub)", vim.log.levels.INFO)
    end,

    --- Delete collection (not allowed for system collections)
    ---@param node NuiTree.Node
    ---@param refresh_cb fun()
    delete = function(node, refresh_cb)
      -- TODO: Implement - validate not system, confirm, call API, refresh_cb()
      vim.notify("[collections/view] delete action (stub)", vim.log.levels.INFO)
    end,
  },
}

-- Self-register with explorer
explorer.register_view("collections", M.source)

return M
