---
--- picker/init.lua - Domain-agnostic picker
---
--- Accepts items and converts them to NuiTree nodes for rendering.
---
local NuiTree = require("nui.tree")

local M = {}

---@class PickerItem
---@field id string Unique identifier
---@field text string Display text

--- Convert picker items to NuiTree.Node
---@param items PickerItem[]
---@return NuiTree.Node[]
local function build_nodes(items)
  local nodes = {}
  for _, item in ipairs(items) do
    table.insert(nodes, NuiTree.Node({
      id = item.id,
      text = item.text,
    }))
  end
  return nodes
end

--- Setup navigation keymaps on buffer
---@param bufnr number Buffer number
local function setup_keymaps(bufnr)
  local opts = { noremap = true, nowait = true, buffer = bufnr }

  vim.keymap.set("n", "j", function()
    vim.cmd("normal! j")
  end, opts)

  vim.keymap.set("n", "k", function()
    vim.cmd("normal! k")
  end, opts)
end

--- Create a picker
---@param bufnr number Buffer to render into
---@param items PickerItem[] Items to display
---@return NuiTree
function M.new(bufnr, items)
  local nodes = build_nodes(items)

  local tree = NuiTree({
    bufnr = bufnr,
    nodes = nodes,
  })

  setup_keymaps(bufnr)

  return tree
end

--- Mock data for testing
M.mock_items = {
  { id = "1", text = "First item" },
  { id = "2", text = "Second item" },
  { id = "3", text = "Third item" },
}

return M
