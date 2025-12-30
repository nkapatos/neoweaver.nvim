---
--- explorer/init.lua - Sidebar host for the picker
---
--- PURPOSE:
--- Thin window host that creates a sidebar and manages picker visibility.
--- Does NOT know about data loading, polling, or domain-specific logic.
---
--- RESPONSIBILITIES:
--- - Create/manage the sidebar window (split)
--- - Manage picker lifecycle (onMount/onShow/onHide/onUnmount)
--- - Handle window lifecycle (open, close, toggle)
--- - Manage idle timeout for resource cleanup
--- - Delegate view switching
---
--- DOES NOT:
--- - Know how to render domain-specific nodes (picker + ViewSource do that)
--- - Know about CRUD logic (ViewSource.actions handles that)
--- - Know about polling intervals (picker manages this)
--- - Manage data loading directly (picker's onShow handles this)
---
--- LIFECYCLE:
--- - open()/close() use show()/hide() for fast toggle (preserves buffer + tree state)
--- - close() starts idle timer; reopen cancels it
--- - Idle timer expiry triggers full unmount (cleanup resources)
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
  ---@type uv_timer_t|nil
  idle_timer = nil,
}

--- Configuration
local config = {
  window = {
    position = "left",
    size = 30,
  },
  idle_timeout = 60000, -- 60 seconds default
}

--- Register a view source
--- Called by domain modules to make their view available
---@param name string View name (e.g., "collections", "tags")
---@param source ViewSource The view source implementation
function M.register_view(name, source)
  views[name] = source
end

--
-- Idle Timer Management
--

--- Start idle timer for cleanup after close
function M._start_idle_timer()
  M._cancel_idle_timer()

  local timer = vim.loop.new_timer()
  state.idle_timer = timer

  timer:start(config.idle_timeout, 0, vim.schedule_wrap(function()
    timer:stop()
    timer:close()
    state.idle_timer = nil
    M.unmount()
  end))
end

--- Cancel pending idle timer
function M._cancel_idle_timer()
  if state.idle_timer then
    state.idle_timer:stop()
    state.idle_timer:close()
    state.idle_timer = nil
  end
end

--
-- Window Management
--

--- Create the sidebar split (does not mount)
---@return NuiSplit
local function create_split()
  return Split({
    relative = "editor",
    position = config.window.position,
    size = config.window.size,
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
end

--
-- Public API
--

--- Explicitly unmount the explorer (destroys buffer + window, full cleanup)
--- Use this when you need to fully reset state or free resources
function M.unmount()
  M._cancel_idle_timer()

  if state.picker_instance then
    state.picker_instance:onUnmount()
    state.picker_instance = nil
  end

  if state.split then
    state.split:unmount()
    state.split = nil
  end

  state.current_view = nil
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

  -- Cancel idle timer if pending
  M._cancel_idle_timer()

  -- Create split if not exists
  if not state.split then
    state.split = create_split()
    setup_keymaps(state.split)
  end

  -- Show the split (mounts internally if not mounted)
  state.split:show()

  -- Setup picker if view changed or first time
  if state.current_view ~= view_name or not state.picker_instance then
    -- Hide old picker if exists (stops its polling)
    if state.picker_instance then
      state.picker_instance:onHide()
    end

    setup_picker(source)
    state.picker_instance:onMount(state.split.bufnr)
    state.current_view = view_name
  end

  -- Trigger show lifecycle (loads data, starts polling)
  state.picker_instance:onShow()
end

--- Close the explorer (hides window, preserves buffer + tree state)
function M.close()
  if state.picker_instance then
    state.picker_instance:onHide() -- stops polling
  end

  if state.split then
    state.split:hide()
  end

  -- Start idle timer for cleanup
  M._start_idle_timer()
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

  -- Hide old picker (stops polling)
  if state.picker_instance then
    state.picker_instance:onHide()
  end

  -- Setup and show new picker
  setup_picker(source)
  state.picker_instance:onMount(state.split.bufnr)
  state.picker_instance:onShow()
  state.current_view = view_name
end

--- Refresh the current view (reload data from source)
function M.refresh()
  if state.picker_instance then
    state.picker_instance:refresh()
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
