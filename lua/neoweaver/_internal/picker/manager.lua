--- Global registry for ViewSources and Picker instances

local picker_mod = require("neoweaver._internal.picker")
local configs = require("neoweaver._internal.picker.configs")

local M = {}

---@type table<string, ViewSource>
local sources = {}

---@type table<string, Picker>
local pickers = {}

---@param name string
---@param source ViewSource
function M.register_source(name, source)
  sources[name] = source
end

---@param name string
---@return ViewSource|nil
function M.get_source(name)
  return sources[name]
end

---@param source_name string
---@return Picker|nil
function M.get_or_create_picker(source_name)
  if pickers[source_name] then
    local picker = pickers[source_name]
    if picker.bufnr and vim.api.nvim_buf_is_valid(picker.bufnr) then
      return picker
    end
    pickers[source_name] = nil
  end

  local source = sources[source_name]
  if not source then
    return nil
  end

  local picker = picker_mod.new(source, configs.explorer)
  picker:onMount()

  picker.on_unmount = function()
    pickers[source_name] = nil
  end

  pickers[source_name] = picker
  return picker
end

---@param source_name string
function M.remove_picker(source_name)
  pickers[source_name] = nil
end

function M.unmount_all()
  for _, picker in pairs(pickers) do
    picker:onUnmount()
  end
  pickers = {}
end

return M
