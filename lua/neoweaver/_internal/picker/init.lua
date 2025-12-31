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
---@field poll_timer uv_timer_t|nil Timer handle for polling
---@field is_visible boolean Visibility state
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
  self.poll_timer = nil
  self.is_visible = false
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

--- Load data and start polling (future: SSE will replace polling)
function Picker:onShow()
  self.is_visible = true
  self:refresh()
  -- TODO: Enable polling when ready
  -- self:_start_polling()
end

--- Stop polling, preserve tree state
function Picker:onHide()
  self.is_visible = false
  self:_stop_polling()
end

--- Full cleanup
function Picker:onUnmount()
  self:_stop_polling()
  self.tree = nil
  self.bufnr = nil
  self.is_visible = false
end

--
-- Polling (TODO: Replace with SSE for push-based updates)
--

function Picker:_start_polling()
  local interval = self.source.poll_interval
  if not interval then
    return
  end

  self:_stop_polling()

  self.poll_timer = vim.loop.new_timer()
  self.poll_timer:start(interval, interval, vim.schedule_wrap(function()
    if self.is_visible then
      self:load()
    end
  end))
end

function Picker:_stop_polling()
  if not self.poll_timer then
    return
  end
  self.poll_timer:stop()
  self.poll_timer:close()
  self.poll_timer = nil
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
