---
--- explorer/init.lua - Sidebar host for picker
---
--- Manages window lifecycle (show/hide/toggle).
--- Uses picker/manager to get picker instances.
--- Binds host-specific keymaps (q, 1, 2) to picker buffers.
--- Swaps displayed buffer on view switch.
---

local Split = require("nui.split")
local manager = require("neoweaver._internal.picker.manager")

local M = {}

local DEFAULT_VIEW = "collections"

--- Current state
local state = {
  ---@type string|nil
  current_view = nil,
  ---@type NuiSplit|nil
  split = nil,
}

--- Configuration
local config = {
  window = {
    position = "left",
    size = 30,
  },
}

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
    win_options = {
      number = false,
      relativenumber = false,
      cursorline = true,
      signcolumn = "no",
      wrap = false,
    },
  })
end

--- Setup host-specific keymaps on picker's buffer
---@param picker Picker
local function setup_host_keymaps(picker)
  if picker._host_keymaps_bound then
    return
  end

  local opts = { noremap = true, buffer = picker.bufnr }

  -- Close explorer
  vim.keymap.set("n", "q", function()
    M.close()
  end, opts)

  -- Switch views
  vim.keymap.set("n", "1", function()
    M.switch_view("collections")
  end, opts)

  vim.keymap.set("n", "2", function()
    M.switch_view("tags")
  end, opts)

  picker._host_keymaps_bound = true
end

--
-- Public API
--

--- Explicitly unmount the explorer (destroys window, force unmounts all pickers)
--- Use this when you need to fully reset state or free resources
function M.unmount()
  manager.unmount_all()

  if state.split then
    state.split:unmount()
    state.split = nil
  end

  state.current_view = nil
end

--- Open the explorer with a specific view
---@param view_name? string Name of the view to display (defaults to DEFAULT_VIEW)
function M.open(view_name)
  view_name = view_name or state.current_view or DEFAULT_VIEW

  -- Get or create picker (validates source exists)
  local picker = manager.get_or_create_picker(view_name)
  if not picker then
    vim.notify("Unknown view: " .. view_name, vim.log.levels.ERROR)
    return
  end

  -- Create split if not exists
  if not state.split then
    state.split = create_split()
  end

  -- Show the split (mounts internally if not mounted)
  state.split:show()

  -- Verify window was created successfully
  if not state.split.winid or not vim.api.nvim_win_is_valid(state.split.winid) then
    vim.notify("Failed to open explorer window", vim.log.levels.ERROR)
    return
  end

  -- Setup host keymaps on picker's buffer
  setup_host_keymaps(picker)

  -- Hide current picker if switching views
  if state.current_view and state.current_view ~= view_name then
    local current_picker = manager.get_or_create_picker(state.current_view)
    if current_picker then
      current_picker:onHide()
    end
  end

  -- Swap buffer displayed in split window
  vim.api.nvim_win_set_buf(state.split.winid, picker.bufnr)
  state.current_view = view_name

  -- Trigger show lifecycle (loads data, subscribes SSE)
  picker:onShow()
end

--- Close the explorer (hides window, picker starts idle timer)
function M.close()
  if state.current_view then
    local picker = manager.get_or_create_picker(state.current_view)
    if picker then
      picker:onHide()
    end
  end

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
  -- Skip if already on this view and explorer is open
  if state.current_view == view_name and M.is_open() then
    return
  end

  -- Delegate to open() which handles all view switching logic
  M.open(view_name)
end

--- Refresh the current view (reload data from source)
function M.refresh()
  if state.current_view then
    local picker = manager.get_or_create_picker(state.current_view)
    if picker then
      picker:refresh()
    end
  end
end

--- Get the current picker instance (for external access)
---@return Picker|nil
function M.get_picker()
  if state.current_view then
    return manager.get_or_create_picker(state.current_view)
  end
  return nil
end

--- Check if explorer is visible (window is open)
---@return boolean
function M.is_open()
  return state.split ~= nil
    and state.split.winid ~= nil
    and vim.api.nvim_win_is_valid(state.split.winid)
end

--- Check if explorer is mounted (split exists, may or may not be visible)
---@return boolean
function M.is_mounted()
  return state.split ~= nil and state.split._.mounted
end

return M
