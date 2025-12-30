---
--- explorer/init.lua - Sidebar host for the picker
---
--- PURPOSE:
--- Thin coordinator that creates a sidebar window and hosts a picker instance.
--- Does NOT know about specific domains (collections, tags, etc.).
---
--- RESPONSIBILITIES:
--- - Create/manage the sidebar window (split)
--- - Instantiate picker with a ViewSource and explorer config
--- - Handle window lifecycle (open, close, toggle)
--- - Delegate view switching (collections view, tags view, etc.)
---
--- DOES NOT:
--- - Know how to render domain-specific nodes (picker + ViewSource do that)
--- - Know about CRUD logic (ViewSource.actions handles that)
--- - Hardcode domain-specific properties or types
---
--- USAGE:
--- local explorer = require("neoweaver._internal.explorer")
--- explorer.open("collections")  -- Open with collections view
--- explorer.open("tags")         -- Open with tags view
--- explorer.toggle()             -- Toggle visibility
---
--- REFERENCE:
--- See _refactor_ref/explorer/init.lua for original implementation
--- See _refactor_ref/explorer/window.lua for window management
---

local picker = require("neoweaver._internal.picker")
local configs = require("neoweaver._internal.picker.configs")

local M = {}

--- Registered view sources
---@type table<string, ViewSource>
local views = {}

--- Current state
local state = {
  ---@type Picker|nil
  picker_instance = nil,
  ---@type string|nil
  current_view = nil,
  ---@type number|nil
  bufnr = nil,
  ---@type number|nil
  winid = nil,
}

--- Register a view source
--- Called by domain modules to make their view available
---@param name string View name (e.g., "collections", "tags")
---@param source ViewSource The view source implementation
function M.register_view(name, source)
  views[name] = source
end

--- Open the explorer with a specific view
---@param view_name string Name of the view to display
function M.open(view_name)
  local source = views[view_name]
  if not source then
    vim.notify("Unknown view: " .. view_name, vim.log.levels.ERROR)
    return
  end

  -- TODO: Create window if not exists
  -- TODO: Create picker instance with source and explorer config
  -- TODO: Mount picker to buffer
  -- TODO: Load data

  state.current_view = view_name
end

--- Close the explorer
function M.close()
  -- TODO: Close window, cleanup
end

--- Toggle explorer visibility
function M.toggle()
  -- TODO: If open, close. If closed, open with last view.
end

--- Switch to a different view
---@param view_name string
function M.switch_view(view_name)
  -- TODO: Switch picker source, reload
end

--- Get the current picker instance (for external access)
---@return Picker|nil
function M.get_picker()
  return state.picker_instance
end

return M
