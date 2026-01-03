--- picker/types.lua - Type definitions for ViewSource and PickerConfig

---@class ViewSource
---@field name string
---@field load_data fun(callback: fun(nodes: NuiTree.Node[], stats: ViewStats))
---@field prepare_node fun(node: NuiTree.Node, parent?: NuiTree.Node): NuiLine[]
---@field actions ViewActions
---@field get_stats fun(): ViewStats
---@field event_types? string[]
---@field idle_timeout? number
---@field poll_interval? number

---@class ViewActions
---@field select? fun(node: NuiTree.Node, refresh_cb: fun())
---@field create? fun(node: NuiTree.Node, refresh_cb: fun())
---@field rename? fun(node: NuiTree.Node, refresh_cb: fun())
---@field delete? fun(node: NuiTree.Node, refresh_cb: fun())

---@class ViewStats
---@field items ViewStatItem[]

---@class ViewStatItem
---@field label string
---@field count number

---@class PickerConfig
---@field keymaps table<string, string>

return {}
