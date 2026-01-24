--- Floating picker window host
local Popup = require("nui.popup")
local Picker = require("neoweaver._internal.picker")
local picker_manager = require("neoweaver._internal.picker.manager")

local M = {}

---@class FloatingPicker
---@field picker Picker
---@field popup NuiPopup
local FloatingPicker = {}
FloatingPicker.__index = FloatingPicker

---@param source ViewSource
---@param config PickerConfig
---@return FloatingPicker
function M.new(source, config)
  local self = setmetatable({}, FloatingPicker)

  -- Every floating picker is ephemeral and should have its own source instance
  -- to avoid conflicts in the manager.
  local source_id = source.name .. ":" .. os.clock()

  -- Wrap the original select action to close the picker after selection
  local original_select = source.actions and source.actions.select
  if original_select then
    source.actions.select = function(...)
      original_select(...)
      self:unmount() -- Close and clean up after action
    end
  end

  picker_manager.register_source(source_id, source)

  self.picker = picker_manager.get_or_create_picker(source_id, config)

  self.popup = Popup({
    enter = true,
    bufnr = self.picker.bufnr,
    relative = "editor",
    position = "50%",
    size = {
      width = "80%",
      height = "80%",
    },
    border = {
      style = "rounded",
      text = {
        top = " " .. (source.title or "Picker") .. " ",
        top_align = "center",
      },
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
      cursorline = true,
      signcolumn = "no",
      wrap = false,
    },
    on_unmount = function()
      -- Full cleanup when the popup is unmounted for any reason (selection, manual close)
      picker_manager.delete_picker(source_id)
      picker_manager.unregister_source(source_id)
    end,
  })

  self:_bind_host_keymaps()
  return self
end

function FloatingPicker:show()
  self.popup:mount()
  self.picker:onShow()
end

function FloatingPicker:hide()
  self.popup:unmount()
  self.picker:onHide()
end

function FloatingPicker:unmount()
  self.popup:unmount()
  self.picker:onUnmount()
end

function FloatingPicker:_bind_host_keymaps()
  local opts = { noremap = true, nowait = true, buffer = self.picker.bufnr }

  -- The picker's own keymaps will handle <CR> for selection.
  -- We only need to handle closing the host window.

  vim.keymap.set("n", "q", function()
    self:unmount()
  end, opts)

  vim.keymap.set("n", "<Esc>", function()
    self:unmount()
  end, opts)
end

return M
