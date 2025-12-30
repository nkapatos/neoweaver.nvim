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

local Split = require("nui.split")
local picker_mod = require("neoweaver._internal.picker")
local configs = require("neoweaver._internal.picker.configs")

local M = {}

-- TODO: Make DEFAULT_VIEW configurable via user config and/or persist last used view
local DEFAULT_VIEW = "collections"

--- Registered view sources
---@type table<string, ViewSource>
local views = {}

--- Current state
local state = {
  ---@type Picker|nil
  picker_instance = nil,
  ---@type string|nil
  current_view = nil,
  ---@type NuiSplit|nil
  split = nil,
  ---@type boolean
  is_open = false,
}

--- Default window config
local window_config = {
  position = "left",
  size = 30,
}

--- Register a view source
--- Called by domain modules to make their view available
---@param name string View name (e.g., "collections", "tags")
---@param source ViewSource The view source implementation
function M.register_view(name, source)
  views[name] = source
end

--- Create the sidebar split window
---@return NuiSplit|nil
local function create_split()
  local split = Split({
    relative = "editor",
    position = window_config.position,
    size = window_config.size,
    buf_options = {
      buftype = "nofile",
      swapfile = false,
      filetype = "neoweaver_explorer",
    },
    win_options = {
      number = false,
      relativenumber = false,
      cursorline = true,
      signcolumn = "no",
      wrap = false,
    },
  })

  split:mount()

  -- Close on q
  split:map("n", "q", function()
    M.close()
  end, { noremap = true })

  return split
end

--- Open the explorer with a specific view
---@param view_name? string Name of the view to display (defaults to DEFAULT_VIEW)
function M.open(view_name)
  view_name = view_name or DEFAULT_VIEW

  local source = views[view_name]
  if not source then
    vim.notify("Unknown view: " .. view_name, vim.log.levels.ERROR)
    return
  end

  -- Create split if not exists
  if not state.is_open or not state.split then
    state.split = create_split()
    state.is_open = true
  end

  -- Create picker instance with source and explorer config
  state.picker_instance = picker_mod.new(source, configs.explorer)

  -- Mount picker to buffer
  state.picker_instance:mount(state.split.bufnr)

  -- Load data
  state.picker_instance:load()

  state.current_view = view_name
end

--- Close the explorer
function M.close()
  if state.split then
    state.split:unmount()
    state.split = nil
  end
  state.picker_instance = nil
  state.is_open = false
end

--- Toggle explorer visibility
---@param view_name? string View to open with (defaults to last view or DEFAULT_VIEW)
function M.toggle(view_name)
  if state.is_open then
    M.close()
  else
    M.open(view_name or state.current_view or DEFAULT_VIEW)
  end
end

--- Switch to a different view
---@param view_name string
function M.switch_view(view_name)
  if not state.is_open then
    M.open(view_name)
    return
  end

  local source = views[view_name]
  if not source then
    vim.notify("Unknown view: " .. view_name, vim.log.levels.ERROR)
    return
  end

  -- Create new picker with new source
  state.picker_instance = picker_mod.new(source, configs.explorer)
  state.picker_instance:mount(state.split.bufnr)
  state.picker_instance:load()
  state.current_view = view_name
end

--- Get the current picker instance (for external access)
---@return Picker|nil
function M.get_picker()
  return state.picker_instance
end

--- Check if explorer is open
---@return boolean
function M.is_open()
  return state.is_open
end

return M
