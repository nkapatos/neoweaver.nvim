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
  -- TODO: Create NuiTree with source.prepare_node
  -- TODO: Bind keymaps from config, delegating to source.actions
end

--- Load data from the source and render
function Picker:load()
  -- TODO: Call source.load_data, then tree:set_nodes and tree:render
end

--- Get the currently selected node
---@return NuiTree.Node|nil
function Picker:get_node()
  -- TODO: Return tree:get_node()
  return nil
end

--- Refresh the tree (reload data)
function Picker:refresh()
  -- TODO: Reload data and re-render
end

return M
