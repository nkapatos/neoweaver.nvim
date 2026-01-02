---
--- picker/init.lua - Generic tree picker component
---
--- Host-agnostic tree viewer using NuiTree. Hosts (explorer, floating window)
--- provide a buffer and call lifecycle hooks. ViewSource provides domain data.
---
--- Lifecycle: onMount(bufnr) → onShow() → onHide() → onUnmount()
--- ViewSource interface: { load_data, prepare_node, actions, poll_interval? }
---

local NuiTree = require("nui.tree")

local M = {}

---@class Picker
---@field source ViewSource
---@field config PickerConfig
---@field tree NuiTree|nil
---@field bufnr number|nil
---@field is_visible boolean Visibility state
---@field _event_unsub fun()|nil Unsubscribe function for SSE events
local Picker = {}
Picker.__index = Picker

---@param source ViewSource
---@param config PickerConfig
---@return Picker
function M.new(source, config)
  local self = setmetatable({}, Picker)
  self.source = source
  self.config = config
  self.tree = nil
  self.bufnr = nil
  self.is_visible = false
  self._event_unsub = nil
  return self
end

--
-- Lifecycle Hooks
--

--- Attach picker to buffer, create tree, bind keymaps
---@param bufnr number
function Picker:onMount(bufnr)
  self.bufnr = bufnr
  self.is_visible = false

  self.tree = NuiTree({
    bufnr = bufnr,
    prepare_node = self.source.prepare_node,
    nodes = {},
  })

  self:_bind_keymaps()
  self:_bind_navigation()
end

--- Load data and subscribe to SSE events for live updates
function Picker:onShow()
  self.is_visible = true
  self:refresh()

  -- Subscribe to SSE events if ViewSource declares event_types
  if self.source.event_types and #self.source.event_types > 0 then
    local api = require("neoweaver._internal.api")
    self._event_unsub = api.events.on(self.source.event_types, function(_event)
      if self.is_visible then
        self:refresh()
      end
    end)
  end
end

--- Pause updates, preserve tree state
function Picker:onHide()
  self.is_visible = false
end

--- Full cleanup
function Picker:onUnmount()
  -- Unsubscribe from SSE events to prevent memory leaks
  if self._event_unsub then
    self._event_unsub()
    self._event_unsub = nil
  end

  self.tree = nil
  self.bufnr = nil
  self.is_visible = false
end

--
-- Data Loading
--

---@param on_complete? function
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

---@return NuiTree.Node|nil
function Picker:get_node()
  if not self.tree then
    return nil
  end
  return self.tree:get_node()
end

--
-- State Preservation (preserves expanded nodes and cursor across reloads)
--

---@return string[]
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
--- Mutation actions (create, rename, delete) receive refresh_cb; select does not.
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
