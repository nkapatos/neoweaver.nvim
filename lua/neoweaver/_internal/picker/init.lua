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
-- FUTURE: Server-Sent Events (SSE) vs Polling
--
-- Current approach: Client-side polling with configurable interval.
-- This works but has drawbacks:
-- - Unnecessary network traffic when no changes
-- - Latency between change and display (up to poll_interval)
-- - Wastes server resources
--
-- Future approach: SSE (Server-Sent Events) for push-based updates
-- - Server maintains long-lived connection
-- - Pushes change events when data mutates
-- - Client refreshes only when notified
--
-- Investigation path:
-- - plenary.curl may support long-lived connections for SSE
-- - Server would need SSE endpoint (e.g., /events/collections)
-- - Event types: collection_created, collection_updated, note_created, etc.
-- - Picker subscribes on onShow(), unsubscribes on onHide()
--
-- For now, polling is disabled (see onShow). Enable when ready to test.
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
---@param on_complete? function Optional callback after data is loaded and rendered
function Picker:load(on_complete)
  self.source.load_data(function(nodes, stats)
    if self.tree then
      self.tree:set_nodes(nodes)
      self.tree:render()
      if on_complete then
        on_complete()
      end
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

--
-- State Preservation
--
-- DESIGN DECISION: Full reload with state preservation (MVP approach)
--
-- Why full reload instead of targeted tree mutations:
-- - Simple and reliable - works for all CRUD scenarios
-- - NuiTree does support add_node/remove_node/set_nodes(nodes, parent_id) for targeted updates
-- - However, targeted updates require knowing exactly what changed and where
-- - For MVP, full reload is acceptable since tree data is small (<1000 nodes typically)
-- - State preservation makes the reload feel seamless to users
--
-- Future optimization path (smart_refresh):
-- - After create: tree:add_node(new_node, parent_id)
-- - After delete: tree:remove_node(node_id)
-- - After rename: just update node properties and re-render (no reload needed)
-- - This avoids network round-trip but requires careful state management
--

--- Get all expanded node IDs from current tree
--- Walks tree recursively and collects IDs where node:is_expanded() == true
---@return string[] Array of node IDs that are expanded
function Picker:_get_expanded_node_ids()
  local expanded_ids = {}

  if not self.tree then
    return expanded_ids
  end

  local function collect_expanded(node)
    if node:is_expanded() then
      table.insert(expanded_ids, node:get_id())
    end
    if node:has_children() then
      for _, child in ipairs(self.tree:get_nodes(node:get_id())) do
        collect_expanded(child)
      end
    end
  end

  -- Walk all root nodes
  for _, node in ipairs(self.tree:get_nodes()) do
    collect_expanded(node)
  end

  return expanded_ids
end

--- Restore expanded state for nodes by ID
--- Nodes that no longer exist are silently skipped
---@param node_ids string[] Array of node IDs to expand
function Picker:_restore_expanded_nodes(node_ids)
  if not self.tree then
    return
  end

  for _, id in ipairs(node_ids) do
    local node = self.tree:get_node(id)
    if node then
      node:expand()
    end
  end
end

--- Get the node ID under cursor
---@return string|number|nil Node ID at cursor, or nil
function Picker:_get_cursor_node_id()
  if not self.tree or not self.bufnr then
    return nil
  end

  -- Find window containing our buffer
  local winid = vim.fn.win_findbuf(self.bufnr)[1]
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return nil
  end

  local node = self.tree:get_node()
  return node and node:get_id() or nil
end

--- Move cursor to a specific node by ID
--- Falls back gracefully if node doesn't exist (cursor stays where it is)
---@param node_id string|number Node ID to focus
function Picker:_set_cursor_to_node(node_id)
  if not self.tree or not self.bufnr or not node_id then
    return
  end

  local node, start_lnum, _ = self.tree:get_node(node_id)
  if node and start_lnum then
    local winid = vim.fn.win_findbuf(self.bufnr)[1]
    if winid and vim.api.nvim_win_is_valid(winid) then
      vim.api.nvim_win_set_cursor(winid, { start_lnum, 0 })
    end
  end
end

--- Refresh the tree with state preservation
--- Captures expanded nodes and cursor position, reloads data, then restores state
--- This is the primary method actions should call after mutations
function Picker:refresh()
  local expanded_ids = self:_get_expanded_node_ids()
  local cursor_id = self:_get_cursor_node_id()

  self:load(function()
    self:_restore_expanded_nodes(expanded_ids)
    if cursor_id then
      self:_set_cursor_to_node(cursor_id)
    end
    -- Re-render to reflect restored expanded state
    if self.tree then
      self.tree:render()
    end
  end)
end

--
-- Keymaps
--

--- Bind action keymaps from config
---
--- DESIGN DECISION: Refresh callback pattern
---
--- Actions that mutate data (create, rename, delete) receive a refresh_cb parameter.
--- After successful mutation, the action calls refresh_cb() to trigger tree reload.
---
--- Why callback instead of return value:
--- - Actions are async (API calls use callbacks)
--- - Action decides when/if to refresh (e.g., skip refresh if user cancels)
--- - Keeps picker generic - doesn't know which actions mutate data
---
--- Note: "select" action does NOT receive refresh_cb since it doesn't mutate data.
---
function Picker:_bind_keymaps()
  local opts = { noremap = true, nowait = true, buffer = self.bufnr }

  -- Refresh callback for mutation actions
  local refresh_cb = function()
    self:refresh()
  end

  for key, action_name in pairs(self.config.keymaps) do
    if action_name == "close" then
      -- Special case: close is handled by host (explorer), not source
      -- Skip for now, explorer will handle this
    elseif action_name == "select" then
      -- Special case: select handles tree operations (expand/collapse) or delegates to source
      -- Note: select does NOT get refresh_cb - it doesn't mutate data
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
      -- Mutation actions (create, rename, delete) receive refresh callback
      vim.keymap.set("n", key, function()
        local node = self:get_node()
        self.source.actions[action_name](node, refresh_cb)
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
