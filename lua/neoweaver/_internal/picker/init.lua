--- Generic tree picker component using NuiTree
--- Lifecycle: onMount → onShow → onHide → onUnmount

local NuiTree = require("nui.tree")

local M = {}

local DEFAULT_IDLE_TIMEOUT = 300000 -- 5 minutes

---@class Picker
---@field source ViewSource
---@field config PickerConfig
---@field tree NuiTree|nil
---@field bufnr number|nil Buffer owned by this picker
---@field is_visible boolean
---@field on_unmount fun()|nil Callback for manager to remove picker from registry
---@field _event_unsub fun()|nil
---@field _idle_timer uv_timer_t|nil
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
  self.on_unmount = nil
  self._event_unsub = nil
  self._idle_timer = nil
  return self
end

function Picker:_start_idle_timer()
  self:_cancel_idle_timer()

  local timeout = self.source.idle_timeout or DEFAULT_IDLE_TIMEOUT
  local timer = vim.loop.new_timer()
  self._idle_timer = timer

  timer:start(
    timeout,
    0,
    vim.schedule_wrap(function()
      self:onUnmount()
    end)
  )
end

function Picker:_cancel_idle_timer()
  if self._idle_timer then
    self._idle_timer:stop()
    self._idle_timer:close()
    self._idle_timer = nil
  end
end

--- Creates buffer, tree, and keymaps
function Picker:onMount()
  self.bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(self.bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(self.bufnr, "bufhidden", "hide")
  vim.api.nvim_buf_set_option(self.bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(self.bufnr, "filetype", "neoweaver_picker")

  self.is_visible = false

  self.tree = NuiTree({
    bufnr = self.bufnr,
    prepare_node = self.source.prepare_node,
    nodes = {},
  })

  self:_bind_keymaps()
  self:_bind_navigation()
end

--- Loads data and subscribes to SSE
function Picker:onShow()
  self:_cancel_idle_timer()
  self.is_visible = true
  self:refresh()

  if self.source.event_types and #self.source.event_types > 0 then
    local api = require("neoweaver._internal.api")
    self._event_unsub = api.events.on(self.source.event_types, function(_event)
      if self.is_visible then
        self:refresh()
      end
    end)
  end
end

--- Pauses updates, starts idle timer
function Picker:onHide()
  self.is_visible = false
  self:_start_idle_timer()
end

--- Cleans up buffer, SSE, and notifies manager
function Picker:onUnmount()
  self:_cancel_idle_timer()

  if self._event_unsub then
    self._event_unsub()
    self._event_unsub = nil
  end

  if self.bufnr and vim.api.nvim_buf_is_valid(self.bufnr) then
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end

  if self.on_unmount then
    self.on_unmount()
  end

  self.tree = nil
  self.bufnr = nil
  self.is_visible = false
end

---@param on_complete? function
function Picker:load(on_complete)
  self.source.load_data(function(nodes, _stats)
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

  for _, node in ipairs(self.tree:get_nodes()) do
    collect_expanded(node)
  end

  return expanded_ids
end

---@param node_ids string[]
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

---@return string|number|nil
function Picker:_get_cursor_node_id()
  if not self.tree or not self.bufnr then
    return nil
  end

  local winid = vim.fn.win_findbuf(self.bufnr)[1]
  if not winid or not vim.api.nvim_win_is_valid(winid) then
    return nil
  end

  local node = self.tree:get_node()
  return node and node:get_id() or nil
end

---@param node_id string|number
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

--- Reload preserving expanded state and cursor
function Picker:refresh()
  local expanded_ids = self:_get_expanded_node_ids()
  local cursor_id = self:_get_cursor_node_id()

  self:load(function()
    self:_restore_expanded_nodes(expanded_ids)
    if cursor_id then
      self:_set_cursor_to_node(cursor_id)
    end
    if self.tree then
      self.tree:render()
    end
  end)
end

function Picker:_bind_keymaps()
  local opts = { noremap = true, nowait = true, buffer = self.bufnr }

  local refresh_cb = function()
    self:refresh()
  end

  for key, action_name in pairs(self.config.keymaps) do
    if action_name == "close" then -- luacheck: ignore 542
      -- Handled by host
    elseif action_name == "select" then
      vim.keymap.set("n", key, function()
        local node = self:get_node()
        if not node then
          return
        end

        if node:has_children() then
          if node:is_expanded() then
            node:collapse()
          else
            node:expand()
          end
          self.tree:render()
        else
          if self.source.actions.select then
            self.source.actions.select(node)
          end
        end
      end, opts)
    elseif self.source.actions[action_name] then
      vim.keymap.set("n", key, function()
        local node = self:get_node()
        self.source.actions[action_name](node, refresh_cb)
      end, opts)
    end
  end
end

function Picker:_bind_navigation()
  local opts = { noremap = true, nowait = true, buffer = self.bufnr }

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
