---
--- picker/init.lua - Generic tree picker component
---
--- PURPOSE:
--- Domain-agnostic picker that displays hierarchical data using NuiTree.
--- Receives a ViewSource (data + rendering + actions) and a PickerConfig (keymaps).
--- Can be hosted in a sidebar (explorer) or floating window.
---
--- RESPONSIBILITIES:
--- - Create and manage NuiTree instance
--- - Bind keymaps based on PickerConfig
--- - Delegate actions to ViewSource.actions
--- - Handle tree navigation (expand/collapse, cursor movement)
--- - Trigger data loading via ViewSource.load_data
---
--- DOES NOT:
--- - Know about specific domains (collections, tags, etc.)
--- - Create windows (host's responsibility)
--- - Define what actions mean (ViewSource's responsibility)
---
--- USAGE:
--- local picker = require("neoweaver._internal.picker")
--- local my_picker = picker.new(view_source, config)
--- my_picker:mount(bufnr)
--- my_picker:load()
---
--- REFERENCE:
--- See _refactor_ref/explorer/ and _refactor_ref/picker/ for original implementation
---

local NuiTree = require("nui.tree")

local M = {}

---@class Picker
---@field source ViewSource
---@field config PickerConfig
---@field tree NuiTree|nil
---@field bufnr number|nil
local Picker = {}
Picker.__index = Picker

--- Create a new picker instance
---@param source ViewSource The view source providing data and actions
---@param config PickerConfig The configuration for keymaps
---@return Picker
function M.new(source, config)
  local self = setmetatable({}, Picker)
  self.source = source
  self.config = config
  self.tree = nil
  self.bufnr = nil
  return self
end

--- Mount the picker to a buffer
---@param bufnr number Buffer number to render into
function Picker:mount(bufnr)
  self.bufnr = bufnr

  -- Create NuiTree with source's prepare_node for rendering
  self.tree = NuiTree({
    bufnr = bufnr,
    prepare_node = self.source.prepare_node,
    nodes = {}, -- Start empty, load() will populate
  })

  -- Bind keymaps from config, delegating to source.actions
  self:_bind_keymaps()

  -- Bind navigation keymaps (always present)
  self:_bind_navigation()
end

--- Bind action keymaps from config
function Picker:_bind_keymaps()
  local opts = { noremap = true, nowait = true, buffer = self.bufnr }

  for key, action_name in pairs(self.config.keymaps) do
    if action_name == "close" then
      -- Special case: close is handled by host (explorer), not source
      -- Skip for now, explorer will handle this
    elseif self.source.actions[action_name] then
      vim.keymap.set("n", key, function()
        local node = self:get_node()
        self.source.actions[action_name](node)
      end, opts)
    end
  end
end

--- Bind navigation keymaps (expand/collapse, movement)
function Picker:_bind_navigation()
  local opts = { noremap = true, nowait = true, buffer = self.bufnr }

  -- Expand/collapse on enter (if node has children and select action not bound)
  -- Movement is handled by normal vim j/k

  -- Toggle expand/collapse
  vim.keymap.set("n", "l", function()
    local node = self:get_node()
    if node and node:has_children() then
      if node:is_expanded() then
        node:collapse()
      else
        node:expand()
      end
      self.tree:render()
    end
  end, opts)

  vim.keymap.set("n", "h", function()
    local node = self:get_node()
    if node and node:is_expanded() then
      node:collapse()
      self.tree:render()
    end
  end, opts)
end

--- Load data from the source and render
function Picker:load()
  self.source.load_data(function(nodes, stats)
    if self.tree then
      self.tree:set_nodes(nodes)
      self.tree:render()
    end
  end)
end

--- Get the currently selected node
---@return NuiTree.Node|nil
function Picker:get_node()
  if not self.tree then
    return nil
  end
  return self.tree:get_node()
end

--- Refresh the tree (reload data)
function Picker:refresh()
  self:load()
end

return M
