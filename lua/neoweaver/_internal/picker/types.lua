---
--- picker/types.lua - LuaLS type definitions for the picker system
---
--- PURPOSE:
--- Defines the ViewSource interface that domains must implement to provide
--- data to the picker. Also defines PickerConfig for host-specific keymaps.
---
--- ARCHITECTURE:
--- - ViewSource is the contract between domains (collections, tags) and the picker
--- - Domains implement ViewSource to provide: data loading, rendering, actions
--- - Picker consumes ViewSource + PickerConfig to display and handle interactions
---
--- NO RUNTIME VALIDATION - these are LuaLS annotations only for static analysis.
---

---@class ViewSource
---@field name string Unique identifier for this view (e.g., "collections", "tags")
---@field load_data fun(callback: fun(nodes: NuiTree.Node[], stats: ViewStats)) Async data loader
---@field prepare_node fun(node: NuiTree.Node, parent?: NuiTree.Node): NuiLine[] Renders node for display
---@field actions ViewActions Table of action handlers
---@field get_stats fun(): ViewStats Returns stats for statusline
---@field poll_interval? number Optional polling interval in ms (domain-specific, nil = no polling)

---@class ViewActions
---@field select? fun(node: NuiTree.Node) Called when node is selected (<CR>)
---@field create? fun() Called to create new item
---@field rename? fun(node: NuiTree.Node) Called to rename item
---@field delete? fun(node: NuiTree.Node) Called to delete item

---@class ViewStats
---@field items ViewStatItem[] Array of stat items for statusline

---@class ViewStatItem
---@field label string Display label (e.g., "Collections", "Notes", "Tags")
---@field count number Count to display

---@class PickerConfig
---@field keymaps table<string, string> Map of key -> action name (e.g., ["d"] = "delete")

return {}
