---
--- tags/view.lua - ViewSource implementation for tags domain (MOCK)
---
--- PURPOSE:
--- Implements the ViewSource interface for the tags domain.
--- Used to validate the picker/view architecture with a second domain.
---
--- THIS IS A MOCK IMPLEMENTATION:
--- - Uses hardcoded mock data (id, text only)
--- - No backend integration
--- - For testing the picker wiring and evaluating the design
---
--- IMPLEMENTS ViewSource:
--- - name: "tags"
--- - load_data: Returns mock tag nodes
--- - prepare_node: Simple text rendering
--- - actions: Stub handlers
--- - get_stats: Returns tag count
---

local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local explorer = require("neoweaver._internal.explorer")

local M = {}

--- Mock tag data
local mock_tags = {
  { id = "tag-1", text = "work" },
  { id = "tag-2", text = "personal" },
  { id = "tag-3", text = "ideas" },
  { id = "tag-4", text = "todo" },
  { id = "tag-5", text = "archive" },
}

--- Build tree nodes from mock tag data
---@param callback fun(nodes: NuiTree.Node[], stats: ViewStats)
local function load_data(callback)
  vim.notify("[tags/view] load_data called (mock)", vim.log.levels.INFO)
  local nodes = {}
  for _, tag in ipairs(mock_tags) do
    table.insert(nodes, NuiTree.Node({
      id = tag.id,
      text = tag.text,
      type = "tag",
    }))
  end
  callback(nodes, { items = { { label = "Tags", count = #mock_tags } } })
end

--- Render a tag node for display
---@param node NuiTree.Node
---@param parent NuiTree.Node|nil
---@return NuiLine[]
local function prepare_node(node, parent)
  local line = NuiLine()
  line:append(string.rep("  ", node:get_depth() - 1))
  line:append("# ", "Special")
  line:append(node.text or "???")
  return { line }
end

--- Get stats for statusline
---@return ViewStats
local function get_stats()
  return { items = { { label = "Tags", count = #mock_tags } } }
end

---@type ViewSource
M.source = {
  name = "tags",
  poll_interval = 10000, -- 10 seconds (mock, different to verify independence)
  load_data = load_data,
  prepare_node = prepare_node,
  get_stats = get_stats,
  actions = {
    --- Select tag (filter by tag)
    ---@param node NuiTree.Node
    select = function(node)
      vim.notify("[tags/view] Selected tag: " .. (node.text or "???"), vim.log.levels.INFO)
    end,

    --- Create new tag (stub)
    create = function()
      vim.notify("[tags/view] Create tag: not implemented (mock)", vim.log.levels.WARN)
    end,

    --- Rename tag (stub)
    ---@param node NuiTree.Node
    rename = function(node)
      vim.notify("[tags/view] Rename tag: not implemented (mock)", vim.log.levels.WARN)
    end,

    --- Delete tag (stub)
    ---@param node NuiTree.Node
    delete = function(node)
      vim.notify("[tags/view] Delete tag: not implemented (mock)", vim.log.levels.WARN)
    end,
  },
}

-- Self-register with explorer
explorer.register_view("tags", M.source)

return M
