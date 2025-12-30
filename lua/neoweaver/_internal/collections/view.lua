---
--- collections/view.lua - ViewSource implementation for collections domain
---
--- PURPOSE:
--- Implements the ViewSource interface for the collections domain.
--- This file contains all domain-specific logic for displaying collections/notes
--- in the picker, previously scattered across explorer/init.lua and explorer/tree.lua.
---
--- IMPLEMENTS ViewSource:
--- - name: "collections"
--- - load_data: Fetches collections tree from backend, converts to NuiTree.Node[]
--- - prepare_node: Renders collection/note nodes with proper icons, indentation
--- - actions: CRUD handlers (select opens note, create/rename/delete collection)
--- - get_stats: Returns { collections: N, notes: M } for statusline
---
--- DOMAIN KNOWLEDGE:
--- - Knows about collection/note node types
--- - Knows about is_default, is_system, collection_id, note_id properties
--- - Knows how to render "(default)" suffix, icons, etc.
---
--- REFERENCE:
--- See _refactor_ref/explorer/tree.lua for original prepare_node logic
--- See _refactor_ref/explorer/init.lua for original action handlers
--- See _refactor_ref/collections.lua for original build_tree_nodes
---

local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")

local M = {}

--- Build tree nodes from collections data
--- TODO: Move logic from collections.build_tree_nodes
---@param callback fun(nodes: NuiTree.Node[], stats: ViewStats)
local function load_data(callback)
  -- TODO: Fetch from backend, convert to NuiTree.Node[]
  -- For now, return empty
  callback({}, { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } })
end

--- Render a node for display
--- TODO: Move logic from explorer/tree.lua
---@param node NuiTree.Node
---@param parent NuiTree.Node|nil
---@return NuiLine[]
local function prepare_node(node, parent)
  -- TODO: Implement domain-specific rendering
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))
  line:append(node.text or node.name or "???")
  return { line }
end

--- Get stats for statusline
---@return ViewStats
local function get_stats()
  -- TODO: Track actual counts
  return { items = { { label = "Collections", count = 0 }, { label = "Notes", count = 0 } } }
end

---@type ViewSource
M.source = {
  name = "collections",
  load_data = load_data,
  prepare_node = prepare_node,
  get_stats = get_stats,
  actions = {
    --- Open note or toggle collection
    ---@param node NuiTree.Node
    select = function(node)
      -- TODO: If note, open buffer. If collection, toggle expand.
    end,

    --- Create new collection
    create = function()
      -- TODO: Prompt for name, call backend
    end,

    --- Rename collection
    ---@param node NuiTree.Node
    rename = function(node)
      -- TODO: Prompt for new name, call backend
    end,

    --- Delete collection
    ---@param node NuiTree.Node
    delete = function(node)
      -- TODO: Confirm, call backend
    end,
  },
}

return M
