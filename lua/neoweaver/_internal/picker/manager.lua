---
--- picker/manager.lua - Global registry for ViewSources and Picker instances
---
--- Manages ViewSource registration and lazy Picker instantiation.
--- Each source has at most one picker instance at a time.
--- Pickers self-remove from registry on unmount (via idle timeout or explicit).
---
--- NOTE: Consider exposing list_sources() for future UI like view switcher dropdown.
---

local picker_mod = require("neoweaver._internal.picker")
local configs = require("neoweaver._internal.picker.configs")

local M = {}

--- Registered ViewSources
---@type table<string, ViewSource>
local sources = {}

--- Active Picker instances (one per source)
---@type table<string, Picker>
local pickers = {}

--- Register a ViewSource
--- Called by domain modules to make their view available
---@param name string Source name (e.g., "collections", "tags")
---@param source ViewSource The view source implementation
function M.register_source(name, source)
  sources[name] = source
end

--- Get a registered ViewSource by name
---@param name string Source name
---@return ViewSource|nil
function M.get_source(name)
  return sources[name]
end

--- Get existing picker or create new one for a source
--- Picker is created lazily on first request and cached.
--- Returns nil if source is not registered.
---@param source_name string Name of the registered source
---@return Picker|nil
function M.get_or_create_picker(source_name)
  -- Check if valid picker exists
  if pickers[source_name] then
    local picker = pickers[source_name]
    if picker.bufnr and vim.api.nvim_buf_is_valid(picker.bufnr) then
      return picker
    end
    -- Stale picker, remove it
    pickers[source_name] = nil
  end

  -- Get source
  local source = sources[source_name]
  if not source then
    return nil
  end

  -- Create and mount new picker
  local picker = picker_mod.new(source, configs.explorer)
  picker:onMount()

  -- Set callback for self-removal on unmount
  picker.on_unmount = function()
    pickers[source_name] = nil
  end

  pickers[source_name] = picker
  return picker
end

--- Remove a picker from registry
--- Called internally when picker unmounts itself
---@param source_name string
function M.remove_picker(source_name)
  pickers[source_name] = nil
end

--- Force unmount all pickers
function M.unmount_all()
  for _, picker in pairs(pickers) do
    picker:onUnmount()
  end
  pickers = {}
end

return M
