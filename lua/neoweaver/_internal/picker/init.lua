---
--- picker/init.lua - Generic tree picker component with lifecycle hooks
---
--- PURPOSE:
--- Self-contained, host-agnostic component that displays hierarchical data using NuiTree.
--- Manages its own data loading and polling based on lifecycle events.
--- Can be hosted in any buffer (sidebar, floating window, embedded).
---
--- RESPONSIBILITIES:
--- - Create and manage NuiTree instance
--- - Bind keymaps based on PickerConfig
--- - Delegate actions to ViewSource.actions
--- - Handle tree navigation (expand/collapse, cursor movement)
--- - Manage data loading lifecycle (load on show, poll while visible)
--- - Start/stop polling based on visibility (onShow/onHide)
---
--- LIFECYCLE HOOKS:
--- - onMount(bufnr): Called when picker is attached to a buffer
--- - onShow(): Called when picker becomes visible (triggers load + polling)
--- - onHide(): Called when picker is hidden (stops polling)
--- - onUnmount(): Called on full cleanup (stops polling, clears state)
---
--- DOES NOT:
--- - Know about specific domains (collections, tags, etc.)
--- - Create windows (host's responsibility)
--- - Define what actions mean (ViewSource's responsibility)
--- - Know where it's displayed (host-agnostic)
---
--- USAGE:
--- local picker = require("neoweaver._internal.picker")
--- local my_picker = picker.new(view_source, config)
--- my_picker:onMount(bufnr)
--- my_picker:onShow()    -- triggers load + starts polling
--- my_picker:onHide()    -- stops polling
--- my_picker:onUnmount() -- full cleanup
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
---@field poll_timer uv_timer_t|nil Timer handle for polling
---@field is_visible boolean Visibility state
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
  self.poll_timer = nil
  self.is_visible = false
  return self
end

--
-- Lifecycle Hooks
--

--- Mount the picker to a buffer
--- Called once when picker is attached to a buffer
---@param bufnr number Buffer number to render into
function Picker:onMount(bufnr)
  self.bufnr = bufnr
  self.is_visible = false

  -- Create NuiTree with source's prepare_node for rendering
  self.tree = NuiTree({
    bufnr = bufnr,
    prepare_node = self.source.prepare_node,
    nodes = {}, -- Start empty, onShow will trigger load
  })

  -- Bind keymaps from config, delegating to source.actions
  self:_bind_keymaps()

  -- Bind navigation keymaps (always present)
  self:_bind_navigation()
end

--- Called when picker becomes visible
--- Triggers data load and starts polling if configured
function Picker:onShow()
  self.is_visible = true
  -- TODO: Consider adding staleness check to avoid reload if data is fresh
  self:load()
  -- TODO: Re-enable polling once load_data is implemented with actual API calls
  -- self:_start_polling()
end

--- Called when picker is hidden
--- Stops polling to avoid unnecessary network calls
function Picker:onHide()
  self.is_visible = false
  self:_stop_polling()
end

--- Called on full cleanup
--- Stops polling and clears all state
function Picker:onUnmount()
  self:_stop_polling()
  self.tree = nil
  self.bufnr = nil
  self.is_visible = false
end

--
-- Polling
--

--- Start polling timer based on source.poll_interval
--- Polling only runs while picker is visible
function Picker:_start_polling()
  local interval = self.source.poll_interval
  if not interval then
    return
  end

  -- Stop any existing timer first
  self:_stop_polling()

  self.poll_timer = vim.loop.new_timer()
  self.poll_timer:start(interval, interval, vim.schedule_wrap(function()
    if self.is_visible then
      vim.notify("[picker:" .. self.source.name .. "] polling tick", vim.log.levels.INFO)
      self:load()
    end
  end))

  vim.notify("[picker:" .. self.source.name .. "] polling started: " .. interval .. "ms", vim.log.levels.INFO)
end

--- Stop polling timer if running
function Picker:_stop_polling()
  if not self.poll_timer then
    return
  end

  vim.notify("[picker:" .. self.source.name .. "] polling stopped", vim.log.levels.INFO)
  self.poll_timer:stop()
  self.poll_timer:close()

  -- TODO: Implement actual timer stop
  -- self.poll_timer:stop()
  -- self.poll_timer:close()
  self.poll_timer = nil
end

--
-- Data Loading
--

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

--
-- Keymaps
--

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

return M
