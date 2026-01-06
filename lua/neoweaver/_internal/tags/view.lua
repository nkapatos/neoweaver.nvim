--- ViewSource for tags (read-only)

local NuiTree = require("nui.tree")
local NuiLine = require("nui.line")
local manager = require("neoweaver._internal.picker.manager")
local tags = require("neoweaver._internal.tags")
local api = require("neoweaver._internal.api")

local M = {}

local cached_stats = { items = { { label = "Tags", count = 0 } } }

local function empty_stats()
  return { items = { { label = "Tags", count = 0 } } }
end

local function load_data(callback)
  tags.list_tags({}, function(tags_list, err)
    if err then
      vim.notify("Failed to load tags: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      callback({}, empty_stats())
      return
    end

    local nodes = {}
    for _, tag in ipairs(tags_list) do
      table.insert(
        nodes,
        NuiTree.Node({
          id = "tag:" .. tag.id,
          type = "tag",
          name = tag.displayName,
          tag_id = tag.id,
          icon = "",
          highlight = "Special",
        })
      )
    end

    cached_stats = { items = { { label = "Tags", count = #tags_list } } }
    callback(nodes, cached_stats)
  end)
end

local function prepare_node(node, _parent)
  local line = NuiLine()

  local indent = string.rep("  ", node:get_depth() - 1)
  line:append(indent)
  line:append("  ")

  if node.icon then
    line:append(node.icon .. " ", node.highlight or "Normal")
  end

  line:append(node.name, node.highlight or "Normal")

  return { line }
end

local function get_stats()
  return cached_stats
end

---@type ViewSource
M.source = {
  name = "tags",
  event_types = { api.events.types.TAG },
  load_data = load_data,
  prepare_node = prepare_node,
  get_stats = get_stats,
  actions = {
    select = function(node)
      local msg = ("Selected tag: %s (id: %s)"):format(node.name or "???", node.tag_id or "?")
      vim.notify(msg, vim.log.levels.INFO)
    end,
  },
}

manager.register_source("tags", M.source)

return M
