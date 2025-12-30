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
--- LIFECYCLE:
--- - open()/close() use show()/hide() for fast toggle (preserves buffer + tree state)
--- - mount()/unmount() for explicit full lifecycle control (creates/destroys buffer)
--- - show() internally calls mount() if not yet mounted
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
  data_loaded = false,
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

--- Create the sidebar split (does not mount)
---@return NuiSplit
local function create_split()
  return Split({
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
end

--- Setup keymaps on the split buffer
---@param split NuiSplit
local function setup_keymaps(split)
  -- Close on q
  split:map("n", "q", function()
    M.close()
  end, { noremap = true })
end

--- Setup picker with view source
---@param source ViewSource
local function setup_picker(source)
  state.picker_instance = picker_mod.new(source, configs.explorer)
  state.picker_instance:mount(state.split.bufnr)
end

--- Explicitly mount the explorer (creates buffer + window)
--- Usually not needed - open() calls show() which mounts internally if needed
function M.mount()
  if state.split then
    return -- Already created
  end

  state.split = create_split()
  -- Note: We don't call split:mount() here, show() will do it
end

--- Explicitly unmount the explorer (destroys buffer + window, full cleanup)
--- Use this when you need to fully reset state or free resources
function M.unmount()
  if state.split then
    state.split:unmount()
    state.split = nil
  end
  state.picker_instance = nil
  state.current_view = nil
  state.data_loaded = false
end

--- Open the explorer with a specific view
--- Uses show() internally - mounts on first call, just shows window on subsequent calls
---@param view_name? string Name of the view to display (defaults to DEFAULT_VIEW)
function M.open(view_name)
  view_name = view_name or state.current_view or DEFAULT_VIEW

  local source = views[view_name]
  if not source then
    vim.notify("Unknown view: " .. view_name, vim.log.levels.ERROR)
    return
  end

  -- Create split if not exists
  if not state.split then
    state.split = create_split()
    setup_keymaps(state.split)
  end

  -- Show the split (mounts internally if not mounted)
  state.split:show()

  -- Setup picker if view changed or first time
  if state.current_view ~= view_name or not state.picker_instance then
    setup_picker(source)
    state.current_view = view_name
    state.data_loaded = false
  end

  -- Load data if not loaded
  if not state.data_loaded then
    state.picker_instance:load()
    state.data_loaded = true
  end
end

--- Close the explorer (hides window, preserves buffer + tree state)
function M.close()
  if state.split then
    state.split:hide()
  end
end

--- Toggle explorer visibility
---@param view_name? string View to open with (defaults to last view or DEFAULT_VIEW)
function M.toggle(view_name)
  -- Check if visible (has a valid window)
  if state.split and state.split.winid and vim.api.nvim_win_is_valid(state.split.winid) then
    M.close()
  else
    M.open(view_name)
  end
end

--- Switch to a different view
---@param view_name string
function M.switch_view(view_name)
  local source = views[view_name]
  if not source then
    vim.notify("Unknown view: " .. view_name, vim.log.levels.ERROR)
    return
  end

  -- If not open, just open with the new view
  if not state.split or not state.split.winid then
    M.open(view_name)
    return
  end

  -- Switch picker to new source
  setup_picker(source)
  state.picker_instance:load()
  state.current_view = view_name
  state.data_loaded = true
end

--- Refresh the current view (reload data from source)
function M.refresh()
  if state.picker_instance then
    state.picker_instance:load()
  end
end

--- Get the current picker instance (for external access)
---@return Picker|nil
function M.get_picker()
  return state.picker_instance
end

--- Check if explorer is visible (window is open)
---@return boolean
function M.is_open()
  return state.split ~= nil
    and state.split.winid ~= nil
    and vim.api.nvim_win_is_valid(state.split.winid)
end

--- Check if explorer is mounted (buffer exists, may or may not be visible)
---@return boolean
function M.is_mounted()
  return state.split ~= nil and state.split._.mounted
end

return M
