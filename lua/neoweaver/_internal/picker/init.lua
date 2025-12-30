---
--- picker/init.lua - Generic tree picker component with lifecycle hooks
---
--- PURPOSE:
--- Self-contained, host-agnostic component that displays hierarchical data using NuiTree.
--- Manages its own data loading and polling based on lifecycle events.
--- Can be hosted in any buffer (sidebar, floating window, embedded).
---
--- ARCHITECTURE DECISION RECORD (ADR):
---
--- The picker is designed as a generic, reusable tree component that:
---
--- 1. OWNS THE TREE: Picker creates and manages the NuiTree instance. It handles
---    all tree operations: rendering, navigation, expand/collapse, cursor position,
---    and state preservation (expanded nodes, cursor) on refresh.
---
--- 2. DELEGATES TO VIEWSOURCE: Picker doesn't know about domain-specific data.
---    It receives a ViewSource that provides:
---    - load_data(callback): Fetches data, returns NuiTree.Node[] with domain properties
---    - prepare_node(node): Renders node to NuiLine[] using domain knowledge
---    - actions: CRUD handlers that receive (node, refresh_callback)
---
--- 3. HOST-AGNOSTIC: Picker doesn't create windows. A host (explorer sidebar,
---    floating window, embedded buffer) provides the bufnr and calls lifecycle hooks.
---    The same picker can be displayed anywhere.
---
--- 4. LIFECYCLE-DRIVEN: Hosts control picker via lifecycle hooks:
---    - onMount(bufnr): Attach to buffer, create tree, bind keymaps
---    - onShow(): Load data, start polling (if configured)
---    - onHide(): Stop polling, preserve state
---    - onUnmount(): Full cleanup
---
--- 5. ACTION FLOW: When user triggers an action (e.g., delete):
---    - Picker gets node from tree (has domain properties like is_system)
---    - Picker calls source.actions.delete(node, refresh_callback)
---    - ViewSource validates (e.g., can't delete system collections)
---    - ViewSource calls API
---    - ViewSource calls refresh_callback() to trigger picker reload
---
--- 6. POLLING: Picker manages polling timer internally based on source.poll_interval.
---    Polling starts on onShow(), stops on onHide(). This ensures no wasted
---    network calls when picker is hidden.
---
--- WHY VIEWSOURCE RETURNS NuiTree.Node[]:
--- - Domain knows the data shape (is_system, collection_id, note_id, etc.)
--- - These properties are attached to NuiTree.Node and preserved
--- - prepare_node() uses these properties for rendering
--- - Actions use these properties for validation (e.g., can't delete system collections)
--- - Keeps picker generic - it just passes nodes around
---
--- RESPONSIBILITIES:
--- - Create and manage NuiTree instance
--- - Bind keymaps based on PickerConfig
--- - Delegate actions to ViewSource.actions with refresh callback
--- - Handle tree navigation (expand/collapse, cursor movement)
--- - Preserve tree state (expanded nodes, cursor) on refresh
--- - Manage data loading lifecycle (load on show, poll while visible)
--- - Start/stop polling based on visibility (onShow/onHide)
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
    elseif action_name == "select" then
      -- Special case: select handles tree operations (expand/collapse) or delegates to source
      vim.keymap.set("n", key, function()
        local node = self:get_node()
        if not node then
          return
        end

        -- If node has children, toggle expand/collapse (tree operation)
        if node:has_children() then
          if node:is_expanded() then
            node:collapse()
          else
            node:expand()
          end
          self.tree:render()
        else
          -- Leaf node: delegate to ViewSource for domain-specific action
          if self.source.actions.select then
            self.source.actions.select(node)
          end
        end
      end, opts)
    elseif self.source.actions[action_name] then
      vim.keymap.set("n", key, function()
        local node = self:get_node()
        -- TODO: Pass refresh callback to actions once we finalize the pattern
        -- self.source.actions[action_name](node, function() self:load() end)
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
