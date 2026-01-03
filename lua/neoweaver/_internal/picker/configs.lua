--- picker/configs.lua - Keymap configurations for different hosts

local M = {}

---@type PickerConfig
M.explorer = {
  keymaps = {
    ["<CR>"] = "select",
    ["o"] = "select",
    ["a"] = "create",
    ["r"] = "rename",
    ["d"] = "delete",
  },
}

---@type PickerConfig
M.floating = {
  keymaps = {
    ["<CR>"] = "select",
    ["q"] = "close",
    ["<Esc>"] = "close",
  },
}

return M
